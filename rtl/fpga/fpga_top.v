`timescale 1ns / 1ps

// Board-level wrapper for soc_top: bidirectional GPIO pads, open-drain I2C
// pads and a reset synchroniser. Connect the ports to your board's pins in
// the constraint file and add pull-ups on I2C SCL/SDA (on the board, or
// the FPGA's internal pull-ups for short wires and slow clocks).
//
// INIT_FILE is the program image ($readmemh), e.g. sw/build/uart_test.hex
// or your own program built with sw/common/crt0.S + link.ld.
module fpga_top #(
    parameter         INIT_FILE = "",
    parameter integer CLK_HZ    = 100_000_000,
    parameter integer GPIO_N    = 16
) (
    input  wire              clk,
    input  wire              rst_btn_n,     // active-low reset button

    inout  wire [GPIO_N-1:0] gpio,

    output wire              uart_tx,
    input  wire              uart_rx,

    inout  wire              i2c_scl,
    inout  wire              i2c_sda,

    output wire              spi_sclk,
    output wire              spi_mosi,
    input  wire              spi_miso,
    output wire [3:0]        spi_cs_n
);

    // Asynchronous assert, synchronous release
    reg [1:0] rst_sync;
    always @(posedge clk or negedge rst_btn_n) begin
        if (!rst_btn_n)
            rst_sync <= 2'b00;
        else
            rst_sync <= {rst_sync[0], 1'b1};
    end
    wire rst_n = rst_sync[1];

    wire [GPIO_N-1:0] gpio_out, gpio_oe;
    wire              scl_oe, sda_oe;

    // Pads
    genvar i;
    generate
        for (i = 0; i < GPIO_N; i = i + 1) begin : g_gpio
            assign gpio[i] = gpio_oe[i] ? gpio_out[i] : 1'bz;
        end
    endgenerate
    assign i2c_scl = scl_oe ? 1'b0 : 1'bz;
    assign i2c_sda = sda_oe ? 1'b0 : 1'bz;

    soc_top #(
        .INIT_FILE (INIT_FILE),
        .CLK_HZ    (CLK_HZ),
        .GPIO_N    (GPIO_N)
    ) u_soc (
        .clk        (clk),
        .rst_n      (rst_n),
        .gpio_in    (gpio),
        .gpio_out   (gpio_out),
        .gpio_oe    (gpio_oe),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .i2c_scl_i  (i2c_scl),
        .i2c_scl_oe (scl_oe),
        .i2c_sda_i  (i2c_sda),
        .i2c_sda_oe (sda_oe),
        .spi_sclk   (spi_sclk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n)
    );

endmodule
