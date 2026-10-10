`timescale 1ns / 1ps

// SPI master: 8-bit transfers, all four modes, MSB or LSB first, and up to
// four software-controlled chip selects.
//
// SCLK half period = CLKDIV + 1 clocks, so f_SCLK = f_clk / (2 * (CLKDIV + 1)).
// Software asserts a chip select through CS, writes DATA once per byte, polls
// STATUS.BUSY, reads DATA and finally releases CS. Keeping CS under
// software control lets one select stay low across a multi-byte command.
//
// Mode (CPOL, CPHA):
//   CPHA = 0: MOSI is valid before the first edge; MISO is sampled on the
//             leading edges, MOSI shifts on the trailing ones.
//   CPHA = 1: MOSI shifts on the leading edges, MISO is sampled on the
//             trailing ones.
//   CPOL sets the SCLK idle level.
//
// Registers (word offsets from the SPI base):
//   0x00 CTRL    RW [0] CPOL  [1] CPHA  [2] LSB_FIRST (change only while idle)
//   0x04 CLKDIV  RW [15:0]
//   0x08 CS      RW [NCS-1:0] 1 = assert the select (cs_n pin low)
//   0x0C DATA    W  start a transfer of wdata[7:0] (ignored while BUSY)
//                R  byte received by the last transfer
//   0x10 STATUS  R  [0] BUSY
module spi_master #(
    parameter integer NCS         = 4,
    parameter [15:0]  DEFAULT_DIV = 16'd4
) (
    input  wire           clk,
    input  wire           rst_n,

    input  wire           sel,
    input  wire           we,
    input  wire           re,
    input  wire [5:0]     addr,
    // Only the low bytes of the registers are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0]    wdata,
    input  wire [3:0]     wstrb,
    /* verilator lint_on UNUSEDSIGNAL */
    output reg  [31:0]    rdata,

    output wire           spi_sclk,
    output wire           spi_mosi,
    input  wire           spi_miso,
    output wire [NCS-1:0] spi_cs_n
);

    localparam [5:0] R_CTRL = 6'd0, R_CLKDIV = 6'd1, R_CS = 6'd2,
                     R_DATA = 6'd3, R_STATUS = 6'd4;

    wire wr = sel && we;
    wire rd = sel && re;

    reg         cpol, cpha, lsb_first;
    reg [15:0]  clkdiv;
    reg [NCS-1:0] cs;
    reg [7:0]   rxdata;

    function [7:0] rev8(input [7:0] v);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1)
                rev8[i] = v[7 - i];
        end
    endfunction

    // ------------------------------------------------------------------
    // Shift engine
    // ------------------------------------------------------------------
    reg        busy, tail;
    reg [15:0] cnt;
    reg [3:0]  edge_n;      // SCLK edges done in this byte, 0..15
    reg        sclk;
    reg [7:0]  tx_shift, rx_shift;

    wire start   = wr && addr == R_DATA && wstrb[0] && !busy;
    // edge_n even = leading edge, odd = trailing edge
    wire sample  = (edge_n[0] == cpha);
    wire [7:0] rx_next = {rx_shift[6:0], spi_miso};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy     <= 1'b0;
            tail     <= 1'b0;
            cnt      <= 16'd0;
            edge_n   <= 4'd0;
            sclk     <= 1'b0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
            rxdata   <= 8'd0;
        end else if (start) begin
            busy     <= 1'b1;
            tail     <= 1'b0;
            cnt      <= clkdiv;
            edge_n   <= 4'd0;
            sclk     <= cpol;
            tx_shift <= lsb_first ? rev8(wdata[7:0]) : wdata[7:0];
        end else if (busy) begin
            if (cnt != 16'd0) begin
                cnt <= cnt - 16'd1;
            end else if (tail) begin
                // Half a period after the last edge: transfer complete.
                busy   <= 1'b0;
                tail   <= 1'b0;
                rxdata <= lsb_first ? rev8(rx_shift) : rx_shift;
            end else begin
                cnt    <= clkdiv;
                sclk   <= !sclk;
                edge_n <= edge_n + 4'd1;
                if (sample)
                    rx_shift <= rx_next;
                else if (edge_n != 4'd0)
                    tx_shift <= {tx_shift[6:0], 1'b0};
                if (edge_n == 4'd15)
                    tail <= 1'b1;
            end
        end else begin
            sclk <= cpol;       // follow CPOL changes while idle
        end
    end

    assign spi_sclk = sclk;
    assign spi_mosi = tx_shift[7];
    assign spi_cs_n = ~cs;

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpol      <= 1'b0;
            cpha      <= 1'b0;
            lsb_first <= 1'b0;
            clkdiv    <= DEFAULT_DIV;
            cs        <= {NCS{1'b0}};
        end else if (wr) begin
            if (addr == R_CTRL && wstrb[0]) begin
                cpol      <= wdata[0];
                cpha      <= wdata[1];
                lsb_first <= wdata[2];
            end
            if (addr == R_CLKDIV) begin
                if (wstrb[0]) clkdiv[7:0]  <= wdata[7:0];
                if (wstrb[1]) clkdiv[15:8] <= wdata[15:8];
            end
            if (addr == R_CS && wstrb[0])
                cs <= wdata[NCS-1:0];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= 32'd0;
        else if (rd) begin
            case (addr)
                R_CTRL:   rdata <= {29'd0, lsb_first, cpha, cpol};
                R_CLKDIV: rdata <= {16'd0, clkdiv};
                R_CS:     rdata <= {{(32-NCS){1'b0}}, cs};
                R_DATA:   rdata <= {24'd0, rxdata};
                R_STATUS: rdata <= {31'd0, busy};
                default:  rdata <= 32'd0;
            endcase
        end
    end

endmodule
