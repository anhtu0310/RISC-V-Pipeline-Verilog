`timescale 1ns / 1ps

// SoC: RV32I core + unified code/data RAM + GPIO, UART, I2C and SPI.
//
// Memory map
//   0x0000_0000 - RAM_BYTES-1   RAM (code, data, stack). Instruction fetch
//                               uses port A, loads/stores use port B.
//   0x1000_0000                 GPIO   (rtl/periph/gpio.v)
//   0x1000_1000                 UART   (rtl/periph/uart.v)
//   0x1000_2000                 I2C    (rtl/periph/i2c_master.v)
//   0x1000_3000                 SPI    (rtl/periph/spi_master.v)
//   anything else               Unmapped: writes ignored, reads return 0
//
// Each peripheral owns a 4 KiB page (only the first 64 words are decoded,
// so registers alias within the page). Register maps are in the header of
// each peripheral and in sw/common/soc.h.
//
// Data bus timing (see rv32i_core.v): request in one cycle, read data due
// the next cycle. Every slave registers its read data, and the read mux
// below uses the slave selection registered alongside the request.
module soc_top #(
    parameter integer RAM_ADDR_WIDTH = 12,       // 2**12 words = 16 KiB
    parameter         INIT_FILE      = "",
    parameter [31:0]  RESET_ADDR     = 32'h0000_0000,
    parameter integer CLK_HZ         = 100_000_000,
    parameter integer UART_BAUD      = 115_200,   // reset value of UART BAUD_DIV
    parameter integer I2C_HZ         = 100_000,   // reset value of I2C PRESCALE
    parameter integer GPIO_N         = 32
) (
    input  wire              clk,
    input  wire              rst_n,

    // GPIO (gpio_oe = 1: pin is an output)
    input  wire [GPIO_N-1:0] gpio_in,
    output wire [GPIO_N-1:0] gpio_out,
    output wire [GPIO_N-1:0] gpio_oe,

    // UART
    output wire              uart_tx,
    input  wire              uart_rx,

    // I2C, open drain: *_oe = 1 pulls the line low, else release (pull-up)
    input  wire              i2c_scl_i,
    output wire              i2c_scl_oe,
    input  wire              i2c_sda_i,
    output wire              i2c_sda_oe,

    // SPI
    output wire              spi_sclk,
    output wire              spi_mosi,
    input  wire              spi_miso,
    output wire [3:0]        spi_cs_n
);

    localparam [31:0] RAM_BYTES = 32'd4 << RAM_ADDR_WIDTH;

    // Reset values of the UART divider and I2C prescaler (16-bit registers).
    /* verilator lint_off WIDTHTRUNC */
    localparam [15:0] UART_DIV     = CLK_HZ / UART_BAUD;
    localparam [15:0] I2C_PRESCALE = CLK_HZ / (4 * I2C_HZ) - 1;
    /* verilator lint_on WIDTHTRUNC */

    // ------------------------------------------------------------------
    // Core
    // ------------------------------------------------------------------
    // Only the word-index bits of the addresses are decoded.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] imem_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [31:0] imem_rdata;
    wire        imem_en;
    wire [31:0] dbus_addr, dbus_wdata, dbus_rdata;
    wire [3:0]  dbus_wstrb;
    wire        dbus_we, dbus_re;

    rv32i_core #(
        .RESET_ADDR (RESET_ADDR)
    ) u_core (
        .clk           (clk),
        .rst_n         (rst_n),
        .imem_addr     (imem_addr),
        .imem_en       (imem_en),
        .imem_rdata    (imem_rdata),
        .dbus_addr     (dbus_addr),
        .dbus_wdata    (dbus_wdata),
        .dbus_wstrb    (dbus_wstrb),
        .dbus_we       (dbus_we),
        .dbus_re       (dbus_re),
        .dbus_rdata    (dbus_rdata),
        // Trace port is for testbenches; left open here.
        /* verilator lint_off PINCONNECTEMPTY */
        .trace_valid   (),
        .trace_pc      (),
        .trace_instr   (),
        .trace_rd_we   (),
        .trace_rd      (),
        .trace_rd_data ()
        /* verilator lint_on PINCONNECTEMPTY */
    );

    // ------------------------------------------------------------------
    // Address decode
    // ------------------------------------------------------------------
    wire sel_ram    = (dbus_addr < RAM_BYTES);
    wire sel_periph = (dbus_addr[31:16] == 16'h1000);
    wire [3:0] page = dbus_addr[15:12];

    wire sel_gpio = sel_periph && page == 4'd0;
    wire sel_uart = sel_periph && page == 4'd1;
    wire sel_i2c  = sel_periph && page == 4'd2;
    wire sel_spi  = sel_periph && page == 4'd3;

    // Read data steering: remember which slave a read went to.
    localparam [2:0] RD_NONE = 3'd0, RD_RAM = 3'd1, RD_GPIO = 3'd2,
                     RD_UART = 3'd3, RD_I2C = 3'd4, RD_SPI  = 3'd5;
    reg [2:0] rd_sel_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rd_sel_q <= RD_NONE;
        else if (!dbus_re)
            rd_sel_q <= RD_NONE;
        else if (sel_ram)  rd_sel_q <= RD_RAM;
        else if (sel_gpio) rd_sel_q <= RD_GPIO;
        else if (sel_uart) rd_sel_q <= RD_UART;
        else if (sel_i2c)  rd_sel_q <= RD_I2C;
        else if (sel_spi)  rd_sel_q <= RD_SPI;
        else               rd_sel_q <= RD_NONE;
    end

    // ------------------------------------------------------------------
    // RAM
    // ------------------------------------------------------------------
    wire [31:0] ram_rdata;

    dp_ram #(
        .ADDR_WIDTH (RAM_ADDR_WIDTH),
        .INIT_FILE  (INIT_FILE)
    ) u_ram (
        .clk     (clk),
        .a_en    (imem_en),
        .a_addr  (imem_addr[RAM_ADDR_WIDTH+1:2]),
        .a_rdata (imem_rdata),
        .b_en    (sel_ram && (dbus_re || dbus_we)),
        .b_wstrb (dbus_we ? dbus_wstrb : 4'b0000),
        .b_addr  (dbus_addr[RAM_ADDR_WIDTH+1:2]),
        .b_wdata (dbus_wdata),
        .b_rdata (ram_rdata)
    );

    // ------------------------------------------------------------------
    // Peripherals
    // ------------------------------------------------------------------
    wire [31:0] gpio_rdata, uart_rdata, i2c_rdata, spi_rdata;
    wire [5:0]  reg_addr = dbus_addr[7:2];

    gpio #(
        .N (GPIO_N)
    ) u_gpio (
        .clk (clk), .rst_n (rst_n),
        .sel (sel_gpio), .we (dbus_we), .re (dbus_re), .addr (reg_addr),
        .wdata (dbus_wdata), .wstrb (dbus_wstrb), .rdata (gpio_rdata),
        .gpio_in (gpio_in), .gpio_out (gpio_out), .gpio_oe (gpio_oe)
    );

    uart #(
        .DEFAULT_DIV (UART_DIV)
    ) u_uart (
        .clk (clk), .rst_n (rst_n),
        .sel (sel_uart), .we (dbus_we), .re (dbus_re), .addr (reg_addr),
        .wdata (dbus_wdata), .wstrb (dbus_wstrb), .rdata (uart_rdata),
        .uart_tx (uart_tx), .uart_rx (uart_rx)
    );

    i2c_master #(
        .DEFAULT_PRESCALE (I2C_PRESCALE)
    ) u_i2c (
        .clk (clk), .rst_n (rst_n),
        .sel (sel_i2c), .we (dbus_we), .re (dbus_re), .addr (reg_addr),
        .wdata (dbus_wdata), .wstrb (dbus_wstrb), .rdata (i2c_rdata),
        .scl_i (i2c_scl_i), .scl_oe (i2c_scl_oe),
        .sda_i (i2c_sda_i), .sda_oe (i2c_sda_oe)
    );

    spi_master #(
        .NCS (4)
    ) u_spi (
        .clk (clk), .rst_n (rst_n),
        .sel (sel_spi), .we (dbus_we), .re (dbus_re), .addr (reg_addr),
        .wdata (dbus_wdata), .wstrb (dbus_wstrb), .rdata (spi_rdata),
        .spi_sclk (spi_sclk), .spi_mosi (spi_mosi), .spi_miso (spi_miso),
        .spi_cs_n (spi_cs_n)
    );

    // ------------------------------------------------------------------
    // Read data mux
    // ------------------------------------------------------------------
    reg [31:0] rdata_mux;
    always @(*) begin
        case (rd_sel_q)
            RD_RAM:  rdata_mux = ram_rdata;
            RD_GPIO: rdata_mux = gpio_rdata;
            RD_UART: rdata_mux = uart_rdata;
            RD_I2C:  rdata_mux = i2c_rdata;
            RD_SPI:  rdata_mux = spi_rdata;
            default: rdata_mux = 32'd0;
        endcase
    end

    assign dbus_rdata = rdata_mux;

endmodule
