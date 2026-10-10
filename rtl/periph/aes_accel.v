`timescale 1ns / 1ps

// AES-128 encryption accelerator (memory-mapped peripheral).
//
// Wraps one of the AES cores in rtl/aes:
//   PIPELINED = 1  aes128_pipe: 10-stage pipeline, accepts a block every clock
//   PIPELINED = 0  aes128_iter: one round per clock, a block every 10 clocks,
//                  about a tenth of the logic
// Both give the same register interface and results; software can't tell
// them apart except by speed.
//
// Software writes the key (KEY0..3) and a plaintext block (DIN0..3) and
// starts the block with CMD.START (or, with CTRL.AUTO_START set, by writing
// DIN3). The key is captured together with the block, so KEY may be changed
// for the next block right away. Results queue up in a 16-entry FIFO in
// issue order and are read from DOUT0..3; reading DOUT3 pops the entry.
// Several blocks can be in flight at once, so a driver can keep pushing
// while results come back.
//
// A START is accepted only when STATUS.READY is set, i.e. the core can take
// a block and the FIFO has room for every block already in flight plus this
// one, so results are never dropped. A START while not ready is ignored and
// sets the sticky STATUS.OVERFLOW.
//
// Byte order: register word i holds block bytes 4i..4i+3 with byte 4i in
// bits [7:0], so on this little-endian CPU a 16-byte buffer read as four
// uint32_t maps straight onto KEY / DIN / DOUT. Byte 0 is the first byte
// of the FIPS-197 input/key/output (in0, key0, out0).
//
// Registers (word offsets from the AES base):
//   0x00 CTRL     RW [0] AUTO_START: a write to DIN3 also starts the block
//   0x04 STATUS   R  [0] READY      a START will be accepted
//                    [1] OUT_VALID  DOUT holds a result (FIFO not empty)
//                    [2] BUSY       blocks are in flight in the core
//                    [3] OVERFLOW   a START was dropped (sticky)
//                    [12:8]  OUT_COUNT  results waiting in the FIFO
//                    [19:16] IN_FLIGHT  blocks inside the core
//                    [31]    PIPELINED  1 = aes128_pipe, 0 = aes128_iter
//   0x08 CMD      W  [0] START  encrypt DIN0..3 with KEY0..3
//                    [1] CLEAR  drop queued and in-flight results, clear OVERFLOW
//   0x0C BLOCKS   R  blocks completed since reset (wraps)
//   0x10-0x1C KEY0..3   RW  (byte-lane writes allowed)
//   0x20-0x2C DIN0..3   RW  (byte-lane writes allowed)
//   0x30-0x3C DOUT0..3  R   head of the result FIFO, 0 when empty;
//                           reading DOUT3 pops
module aes_accel #(
    parameter integer PIPELINED = 1
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sel,
    input  wire        we,
    input  wire        re,
    input  wire [5:0]  addr,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    output reg  [31:0] rdata
);

    localparam [5:0] R_CTRL  = 6'h00, R_STATUS = 6'h01, R_CMD   = 6'h02,
                     R_BLOCKS = 6'h03, R_KEY0  = 6'h04, R_DIN0  = 6'h08,
                     R_DOUT0 = 6'h0C;

    localparam integer FIFO_DEPTH = 16;    // also hard-coded in `ready`
    localparam integer EPOCH_W    = 4;

    wire wr = sel && we;
    wire rd = sel && re;

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    reg        auto_start;
    reg        overflow;
    reg [31:0] blocks;
    reg [31:0] key_w [0:3];
    reg [31:0] din_w [0:3];

    // Register word i = bytes 4i..4i+3 (byte 4i in bits [7:0]); the cores
    // want byte 0 in bits [127:120].
    function [31:0] bswap(input [31:0] w);
        bswap = {w[7:0], w[15:8], w[23:16], w[31:24]};
    endfunction

    wire [127:0] key_blk = {bswap(key_w[0]), bswap(key_w[1]), bswap(key_w[2]), bswap(key_w[3])};
    wire [127:0] din_blk = {bswap(din_w[0]), bswap(din_w[1]), bswap(din_w[2]), bswap(din_w[3])};

    function [31:0] merge(input [31:0] old, input [31:0] d, input [3:0] strb);
        integer b;
        begin
            for (b = 0; b < 4; b = b + 1)
                merge[8*b +: 8] = strb[b] ? d[8*b +: 8] : old[8*b +: 8];
        end
    endfunction

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            auto_start <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                key_w[i] <= 32'd0;
                din_w[i] <= 32'd0;
            end
        end else if (wr) begin
            if (addr == R_CTRL && wstrb[0])
                auto_start <= wdata[0];
            for (i = 0; i < 4; i = i + 1) begin
                if (addr == R_KEY0 + i[5:0]) key_w[i] <= merge(key_w[i], wdata, wstrb);
                if (addr == R_DIN0 + i[5:0]) din_w[i] <= merge(din_w[i], wdata, wstrb);
            end
        end
    end

    // ------------------------------------------------------------------
    // Start / clear
    // ------------------------------------------------------------------
    wire cmd_wr    = wr && addr == R_CMD && wstrb[0];
    wire clear     = cmd_wr && wdata[1];
    // DIN3 is written this cycle in auto mode: start from the new value.
    wire auto_go   = wr && auto_start && addr == R_DIN0 + 6'd3;
    wire start_req = (cmd_wr && wdata[0]) || auto_go;
    wire [127:0] blk_now = auto_go ? {din_blk[127:32], bswap(merge(din_w[3], wdata, wstrb))} : din_blk;

    // Results carry the epoch they were started in; CLEAR bumps the epoch
    // so results still in flight are dropped when they come out.
    reg [EPOCH_W-1:0] epoch;

    wire              core_in_ready;
    wire              core_out_valid;
    wire [127:0]      core_out;
    wire [EPOCH_W-1:0] core_out_epoch;

    reg  [4:0] in_flight;   // up to 10
    wire [4:0] out_count;

    wire ready = core_in_ready && !clear && ({1'b0, in_flight} + {1'b0, out_count} < 6'd16);
    wire start = start_req && ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            epoch     <= {EPOCH_W{1'b0}};
            overflow  <= 1'b0;
            in_flight <= 5'd0;
            blocks    <= 32'd0;
        end else begin
            if (clear)
                epoch <= epoch + 1'b1;
            if (clear)
                overflow <= 1'b0;
            else if (start_req && !ready)
                overflow <= 1'b1;
            in_flight <= in_flight + {4'd0, start} - {4'd0, core_out_valid};
            if (core_out_valid && core_out_epoch == epoch)
                blocks <= blocks + 32'd1;
        end
    end

    // ------------------------------------------------------------------
    // Core
    // ------------------------------------------------------------------
    generate
        if (PIPELINED != 0) begin : g_pipe
            assign core_in_ready = 1'b1;
            aes128_pipe #(
                .TAG_W (EPOCH_W)
            ) u_core (
                .clk       (clk),
                .rst_n     (rst_n),
                .ce        (1'b1),
                .in_valid  (start),
                .in_key    (key_blk),
                .in_block  (blk_now),
                .in_tag    (epoch),
                .out_valid (core_out_valid),
                .out_block (core_out),
                .out_tag   (core_out_epoch)
            );
        end else begin : g_iter
            reg [EPOCH_W-1:0] iter_epoch;
            always @(posedge clk)
                if (start)
                    iter_epoch <= epoch;
            assign core_out_epoch = iter_epoch;
            aes128_iter u_core (
                .clk       (clk),
                .rst_n     (rst_n),
                .in_valid  (start),
                .in_ready  (core_in_ready),
                .in_key    (key_blk),
                .in_block  (blk_now),
                .out_valid (core_out_valid),
                .out_block (core_out)
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Result FIFO (first-word fall-through; CLEAR empties it at once)
    // ------------------------------------------------------------------
    // The READY rule above guarantees it never overflows.
    reg [127:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [3:0]   wr_ptr, rd_ptr;
    reg [4:0]   count_q;

    wire fifo_empty = (count_q == 5'd0);
    wire fifo_push  = core_out_valid && core_out_epoch == epoch && !clear;
    wire fifo_pop   = rd && addr == R_DOUT0 + 6'd3 && !fifo_empty && !clear;
    wire [127:0] head = fifo_mem[rd_ptr];

    always @(posedge clk)
        if (fifo_push)
            fifo_mem[wr_ptr] <= core_out;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= 4'd0;
            rd_ptr  <= 4'd0;
            count_q <= 5'd0;
        end else if (clear) begin
            wr_ptr  <= 4'd0;
            rd_ptr  <= 4'd0;
            count_q <= 5'd0;
        end else begin
            if (fifo_push) wr_ptr <= wr_ptr + 4'd1;
            if (fifo_pop)  rd_ptr <= rd_ptr + 4'd1;
            count_q <= count_q + {4'd0, fifo_push} - {4'd0, fifo_pop};
        end
    end
    assign out_count = count_q;

    // ------------------------------------------------------------------
    // Read back
    // ------------------------------------------------------------------
    wire [31:0] status = {PIPELINED != 0, 11'd0, in_flight[3:0], 3'd0, out_count,
                          4'd0, overflow, in_flight != 5'd0, !fifo_empty, ready};

    always @(posedge clk) begin
        if (rd) begin
            case (addr)
                R_CTRL:      rdata <= {31'd0, auto_start};
                R_STATUS:    rdata <= status;
                R_BLOCKS:    rdata <= blocks;
                R_KEY0:      rdata <= key_w[0];
                R_KEY0 + 1:  rdata <= key_w[1];
                R_KEY0 + 2:  rdata <= key_w[2];
                R_KEY0 + 3:  rdata <= key_w[3];
                R_DIN0:      rdata <= din_w[0];
                R_DIN0 + 1:  rdata <= din_w[1];
                R_DIN0 + 2:  rdata <= din_w[2];
                R_DIN0 + 3:  rdata <= din_w[3];
                R_DOUT0:     rdata <= fifo_empty ? 32'd0 : bswap(head[127:96]);
                R_DOUT0 + 1: rdata <= fifo_empty ? 32'd0 : bswap(head[95:64]);
                R_DOUT0 + 2: rdata <= fifo_empty ? 32'd0 : bswap(head[63:32]);
                R_DOUT0 + 3: rdata <= fifo_empty ? 32'd0 : bswap(head[31:0]);
                default:     rdata <= 32'd0;
            endcase
        end
    end

endmodule
