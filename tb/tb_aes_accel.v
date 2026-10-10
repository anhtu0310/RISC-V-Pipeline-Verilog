`timescale 1ns / 1ps

// Register-level tests for the AES accelerator (rtl/periph/aes_accel.v).
//
// Two instances are tested through their bus ports with the same timing as
// the core (request for one cycle, registered read data the next cycle):
// PIPELINED = 1 (aes128_pipe) and PIPELINED = 0 (aes128_iter). Both must
// behave the same except for speed. Expected ciphertexts are the FIPS-197
// Appendix B / C.1 and NIST SP 800-38A F.1.1 (ECB-AES128) vectors.
module tb_aes_accel;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    // ------------------------------------------------------------------
    // Bus and DUTs
    // ------------------------------------------------------------------
    reg  [1:0]  sel = 2'b00;      // one-hot {iter, pipe}
    reg         we = 1'b0, re = 1'b0;
    reg  [5:0]  addr = 6'd0;
    reg  [31:0] wdata = 32'd0;
    reg  [3:0]  wstrb = 4'd0;
    wire [31:0] rdata_pipe, rdata_iter;

    aes_accel #(.PIPELINED(1)) u_pipe (
        .clk (clk), .rst_n (rst_n),
        .sel (sel[0]), .we (we), .re (re), .addr (addr),
        .wdata (wdata), .wstrb (wstrb), .rdata (rdata_pipe)
    );

    aes_accel #(.PIPELINED(0)) u_iter (
        .clk (clk), .rst_n (rst_n),
        .sel (sel[1]), .we (we), .re (re), .addr (addr),
        .wdata (wdata), .wstrb (wstrb), .rdata (rdata_iter)
    );

    integer dev;     // 0 = pipe, 1 = iter

    localparam [7:0] CTRL = 8'h00, STATUS = 8'h04, CMD = 8'h08, BLOCKS = 8'h0C,
                     KEY = 8'h10, DIN = 8'h20, DOUT = 8'h30;
    localparam [31:0] READY = 32'h1, OUT_VALID = 32'h2, BUSY = 32'h4, OVERFLOW = 32'h8;

    task bus_write(input [7:0] off, input [31:0] d, input [3:0] strb);
        begin
            @(negedge clk);
            sel = 2'b01 << dev; we = 1'b1; addr = off[7:2]; wdata = d; wstrb = strb;
            @(negedge clk);
            sel = 2'b00; we = 1'b0; wstrb = 4'd0;
        end
    endtask

    task wr(input [7:0] off, input [31:0] d);
        bus_write(off, d, 4'b1111);
    endtask

    task rd(input [7:0] off, output [31:0] d);
        begin
            @(negedge clk);
            sel = 2'b01 << dev; re = 1'b1; addr = off[7:2];
            @(negedge clk);
            sel = 2'b00; re = 1'b0;
            d = dev ? rdata_iter : rdata_pipe;
        end
    endtask

    task check(input [8*40-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL [%0s] %0s: got %08h expected %08h",
                         dev ? "iter" : "pipe", what, got, exp);
            end
        end
    endtask

    // FIPS byte order (byte 0 in [127:120]) -> register word i (byte 4i in [7:0])
    function [31:0] word(input [127:0] v, input integer i);
        reg [31:0] w;
        begin
            w = v[127 - 32*i -: 32];
            word = {w[7:0], w[15:8], w[23:16], w[31:24]};
        end
    endfunction

    // ------------------------------------------------------------------
    // Vectors
    // ------------------------------------------------------------------
    reg [127:0] vk [0:5];
    reg [127:0] vp [0:5];
    reg [127:0] vc [0:5];
    initial begin
        // FIPS-197 Appendix B
        vk[0] = 128'h2b7e151628aed2a6abf7158809cf4f3c; vp[0] = 128'h3243f6a8885a308d313198a2e0370734; vc[0] = 128'h3925841d02dc09fbdc118597196a0b32;
        // FIPS-197 Appendix C.1
        vk[1] = 128'h000102030405060708090a0b0c0d0e0f; vp[1] = 128'h00112233445566778899aabbccddeeff; vc[1] = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
        // SP 800-38A F.1.1
        vk[2] = 128'h2b7e151628aed2a6abf7158809cf4f3c; vp[2] = 128'h6bc1bee22e409f96e93d7e117393172a; vc[2] = 128'h3ad77bb40d7a3660a89ecaf32466ef97;
        vk[3] = 128'h2b7e151628aed2a6abf7158809cf4f3c; vp[3] = 128'hae2d8a571e03ac9c9eb76fac45af8e51; vc[3] = 128'hf5d3d58503b9699de785895a96fdbaaf;
        vk[4] = 128'h2b7e151628aed2a6abf7158809cf4f3c; vp[4] = 128'h30c81c46a35ce411e5fbc1191a0a52ef; vc[4] = 128'h43b1cd7f598ece23881b00e3ed030688;
        vk[5] = 128'h2b7e151628aed2a6abf7158809cf4f3c; vp[5] = 128'hf69f2445df4f9b17ad2b417be66c3710; vc[5] = 128'h7b0c785e27e8ad3f8223207104725dd4;
    end

    reg [31:0] v;
    integer i, j, n;

    task set_key(input [127:0] k);
        for (i = 0; i < 4; i = i + 1) wr(KEY + 4*i, word(k, i));
    endtask

    task set_din(input [127:0] p);
        for (i = 0; i < 4; i = i + 1) wr(DIN + 4*i, word(p, i));
    endtask

    task wait_status(input [31:0] mask);
        integer t;
        begin
            t = 0;
            rd(STATUS, v);
            while ((v & mask) == 0 && t < 100) begin
                rd(STATUS, v);
                t = t + 1;
            end
            check("status wait", v & mask, mask);
        end
    endtask

    task check_result(input [8*24-1:0] what, input [127:0] c);
        begin
            for (j = 0; j < 4; j = j + 1) begin
                rd(DOUT + 4*j, v);
                check(what, v, word(c, j));
            end
        end
    endtask

    task push(input integer idx);     // key + block, START, no waiting
        begin
            set_key(vk[idx]);
            set_din(vp[idx]);
            wr(CMD, 32'h1);
        end
    endtask

    // ------------------------------------------------------------------
    // Tests (run once per instance)
    // ------------------------------------------------------------------
    task run_tests;
        reg [31:0] impl;
        begin
            impl = dev ? 32'h0 : 32'h8000_0000;
            $display("--- aes_accel PIPELINED=%0d", dev ? 0 : 1);

            // Reset state
            rd(STATUS, v);  check("reset STATUS", v, impl | READY);
            rd(BLOCKS, v);  check("reset BLOCKS", v, 0);
            rd(DOUT, v);    check("DOUT when empty", v, 0);
            rd(CTRL, v);    check("reset CTRL", v, 0);

            // Register read-back and byte lanes
            wr(KEY + 4, 32'h1122_3344);
            bus_write(KEY + 4, 32'hAA00_BB00, 4'b1010);
            rd(KEY + 4, v); check("KEY1 byte lanes", v, 32'hAA22_BB44);
            wr(DIN + 12, 32'hCAFE_F00D);
            rd(DIN + 12, v); check("DIN3 read-back", v, 32'hCAFE_F00D);
            rd(8'h40, v);   check("unused offset", v, 0);

            // One block: FIPS-197 C.1
            push(1);
            rd(STATUS, v);  check("BUSY right after START", v & BUSY, BUSY);
            wait_status(OUT_VALID);
            rd(STATUS, v);  check("one result queued", v & 32'h0000_1F0F, 32'h0000_0103);
            check_result("FIPS-197 C.1", vc[1]);
            rd(STATUS, v);  check("FIFO empty after pop", v & 32'h7FFF_FFFF, READY);
            rd(BLOCKS, v);  check("BLOCKS after one", v, 1);

            // Key changed while a block is in flight: each block keeps its own
            for (n = 0; n < 2; n = n + 1) begin
                wait_status(READY);
                push(n);
            end
            wait_status(OUT_VALID);
            check_result("FIPS-197 B (key change)", vc[0]);
            wait_status(OUT_VALID);
            check_result("FIPS-197 C.1 (key change)", vc[1]);

            // AUTO_START: SP 800-38A, four blocks in a row, read afterwards
            wr(CTRL, 32'h1);
            set_key(vk[2]);
            for (n = 2; n < 6; n = n + 1) begin
                wait_status(READY);
                set_din(vp[n]);             // the DIN3 write starts the block
            end
            wait_status(OUT_VALID);
            repeat (12) @(negedge clk);
            rd(STATUS, v);  check("4 results queued", (v >> 8) & 32'h1F, 4);
            for (n = 2; n < 6; n = n + 1)
                check_result("SP 800-38A ECB", vc[n]);
            wr(CTRL, 32'h0);

            // Fill all 16 FIFO entries; a 17th START must be refused
            for (n = 0; n < 16; n = n + 1) begin
                wait_status(READY);
                push(n % 6);
            end
            repeat (12) @(negedge clk);
            rd(STATUS, v);  check("FIFO full: READY low, 16 queued", v & 32'h0000_1F0B, 32'h0000_1002);
            push(0);
            rd(STATUS, v);  check("17th START sets OVERFLOW", v & OVERFLOW, OVERFLOW);
            for (n = 0; n < 16; n = n + 1)
                check_result("16 queued results", vc[n % 6]);
            rd(STATUS, v);  check("drained, READY again", v & 32'h0000_1F0B, 32'h0000_0009);
            rd(BLOCKS, v);  check("BLOCKS count", v, 1 + 2 + 4 + 16);

            // Credit check: with 12 results queued, STARTs issued back to back
            // must stop once queued + in flight reaches 16, even though the
            // FIFO itself still has room (pipeline: 4 of the 6 accepted; the
            // iterative core takes one block per 10 clocks, so 2)
            set_key(vk[3]); set_din(vp[3]);
            for (n = 0; n < 12; n = n + 1) begin
                wait_status(READY);
                wr(CMD, 32'h1);
            end
            repeat (12) @(negedge clk);
            wr(CMD, 32'h2);                  // CLEAR: OVERFLOW off, FIFO empty
            for (n = 0; n < 12; n = n + 1) begin
                wait_status(READY);
                wr(CMD, 32'h1);
            end
            repeat (12) @(negedge clk);
            for (n = 0; n < 6; n = n + 1)
                wr(CMD, 32'h1);              // every 2 clocks, while earlier ones are in flight
            repeat (12) @(negedge clk);
            rd(STATUS, v);
            check("credit: OVERFLOW", v & OVERFLOW, OVERFLOW);
            check("credit: queued", (v >> 8) & 32'h1F, dev ? 14 : 16);
            for (n = 0; n < (dev ? 14 : 16); n = n + 1)
                check_result("credit results", vc[3]);
            rd(STATUS, v);  check("credit: drained", v & 32'h0000_1F07, READY);
            wr(CMD, 32'h2);
            rd(BLOCKS, v);  check("BLOCKS after credit test", v, 1 + 2 + 4 + 16 + 12 + 12 + (dev ? 2 : 4));

            // CLEAR drops queued and in-flight results and OVERFLOW
            push(1);
            repeat (12) @(negedge clk);
            push(2);                         // still in flight at the CLEAR
            wr(CMD, 32'h2);
            repeat (15) @(negedge clk);
            rd(STATUS, v);  check("CLEAR empties everything", v & 32'h7FFF_FFFF, READY);
            rd(BLOCKS, v);  check("cleared block counted, flushed not", v, 1 + 2 + 4 + 16 + 24 + (dev ? 2 : 4) + 1);
            push(0);
            wait_status(OUT_VALID);
            check_result("block after CLEAR", vc[0]);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        dev = 0; run_tests;
        dev = 1; run_tests;
        $display("aes_accel register tests: %0d checks, %0d errors", checks, errors);
        if (errors == 0)
            $display("TEST PASSED");
        else begin
            $display("TEST FAILED");
            $fatal(1);
        end
        $finish;
    end

    initial begin
        #5_000_000;
        $display("TEST FAILED: timeout");
        $fatal(1);
    end

endmodule
