// Minimal SoC: RV32I core + unified code/data RAM + peripheral window.
//
// Memory map
//   0x0000_0000 - RAM_BYTES-1   RAM (code, data, stack). Instruction fetch
//                               uses port A, loads/stores use port B.
//   0x1000_0000 - 0x1FFF_FFFF   Peripheral window (reserved; reads return 0)
//   anything else               Unmapped: writes ignored, reads return 0
//
// Data bus timing (see rv32i_core.v): request in one cycle, read data due
// the next cycle. Every slave registers its read data, and the read mux
// below uses the slave selection registered alongside the request.
module soc_top #(
    parameter integer RAM_ADDR_WIDTH = 12,       // 2**12 words = 16 KiB
    parameter         INIT_FILE      = "",
    parameter [31:0]  RESET_ADDR     = 32'h0000_0000
) (
    input  wire clk,
    input  wire rst_n
);

    localparam [31:0] RAM_BYTES = 32'd4 << RAM_ADDR_WIDTH;

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
    wire sel_ram = (dbus_addr < RAM_BYTES);
    // wire sel_periph = (dbus_addr[31:28] == 4'h1);  // added with peripherals

    reg  sel_ram_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sel_ram_q <= 1'b0;
        else
            sel_ram_q <= dbus_re && sel_ram;
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

    assign dbus_rdata = sel_ram_q ? ram_rdata : 32'd0;

endmodule
