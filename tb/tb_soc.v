// System-level, self-checking testbench.
//
// Runs a program image on soc_top and checks it two ways:
//   1. Lockstep: every instruction the pipeline retires is compared (PC,
//      encoding, destination register and value) with rv32i_ref_model.
//   2. Program result: the program stores to TOHOST (1 = pass,
//      (n << 1) | 1 = failed check n). After that the RAM contents of the
//      RTL and the model are compared word by word.
//
// Plusargs
//   +HEX=<file>         program image ($readmemh, one 32-bit word per line)
//   +MAX_CYCLES=<n>     timeout (default 200000)
//   +TRACE              print every retired instruction
//   +VCD=<file>         dump waveforms
//
// Exit: prints "TEST PASSED" or "TEST FAILED: ..." and calls $finish
// (with a non-zero code on failure, via $fatal, so make/CI see it).
module tb_soc;
`include "rv32i_defs.vh"

    localparam integer RAM_ADDR_WIDTH = 12;
    localparam [31:0]  TOHOST_ADDR    = 32'hF000_0000;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;   // 100 MHz

    soc_top #(
        .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    rv32i_ref_model #(
        .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH)
    ) ref_model ();

    // Taps into the core
    wire        tr_valid   = dut.u_core.trace_valid;
    wire [31:0] tr_pc      = dut.u_core.trace_pc;
    wire [31:0] tr_instr   = dut.u_core.trace_instr;
    wire        tr_rd_we   = dut.u_core.trace_rd_we;
    wire [4:0]  tr_rd      = dut.u_core.trace_rd;
    wire [31:0] tr_rd_data = dut.u_core.trace_rd_data;
    wire        bus_we     = dut.u_core.dbus_we;
    wire [31:0] bus_addr   = dut.u_core.dbus_addr;
    wire [31:0] bus_wdata  = dut.u_core.dbus_wdata;

    reg [1023:0] hex_file;
    reg [1023:0] vcd_file;
    integer      max_cycles;
    reg          trace_on;

    integer cycles  = 0;
    integer retired = 0;
    integer errors  = 0;
    reg     done    = 1'b0;
    reg [31:0] tohost_val;

    // ------------------------------------------------------------------
    // Set-up
    // ------------------------------------------------------------------
    initial begin
        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("TEST FAILED: no +HEX=<file> given");
            $fatal(1);
        end
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 200000;
        trace_on = $test$plusargs("TRACE");
        if ($value$plusargs("VCD=%s", vcd_file)) begin
            $dumpfile(vcd_file);
            $dumpvars(0, tb_soc);
        end

        // Load the image after the RAM's own initial block has cleared it.
        #1;
        $readmemh(hex_file, dut.u_ram.mem);
        ref_model.clear_mem;
        $readmemh(hex_file, ref_model.mem);
        ref_model.reset;

        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
    end

    // ------------------------------------------------------------------
    // Lockstep comparison at retirement
    // ------------------------------------------------------------------
    reg [31:0] m_pc, m_instr, m_rd_data;
    reg [4:0]  m_rd;
    reg        m_rd_we, m_mmio;

    always @(posedge clk) begin
        if (rst_n && !done) begin
            cycles = cycles + 1;

            if (tr_valid) begin
                retired = retired + 1;
                ref_model.step(tr_rd_data, m_pc, m_instr, m_rd_we, m_rd, m_rd_data, m_mmio);

                if (trace_on)
                    $display("%8d  pc=%08h  instr=%08h  %s", cycles, tr_pc, tr_instr,
                             tr_rd_we ? $sformatf("x%0d <= %08h", tr_rd, tr_rd_data) : "");

                if (tr_pc !== m_pc || tr_instr !== m_instr ||
                    tr_rd_we !== m_rd_we ||
                    (m_rd_we && (tr_rd !== m_rd || tr_rd_data !== m_rd_data))) begin
                    errors = errors + 1;
                    $display("MISMATCH at retire #%0d (cycle %0d)", retired, cycles);
                    $display("  rtl  : pc=%08h instr=%08h rd_we=%b x%0d=%08h",
                             tr_pc, tr_instr, tr_rd_we, tr_rd, tr_rd_data);
                    $display("  model: pc=%08h instr=%08h rd_we=%b x%0d=%08h",
                             m_pc, m_instr, m_rd_we, m_rd, m_rd_data);
                    if (errors >= 5)
                        finish_test("too many mismatches");
                end
            end

            if (bus_we && bus_addr == TOHOST_ADDR) begin
                tohost_val = bus_wdata;
                // Let the store drain so RAM and model are both up to date.
                repeat (3) @(posedge clk);
                finish_test("");
            end else if (cycles >= max_cycles) begin
                finish_test("timeout");
            end
        end
    end

    // ------------------------------------------------------------------
    // End of test
    // ------------------------------------------------------------------
    integer k;
    task finish_test(input [8*32-1:0] why);
        begin
            done = 1'b1;

            for (k = 0; k < (1 << RAM_ADDR_WIDTH); k = k + 1) begin
                if (dut.u_ram.mem[k] !== ref_model.mem[k]) begin
                    if (errors < 10)
                        $display("RAM MISMATCH @%08h: rtl=%08h model=%08h",
                                 k * 4, dut.u_ram.mem[k], ref_model.mem[k]);
                    errors = errors + 1;
                end
            end

            $display("------------------------------------------------------------");
            $display("program : %0s", hex_file);
            $display("cycles  : %0d   retired: %0d   CPI: %0.3f",
                     cycles, retired, retired ? (1.0 * cycles) / retired : 0.0);

            if (why != "") begin
                $display("TEST FAILED: %0s", why);
                $fatal(1);
            end else if (errors != 0) begin
                $display("TEST FAILED: %0d mismatch(es) against the reference model", errors);
                $fatal(1);
            end else if (tohost_val != 32'd1) begin
                $display("TEST FAILED: program reported failure in check %0d", tohost_val >> 1);
                $fatal(1);
            end else begin
                $display("TEST PASSED");
                $finish;
            end
        end
    endtask

endmodule
