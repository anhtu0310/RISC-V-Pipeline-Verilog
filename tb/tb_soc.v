`timescale 1ns / 1ps

// System-level, self-checking testbench.
//
// Runs a program image on soc_top and checks it two ways:
//   1. Lockstep: every instruction the pipeline retires is compared (PC,
//      encoding, destination register and value) with rv32i_ref_model.
//   2. Program result: the program stores to TOHOST (1 = pass,
//      (n << 1) | 1 = failed check n). After that the RAM contents of the
//      RTL and the model are compared word by word.
//
// The SoC's pins are connected to models of a small board:
//   GPIO  pins 7:0 are looped back externally to pins 31:24, pins 23:16
//         read 0xA5, pins 15:8 read 0 (when not driven by the SoC)
//   UART  tb/models/uart_model.v at 16 clocks per bit, echoing every byte
//   I2C   two tb/models/i2c_slave_model.v devices (0x50 with clock
//         stretching, 0x51 without) on pulled-up open-drain SCL/SDA
//   SPI   one tb/models/spi_slave_model.v per chip select, CS n in mode n
// Loads from peripherals are taken from the RTL by the reference model,
// so the programs check the peripheral behaviour themselves.
//
// Plusargs
//   +HEX=<file>         program image ($readmemh, one 32-bit word per line)
//   +MAX_CYCLES=<n>     timeout (default 200000)
//   +TRACE              print every retired instruction
//   +VCD=<file>         dump waveforms
//   +UART_EXPECT=<str>  fail unless the UART terminal received <str> first
//
// A store to MARK_ADDR (0xF000_0004) prints "[mark] <value> at cycle <n>
// (+<cycles since the previous mark>)", for timing code sections.
// Parameter AES_PIPELINED selects the AES core (iverilog -P tb_soc.AES_PIPELINED=0).
//
// Exit: prints "TEST PASSED" or "TEST FAILED: ..." and calls $finish
// (with a non-zero code on failure, via $fatal, so make/CI see it).
module tb_soc;
`include "rv32i_defs.vh"

    // 0: build the SoC with the iterative AES core instead of the pipeline
    parameter integer AES_PIPELINED = 1;

    localparam integer RAM_ADDR_WIDTH = 12;
    localparam [31:0]  TOHOST_ADDR    = 32'hF000_0000;
    localparam [31:0]  MARK_ADDR      = 32'hF000_0004;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;   // 100 MHz

    // ------------------------------------------------------------------
    // DUT and board
    // ------------------------------------------------------------------
    wire [31:0] gpio_out, gpio_oe;
    wire [31:0] gpio_board = {gpio_out[7:0] & gpio_oe[7:0], 8'hA5, 8'h00, 8'h00};
    wire [31:0] gpio_in    = (gpio_out & gpio_oe) | (gpio_board & ~gpio_oe);

    wire uart_tx, uart_rx;

    wire scl, sda, scl_oe, sda_oe;
    pullup (scl);
    pullup (sda);
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    wire       spi_sclk, spi_mosi, spi_miso;
    wire [3:0] spi_cs_n;
    pullup (spi_miso);

    soc_top #(
        .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH),
        .AES_PIPELINED  (AES_PIPELINED)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .gpio_in    (gpio_in),
        .gpio_out   (gpio_out),
        .gpio_oe    (gpio_oe),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .i2c_scl_i  (scl),
        .i2c_scl_oe (scl_oe),
        .i2c_sda_i  (sda),
        .i2c_sda_oe (sda_oe),
        .spi_sclk   (spi_sclk),
        .spi_mosi   (spi_mosi),
        .spi_miso   (spi_miso),
        .spi_cs_n   (spi_cs_n)
    );

    uart_model #(.DIV(16), .NAME("uart")) u_term (.clk (clk), .rx (uart_tx), .tx (uart_rx));
    initial u_term.echo = 1'b1;

    i2c_slave_model #(.ADDR(7'h50), .STRETCH(200)) u_i2c50 (.scl (scl), .sda (sda));
    i2c_slave_model #(.ADDR(7'h51), .STRETCH(0))   u_i2c51 (.scl (scl), .sda (sda));

    spi_slave_model #(.CPOL(0), .CPHA(0), .ID(8'hA0)) u_spi0 (.sclk (spi_sclk), .mosi (spi_mosi), .cs_n (spi_cs_n[0]), .miso (spi_miso));
    spi_slave_model #(.CPOL(0), .CPHA(1), .ID(8'hA1)) u_spi1 (.sclk (spi_sclk), .mosi (spi_mosi), .cs_n (spi_cs_n[1]), .miso (spi_miso));
    spi_slave_model #(.CPOL(1), .CPHA(0), .ID(8'hA2)) u_spi2 (.sclk (spi_sclk), .mosi (spi_mosi), .cs_n (spi_cs_n[2]), .miso (spi_miso));
    spi_slave_model #(.CPOL(1), .CPHA(1), .ID(8'hA3)) u_spi3 (.sclk (spi_sclk), .mosi (spi_mosi), .cs_n (spi_cs_n[3]), .miso (spi_miso));

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
    reg [1023:0] uart_expect;
    reg          check_uart;
    integer      max_cycles;
    reg          trace_on;

    integer cycles  = 0;
    integer last_mark = 0;
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
        check_uart = $value$plusargs("UART_EXPECT=%s", uart_expect);
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

            if (bus_we && bus_addr == MARK_ADDR) begin
                $display("[mark] %0d at cycle %0d (+%0d)", bus_wdata, cycles, cycles - last_mark);
                last_mark = cycles;
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
    // True if the first bytes the UART terminal received spell `s`
    // ($value$plusargs right-aligns the string; leading NULs are padding).
    function uart_received(input [1023:0] s);
        integer n, j, len;
        begin
            len = 0;
            for (n = 0; n < 128; n = n + 1)
                if (s[n*8 +: 8] != 8'd0)
                    len = n + 1;
            uart_received = (u_term.rx_count >= len);
            for (j = 0; j < len && uart_received; j = j + 1)
                if (u_term.rx_buf[j] != s[(len - 1 - j)*8 +: 8])
                    uart_received = 1'b0;
        end
    endfunction

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

            if (u_term.frame_errors != 0) begin
                $display("UART: %0d framing error(s) on the SoC's TX line", u_term.frame_errors);
                errors = errors + 1;
            end
            if (u_spi0.errors + u_spi1.errors + u_spi2.errors + u_spi3.errors != 0) begin
                $display("SPI: protocol error(s) seen by the slave models");
                errors = errors + 1;
            end
            if (check_uart && !uart_received(uart_expect)) begin
                $display("UART: expected the terminal to receive \"%0s\"", uart_expect);
                errors = errors + 1;
            end

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
