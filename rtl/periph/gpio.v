`timescale 1ns / 1ps

// General-purpose I/O, N pins (N <= 32).
//
// Each pin has an output value, an output enable (direction) and an input
// that is passed through a two-flop synchroniser. Rising and falling edges
// on the synchronised inputs are latched in sticky status registers so
// software can poll for button presses etc. without missing short pulses.
//
// Registers (word offsets from the GPIO base):
//   0x00 DATA_IN   R    synchronised pin values
//   0x04 DATA_OUT  RW   output values
//   0x08 DIR       RW   1 = pin is an output (drives gpio_out), 0 = input
//   0x0C OUT_SET   W    DATA_OUT |=  wdata   (atomic bit set)
//   0x10 OUT_CLR   W    DATA_OUT &= ~wdata   (atomic bit clear)
//   0x14 OUT_TGL   W    DATA_OUT ^=  wdata   (atomic bit toggle)
//   0x18 RISE      R/W1C  latched rising edges; write 1 to clear
//   0x1C FALL      R/W1C  latched falling edges; write 1 to clear
//
// DATA_OUT and DIR honour the byte strobes, so sb/sh work on them.
// Unused offsets read as 0.
module gpio #(
    parameter integer N = 32
) (
    input  wire         clk,
    input  wire         rst_n,

    // Bus slave (request in one cycle, registered read data next cycle)
    input  wire         sel,
    input  wire         we,
    input  wire         re,
    input  wire [5:0]   addr,       // word offset
    // Bits above N are unused when N < 32.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0]  wdata,
    input  wire [3:0]   wstrb,
    /* verilator lint_on UNUSEDSIGNAL */
    output reg  [31:0]  rdata,

    // Pins
    input  wire [N-1:0] gpio_in,
    output wire [N-1:0] gpio_out,
    output wire [N-1:0] gpio_oe
);

    localparam [5:0] R_DATA_IN = 6'd0, R_DATA_OUT = 6'd1, R_DIR  = 6'd2,
                     R_SET     = 6'd3, R_CLR      = 6'd4, R_TGL  = 6'd5,
                     R_RISE    = 6'd6, R_FALL     = 6'd7;

    reg [N-1:0] data_out, dir;
    reg [N-1:0] sync1, sync2, last;
    reg [N-1:0] rise, fall;

    // Byte-lane write mask
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] lane_mask = {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};
    /* verilator lint_on UNUSEDSIGNAL */
    wire [N-1:0] wmask = lane_mask[N-1:0];
    wire [N-1:0] wbits = wdata[N-1:0] & wmask;

    wire wr = sel && we;

    // Input synchroniser and edge detect
    wire [N-1:0] rise_now = sync2 & ~last;
    wire [N-1:0] fall_now = ~sync2 & last;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= {N{1'b0}};
            sync2 <= {N{1'b0}};
            last  <= {N{1'b0}};
        end else begin
            sync1 <= gpio_in;
            sync2 <= sync1;
            last  <= sync2;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= {N{1'b0}};
            dir      <= {N{1'b0}};
            rise     <= {N{1'b0}};
            fall     <= {N{1'b0}};
        end else begin
            if (wr) begin
                case (addr)
                    R_DATA_OUT: data_out <= (data_out & ~wmask) | wbits;
                    R_DIR:      dir      <= (dir & ~wmask) | wbits;
                    R_SET:      data_out <= data_out | wbits;
                    R_CLR:      data_out <= data_out & ~wbits;
                    R_TGL:      data_out <= data_out ^ wbits;
                    default:    ;
                endcase
            end
            // A new edge wins over a simultaneous clear, so none is lost.
            rise <= (rise & ~((wr && addr == R_RISE) ? wbits : {N{1'b0}})) | rise_now;
            fall <= (fall & ~((wr && addr == R_FALL) ? wbits : {N{1'b0}})) | fall_now;
        end
    end

    // Registered read data
    reg [31:0] rd_mux;
    always @(*) begin
        rd_mux = 32'd0;
        case (addr)
            R_DATA_IN:  rd_mux[N-1:0] = sync2;
            R_DATA_OUT: rd_mux[N-1:0] = data_out;
            R_DIR:      rd_mux[N-1:0] = dir;
            R_RISE:     rd_mux[N-1:0] = rise;
            R_FALL:     rd_mux[N-1:0] = fall;
            default:    ;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= 32'd0;
        else if (sel && re)
            rdata <= rd_mux;
    end

    assign gpio_out = data_out;
    assign gpio_oe  = dir;

endmodule
