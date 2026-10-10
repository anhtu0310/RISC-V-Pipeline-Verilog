`timescale 1ns / 1ps

// Register-level tests for the peripherals (GPIO, UART, I2C, SPI).
//
// The peripherals are driven straight through their bus ports (same timing
// as the core: request for one cycle, registered read data the next cycle)
// against behavioural models of the outside world:
//   UART  <-> uart_model (terminal)
//   I2C   <-> two i2c_slave_model devices on an open-drain bus with pull-ups
//              (0x50 stretches the clock, 0x51 does not)
//   SPI   <-> four spi_slave_model devices, one per chip select, in modes 0..3
//   GPIO  <-> testbench-driven pins
// Every check counts towards a final "TEST PASSED" / "TEST FAILED".
module tb_periph;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    // ------------------------------------------------------------------
    // Shared bus
    // ------------------------------------------------------------------
    reg  [3:0]  sel = 4'b0000;     // one-hot: {spi, i2c, uart, gpio}
    reg         we = 1'b0, re = 1'b0;
    reg  [5:0]  addr = 6'd0;
    reg  [31:0] wdata = 32'd0;
    reg  [3:0]  wstrb = 4'd0;
    wire [31:0] rdata_gpio, rdata_uart, rdata_i2c, rdata_spi;

    localparam GPIO = 0, UART = 1, I2C = 2, SPI = 3;

    reg [1:0] last_dev;

    task bus_write(input integer dev, input [7:0] off, input [31:0] d, input [3:0] strb);
        begin
            @(negedge clk);
            sel = 4'b0001 << dev; we = 1'b1; addr = off[7:2]; wdata = d; wstrb = strb;
            @(negedge clk);
            sel = 4'b0000; we = 1'b0; wstrb = 4'd0;
        end
    endtask

    task wr(input integer dev, input [7:0] off, input [31:0] d);
        bus_write(dev, off, d, 4'b1111);
    endtask

    task rd(input integer dev, input [7:0] off, output [31:0] d);
        begin
            @(negedge clk);
            sel = 4'b0001 << dev; re = 1'b1; addr = off[7:2];
            @(negedge clk);
            sel = 4'b0000; re = 1'b0;
            case (dev)
                GPIO:    d = rdata_gpio;
                UART:    d = rdata_uart;
                I2C:     d = rdata_i2c;
                default: d = rdata_spi;
            endcase
        end
    endtask

    task check(input [8*48-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL %0s: got %08h expected %08h", what, got, exp);
            end
        end
    endtask

    reg [31:0] v;

    // ------------------------------------------------------------------
    // GPIO
    // ------------------------------------------------------------------
    reg  [31:0] gpio_in = 32'd0;
    wire [31:0] gpio_out, gpio_oe;

    gpio #(.N(32)) u_gpio (
        .clk (clk), .rst_n (rst_n),
        .sel (sel[GPIO]), .we (we), .re (re), .addr (addr),
        .wdata (wdata), .wstrb (wstrb), .rdata (rdata_gpio),
        .gpio_in (gpio_in), .gpio_out (gpio_out), .gpio_oe (gpio_oe)
    );

    task test_gpio;
        begin
            $display("--- GPIO");
            rd(GPIO, 8'h04, v); check("gpio reset DATA_OUT", v, 0);
            rd(GPIO, 8'h08, v); check("gpio reset DIR", v, 0);
            check("gpio reset oe pins", gpio_oe, 0);

            wr(GPIO, 8'h08, 32'h0000_ffff);
            wr(GPIO, 8'h04, 32'h1234_5678);
            check("gpio out pins", gpio_out, 32'h1234_5678);
            check("gpio oe pins", gpio_oe, 32'h0000_ffff);
            rd(GPIO, 8'h04, v); check("gpio DATA_OUT readback", v, 32'h1234_5678);

            bus_write(GPIO, 8'h04, 32'hAB00_CD00, 4'b0010);     // byte 1 only
            check("gpio byte-lane write", gpio_out, 32'h1234_CD78);
            bus_write(GPIO, 8'h04, 32'hEEFF_0000, 4'b1100);     // upper half only
            check("gpio half-word write", gpio_out, 32'hEEFF_CD78);

            wr(GPIO, 8'h0C, 32'h0000_0003); check("gpio SET", gpio_out, 32'hEEFF_CD7B);
            wr(GPIO, 8'h10, 32'h0000_0078); check("gpio CLR", gpio_out, 32'hEEFF_CD03);
            wr(GPIO, 8'h14, 32'hFFFF_0000); check("gpio TGL", gpio_out, 32'h1100_CD03);

            // Inputs pass a 2-flop synchroniser
            gpio_in = 32'hCAFE_0001;
            repeat (2) @(negedge clk);
            rd(GPIO, 8'h00, v); check("gpio DATA_IN after sync", v, 32'hCAFE_0001);

            // Edge latches (sticky, write-1-to-clear)
            wr(GPIO, 8'h18, 32'hFFFF_FFFF);
            wr(GPIO, 8'h1C, 32'hFFFF_FFFF);
            @(negedge clk) gpio_in = 32'hCAFE_0003;    // bit 1 rises
            @(negedge clk) gpio_in = 32'hCAFE_0001;    // ... for one cycle only
            @(negedge clk) gpio_in = 32'h4AFE_0001;    // bit 31 falls
            repeat (4) @(negedge clk);
            rd(GPIO, 8'h18, v); check("gpio RISE latched 1-cycle pulse", v, 32'h0000_0002);
            rd(GPIO, 8'h1C, v); check("gpio FALL", v, 32'h8000_0002);
            wr(GPIO, 8'h1C, 32'h0000_0002);
            rd(GPIO, 8'h1C, v); check("gpio FALL W1C", v, 32'h8000_0000);
            rd(GPIO, 8'h20, v); check("gpio unused offset", v, 0);
        end
    endtask

    // ------------------------------------------------------------------
    // UART
    // ------------------------------------------------------------------
    localparam integer UDIV = 8;
    wire uart_tx, uart_rx;

    uart #(.FIFO_DEPTH(8), .DEFAULT_DIV(UDIV)) u_uart (
        .clk (clk), .rst_n (rst_n),
        .sel (sel[UART]), .we (we), .re (re), .addr (addr),
        .wdata (wdata), .wstrb (wstrb), .rdata (rdata_uart),
        .uart_tx (uart_tx), .uart_rx (uart_rx)
    );

    uart_model #(.DIV(UDIV), .NAME("uart")) u_term (
        .clk (clk), .rx (uart_tx), .tx (uart_rx)
    );

    task uart_wait_idle;
        begin
            v = 0;
            while (!v[2]) rd(UART, 8'h04, v);
        end
    endtask

    integer n0, t0, t1;
    task test_uart;
        integer k;
        begin
            $display("--- UART");
            rd(UART, 8'h08, v); check("uart reset BAUD_DIV", v, UDIV);
            rd(UART, 8'h04, v); check("uart reset STATUS", v, 32'h06);   // TX_EMPTY | TX_IDLE

            // Transmit, and check the bit time on the wire
            n0 = u_term.rx_count;
            fork
                begin
                    @(negedge uart_tx) t0 = $time;
                    @(posedge uart_tx) t1 = $time;
                end
                begin
                    wr(UART, 8'h00, "H"); wr(UART, 8'h00, "i"); wr(UART, 8'h00, "!");
                end
            join
            // 'H' = 0x48 goes out LSB first: start bit + three 0 bits
            check("uart low time of 'H' (ns)", t1 - t0, 4 * UDIV * 10);
            uart_wait_idle;
            check("uart bytes sent", u_term.rx_count - n0, 3);
            check("uart byte 0", u_term.rx_buf[n0], "H");
            check("uart byte 2", u_term.rx_buf[n0 + 2], "!");

            // TX FIFO full: one byte goes to the shifter, 8 wait, the rest drop
            n0 = u_term.rx_count;
            for (k = 0; k < 11; k = k + 1)
                wr(UART, 8'h00, 8'h30 + k);
            rd(UART, 8'h04, v); check("uart TX_FULL", v[0], 1);
            uart_wait_idle;
            check("uart bytes after overflow", u_term.rx_count - n0, 9);
            check("uart last kept byte", u_term.rx_buf[n0 + 8], 8'h38);

            // Receive
            rd(UART, 8'h00, v); check("uart empty read flag", v, 32'h8000_0000);
            u_term.send_byte(8'hA5);
            u_term.send_byte(8'h00);
            u_term.send_byte(8'hFF);
            rd(UART, 8'h04, v); check("uart RX_AVAIL", v[3], 1);
            rd(UART, 8'h00, v); check("uart rx 0", v, 32'hA5);
            rd(UART, 8'h00, v); check("uart rx 1", v, 32'h00);
            rd(UART, 8'h00, v); check("uart rx 2", v, 32'hFF);
            rd(UART, 8'h04, v); check("uart RX empty again", v[3], 0);

            // Overrun: 9 bytes into an 8-deep FIFO
            for (k = 0; k < 9; k = k + 1)
                u_term.send_byte(8'h40 + k);
            rd(UART, 8'h04, v); check("uart RX_FULL", v[4], 1);
            check("uart RX_OVERRUN", v[5], 1);
            for (k = 0; k < 8; k = k + 1) begin
                rd(UART, 8'h00, v); check("uart rx after overrun", v, 8'h40 + k);
            end
            wr(UART, 8'h04, 32'h20);
            rd(UART, 8'h04, v); check("uart OVERRUN cleared", v[5], 0);

            // Framing error: byte dropped, flag set
            u_term.send_bad_frame(8'h55);
            repeat (UDIV * 2) @(posedge clk);
            rd(UART, 8'h04, v); check("uart FRAME_ERR", v[6], 1);
            check("uart bad frame not stored", v[3], 0);
            wr(UART, 8'h04, 32'h40);
            rd(UART, 8'h04, v); check("uart FRAME_ERR cleared", v[6], 0);

            // A glitch shorter than half a bit is not a start bit
            u_term.send_glitch(UDIV / 2 - 2);
            repeat (UDIV * 12) @(posedge clk);
            rd(UART, 8'h04, v); check("uart glitch rejected", v[3] | v[6], 0);

            // Different (odd) divider on both sides
            wr(UART, 8'h08, 13); u_term.div = 13;
            n0 = u_term.rx_count;
            wr(UART, 8'h00, 8'h96);
            uart_wait_idle;
            check("uart div=13 tx", u_term.rx_buf[n0], 8'h96);
            u_term.send_byte(8'h69);
            rd(UART, 8'h00, v); check("uart div=13 rx", v, 8'h69);

            // Internal loopback
            wr(UART, 8'h0C, 1);
            wr(UART, 8'h00, 8'h3C);
            uart_wait_idle;
            repeat (13) @(posedge clk);
            rd(UART, 8'h00, v); check("uart loopback", v, 8'h3C);
            wr(UART, 8'h0C, 0);
            rd(UART, 8'h0C, v); check("uart CTRL readback", v, 0);
        end
    endtask

    // ------------------------------------------------------------------
    // I2C
    // ------------------------------------------------------------------
    wire scl, sda;
    wire scl_oe, sda_oe;
    pullup (scl);
    pullup (sda);
    assign scl = scl_oe ? 1'b0 : 1'bz;
    assign sda = sda_oe ? 1'b0 : 1'bz;

    i2c_master #(.DEFAULT_PRESCALE(16'd3)) u_i2c (
        .clk (clk), .rst_n (rst_n),
        .sel (sel[I2C]), .we (we), .re (re), .addr (addr),
        .wdata (wdata), .wstrb (wstrb), .rdata (rdata_i2c),
        .scl_i (scl), .scl_oe (scl_oe), .sda_i (sda), .sda_oe (sda_oe)
    );

    i2c_slave_model #(.ADDR(7'h50), .STRETCH(300), .NAME("eeprom50")) u_eep50 (.scl (scl), .sda (sda));
    i2c_slave_model #(.ADDR(7'h51), .STRETCH(0),   .NAME("eeprom51")) u_eep51 (.scl (scl), .sda (sda));

    localparam [31:0] I2C_START = 1, I2C_STOP = 2, I2C_WRITE = 4, I2C_READ = 8, I2C_NACK = 16;

    task i2c_cmd(input [31:0] c);
        begin
            wr(I2C, 8'h0C, c);
            v = 1;
            while (v[0]) rd(I2C, 8'h10, v);
        end
    endtask

    task i2c_write(input [7:0] b, input [31:0] extra);
        begin
            wr(I2C, 8'h04, b);
            i2c_cmd(I2C_WRITE | extra);
        end
    endtask

    // SCL low time held by a slave (clock stretching) is visible as the
    // master releasing SCL while the line stays low.
    integer stretch_cycles = 0;
    always @(posedge clk) if (!scl_oe && scl === 1'b0) stretch_cycles = stretch_cycles + 1;

    integer s0, p0;
    reg [7:0] b0, b1, b2;
    task test_i2c;
        begin
            $display("--- I2C");
            rd(I2C, 8'h00, v); check("i2c reset PRESCALE", v, 3);
            rd(I2C, 8'h10, v); check("i2c reset STATUS", v, 0);
            check("i2c lines idle high", {scl, sda}, 2'b11);

            // Write 3 bytes at pointer 0x10 of device 0x50
            s0 = u_eep50.starts; p0 = u_eep50.stops;
            i2c_write({7'h50, 1'b0}, I2C_START);
            rd(I2C, 8'h10, v); check("i2c addr ACK / bus active", v, 32'h4);
            i2c_write(8'h10, 0);
            i2c_write(8'hDE, 0);
            i2c_write(8'hAD, 0);
            i2c_write(8'hBE, I2C_STOP);
            rd(I2C, 8'h10, v); check("i2c idle after STOP", v, 0);
            check("i2c slave memory 0x10", u_eep50.mem[8'h10], 8'hDE);
            check("i2c slave memory 0x12", u_eep50.mem[8'h12], 8'hBE);
            check("i2c START/STOP seen", {u_eep50.starts - s0, u_eep50.stops - p0}, {32'd1, 32'd1});
            check("i2c other slave untouched", u_eep51.mem[8'h10], 8'h10 ^ 8'h5a);
            check("i2c clock stretching seen", stretch_cycles > 20, 1);

            // Read them back: set pointer, repeated START, read 3 bytes
            i2c_write({7'h50, 1'b0}, I2C_START);
            i2c_write(8'h10, 0);
            i2c_write({7'h50, 1'b1}, I2C_START);
            i2c_cmd(I2C_READ);              rd(I2C, 8'h08, v); b0 = v[7:0];
            i2c_cmd(I2C_READ);              rd(I2C, 8'h08, v); b1 = v[7:0];
            i2c_cmd(I2C_READ | I2C_NACK | I2C_STOP); rd(I2C, 8'h08, v); b2 = v[7:0];
            check("i2c read back", {b0, b1, b2}, 24'hDEADBE);
            check("i2c slave sent 3 bytes", u_eep50.bytes_tx, 3);

            // Second device, no stretching, default contents
            i2c_write({7'h51, 1'b0}, I2C_START);
            i2c_write(8'h80, 0);
            i2c_write({7'h51, 1'b1}, I2C_START);
            i2c_cmd(I2C_READ | I2C_NACK | I2C_STOP); rd(I2C, 8'h08, v);
            check("i2c device 0x51 read", v, 8'h80 ^ 8'h5a);

            // Nobody at 0x23: NACK
            i2c_write({7'h23, 1'b0}, I2C_START);
            rd(I2C, 8'h10, v); check("i2c address NACK", v[1], 1);
            i2c_cmd(I2C_STOP);
            rd(I2C, 8'h10, v); check("i2c idle after NACK+STOP", v, 32'h2);
            check("i2c lines released", {scl, sda}, 2'b11);

            // SCL frequency: one bit = 4 * (PRESCALE + 1) clocks
            wr(I2C, 8'h00, 9);
            rd(I2C, 8'h00, v); check("i2c PRESCALE write", v, 9);
            fork
                i2c_write({7'h51, 1'b0}, I2C_START | I2C_STOP);
                begin
                    @(negedge sda);                 // START
                    @(posedge scl) t0 = $time;      // first data bit
                    @(posedge scl) t1 = $time;
                end
            join
            // 4 phases of PRESCALE+1 clocks, plus 3 clocks for SCL to pass
            // the input synchroniser before the high phase starts counting
            check("i2c SCL period (ns)", t1 - t0, (4 * 10 + 3) * 10);
            check("i2c 0x50 received only its own bytes", u_eep50.bytes_rx, 4 + 1);
        end
    endtask

    // ------------------------------------------------------------------
    // SPI
    // ------------------------------------------------------------------
    wire       sclk, mosi, miso;
    wire [3:0] cs_n;
    pullup (miso);

    spi_master #(.NCS(4), .DEFAULT_DIV(16'd2)) u_spi (
        .clk (clk), .rst_n (rst_n),
        .sel (sel[SPI]), .we (we), .re (re), .addr (addr),
        .wdata (wdata), .wstrb (wstrb), .rdata (rdata_spi),
        .spi_sclk (sclk), .spi_mosi (mosi), .spi_miso (miso), .spi_cs_n (cs_n)
    );

    spi_slave_model #(.CPOL(0), .CPHA(0), .ID(8'hA0), .NAME("spi0")) u_spi0 (.sclk(sclk), .mosi(mosi), .cs_n(cs_n[0]), .miso(miso));
    spi_slave_model #(.CPOL(0), .CPHA(1), .ID(8'hA1), .NAME("spi1")) u_spi1 (.sclk(sclk), .mosi(mosi), .cs_n(cs_n[1]), .miso(miso));
    spi_slave_model #(.CPOL(1), .CPHA(0), .ID(8'hA2), .NAME("spi2")) u_spi2 (.sclk(sclk), .mosi(mosi), .cs_n(cs_n[2]), .miso(miso));
    spi_slave_model #(.CPOL(1), .CPHA(1), .ID(8'hA3), .NAME("spi3")) u_spi3 (.sclk(sclk), .mosi(mosi), .cs_n(cs_n[3]), .miso(miso));

    task spi_xfer(input [7:0] tx, output [7:0] rx);
        begin
            wr(SPI, 8'h0C, tx);
            v = 1;
            while (v[0]) rd(SPI, 8'h10, v);
            rd(SPI, 8'h0C, v);
            rx = v[7:0];
        end
    endtask

    integer sclk_edges = 0;
    always @(sclk) sclk_edges = sclk_edges + 1;

    reg [7:0] r0, r1, r2, r3;
    integer   m, e0, c0;
    task test_spi;
        begin
            $display("--- SPI");
            rd(SPI, 8'h04, v); check("spi reset CLKDIV", v, 2);
            check("spi reset cs_n", cs_n, 4'hF);

            for (m = 0; m < 4; m = m + 1) begin
                // Slave m uses CPOL = m[1], CPHA = m[0]
                wr(SPI, 8'h00, {m[0], m[1]});
                repeat (2) @(posedge clk);
                check("spi SCLK idle level", sclk, m[1]);
                wr(SPI, 8'h08, 1 << m);
                check("spi cs_n", cs_n, 4'hF ^ (4'b0001 << m[1:0]));
                e0 = sclk_edges;
                spi_xfer(8'h3C, r0);
                check("spi 16 SCLK edges per byte", sclk_edges - e0, 16);
                spi_xfer(8'h81, r1);
                spi_xfer(8'hFF, r2);
                spi_xfer(8'h00, r3);
                wr(SPI, 8'h08, 0);
                check("spi mode rx", {r0, r1, r2, r3}, {8'hA0 + m[7:0], 8'h3C, 8'h81, 8'hFF});
            end
            check("spi slave 0 got bytes", {u_spi0.rx_log[0], u_spi0.rx_log[3]}, 16'h3C00);
            check("spi slave 3 got bytes", {u_spi3.rx_log[1], u_spi3.rx_log[2]}, 16'h81FF);
            check("spi slave protocol errors",
                  u_spi0.errors + u_spi1.errors + u_spi2.errors + u_spi3.errors, 0);

            // LSB first (slave is MSB first, so it sees the byte reversed)
            wr(SPI, 8'h00, 32'h4);              // mode 0, LSB first
            wr(SPI, 8'h08, 1);
            c0 = u_spi0.rx_count;
            spi_xfer(8'h01, r0);
            spi_xfer(8'h00, r1);
            wr(SPI, 8'h08, 0);
            check("spi LSB-first tx seen reversed", u_spi0.rx_log[c0], 8'h80);
            check("spi LSB-first rx reversed ID", r0, 8'h05);         // 0xA0 reversed
            check("spi LSB-first echo", r1, 8'h01);

            // Fastest clock (CLKDIV = 0) and transfer length in clocks
            wr(SPI, 8'h04, 0);
            wr(SPI, 8'h00, 32'h2);              // mode 1 (CPHA = 1) for slave 1
            wr(SPI, 8'h08, 2);
            spi_xfer(8'h5A, r0);
            spi_xfer(8'hC3, r1);
            wr(SPI, 8'h08, 0);
            check("spi div=0 transfer", {r0, r1}, 16'hA15A);
            @(negedge clk);
            sel = 4'b1000; we = 1'b1; addr = 6'd3; wdata = 8'h11; wstrb = 4'b1111;
            @(negedge clk);
            sel = 4'b0000; we = 1'b0;
            c0 = 0;
            while (u_spi.busy) begin
                @(negedge clk);
                c0 = c0 + 1;
            end
            check("spi div=0 busy clocks", c0, 16 + 1);
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("build/tb_periph.vcd");
            $dumpvars(0, tb_periph);
        end
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        test_gpio;
        test_uart;
        test_i2c;
        test_spi;

        check("uart: terminal saw no framing errors", u_term.frame_errors, 0);

        $display("------------------------------------------------------------");
        $display("peripheral checks: %0d, failures: %0d", checks, errors);
        if (errors == 0) begin
            $display("TEST PASSED");
            $finish;
        end else begin
            $display("TEST FAILED: %0d peripheral check(s) failed", errors);
            $fatal(1);
        end
    end

    initial begin
        #5_000_000;
        $display("TEST FAILED: timeout");
        $fatal(1);
    end

endmodule
