`timescale 1ns / 1ps

// I2C master, byte-level command interface (single master, 7-bit or 10-bit
// addressing is up to software: the address byte is just a WRITE).
//
// Software queues one command at a time by writing CMD; the controller
// executes the selected parts in the order START -> WRITE or READ -> STOP
// and clears BUSY when done. So a register read from a typical device is:
//   TXDATA = addr<<1|0; CMD = START|WRITE      (check NACK)
//   TXDATA = reg;       CMD = WRITE
//   TXDATA = addr<<1|1; CMD = START|WRITE      (repeated start)
//   CMD = READ|NACK|STOP;  byte in RXDATA
//
// Bus timing: every SCL bit is four phases of (PRESCALE + 1) clocks, plus
// 3 clocks for the released SCL to be seen high through the input
// synchroniser, so f_SCL = f_clk / (4 * (PRESCALE + 1) + 3); PRESCALE = 249
// gives 99.7 kHz at 100 MHz. SCL and SDA are open-drain: the *_oe outputs pull the line low
// when 1, and the line must have a pull-up. The master waits while a slave
// holds SCL low (clock stretching).
//
// Registers (word offsets from the I2C base):
//   0x00 PRESCALE  RW [15:0]
//   0x04 TXDATA    RW [7:0]  byte for the next WRITE
//   0x08 RXDATA    R  [7:0]  byte from the last READ
//   0x0C CMD       W  [0] START  [1] STOP  [2] WRITE  [3] READ
//                     [4] NACK: answer the READ with NACK (last byte)
//                  Ignored while BUSY. WRITE wins if both WRITE and READ are set.
//   0x10 STATUS    R  [0] BUSY  [1] NACK: the slave did not acknowledge the
//                     last WRITE  [2] BUS_ACTIVE: between START and STOP
module i2c_master #(
    parameter [15:0] DEFAULT_PRESCALE = 16'd249
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sel,
    input  wire        we,
    input  wire        re,
    input  wire [5:0]  addr,
    // Only the low bytes of the registers are used.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    /* verilator lint_on UNUSEDSIGNAL */
    output reg  [31:0] rdata,

    input  wire        scl_i,
    output wire        scl_oe,      // 1 = pull SCL low
    input  wire        sda_i,
    output wire        sda_oe       // 1 = pull SDA low
);

    localparam [5:0] R_PRESCALE = 6'd0, R_TXDATA = 6'd1, R_RXDATA = 6'd2,
                     R_CMD      = 6'd3, R_STATUS = 6'd4;

    wire wr = sel && we;
    wire rd = sel && re;

    reg [15:0] prescale;
    reg [7:0]  txdata, rxdata;
    reg        nack, bus_active;

    // Pending command parts
    reg        do_start, do_stop, do_write, do_read, read_nack;

    // Input synchronisers
    reg [1:0] scl_sync, sda_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync <= 2'b11;
            sda_sync <= 2'b11;
        end else begin
            scl_sync <= {scl_sync[0], scl_i};
            sda_sync <= {sda_sync[0], sda_i};
        end
    end
    wire scl_in = scl_sync[1];
    wire sda_in = sda_sync[1];

    // ------------------------------------------------------------------
    // Bit engine
    // ------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0, S_START = 2'd1, S_BIT = 2'd2, S_STOP = 2'd3;

    reg [1:0]  state;
    reg [1:0]  phase;
    reg [15:0] cnt;
    reg [3:0]  bitn;        // 0..7 data bits, 8 = ACK bit
    reg [7:0]  shift;
    reg        scl_low, sda_low;
    reg        writing;     // current byte is a WRITE (else READ)

    wire busy = (state != S_IDLE) || do_start || do_write || do_read || do_stop;

    // Phase 1 drives SCL high and waits for it to actually be high
    // (a slave may be stretching the clock) before the timer runs.
    wire stretched = (phase == 2'd1) && !scl_in;
    wire phase_end = (cnt == 16'd0) && !stretched;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            phase      <= 2'd0;
            cnt        <= 16'd0;
            bitn       <= 4'd0;
            shift      <= 8'd0;
            scl_low    <= 1'b0;
            sda_low    <= 1'b0;
            writing    <= 1'b0;
            rxdata     <= 8'd0;
            nack       <= 1'b0;
            bus_active <= 1'b0;
            do_start   <= 1'b0;
            do_stop    <= 1'b0;
            do_write   <= 1'b0;
            do_read    <= 1'b0;
            read_nack  <= 1'b0;
        end else begin
            if (wr && addr == R_CMD && wstrb[0] && !busy) begin
                do_start  <= wdata[0];
                do_stop   <= wdata[1];
                do_write  <= wdata[2];
                do_read   <= wdata[3] && !wdata[2];
                read_nack <= wdata[4];
            end

            case (state)
                S_IDLE: begin
                    phase <= 2'd0;
                    cnt   <= prescale;
                    if (do_start) begin
                        do_start <= 1'b0;
                        state    <= S_START;
                    end else if (do_write || do_read) begin
                        writing  <= do_write;
                        shift    <= do_write ? txdata : 8'd0;
                        bitn     <= 4'd0;
                        do_write <= 1'b0;
                        do_read  <= 1'b0;
                        if (do_write)
                            nack <= 1'b0;
                        state    <= S_BIT;
                    end else if (do_stop) begin
                        do_stop <= 1'b0;
                        state   <= S_STOP;
                    end
                end

                // START / repeated START:
                //   0: release SDA   1: release SCL   2: SDA low (START)   3: SCL low
                S_START: begin
                    case (phase)
                        2'd0: sda_low <= 1'b0;
                        2'd1: scl_low <= 1'b0;
                        2'd2: sda_low <= 1'b1;
                        default: scl_low <= 1'b1;
                    endcase
                    if (phase_end) begin
                        cnt   <= prescale;
                        phase <= phase + 2'd1;
                        if (phase == 2'd3) begin
                            bus_active <= 1'b1;
                            state      <= S_IDLE;
                        end
                    end else if (!stretched) begin
                        cnt <= cnt - 16'd1;
                    end
                end

                // One data or ACK bit:
                //   0: SCL low, put the bit on SDA   1: release SCL
                //   2: SCL high, sample SDA at the end   3: SCL low
                S_BIT: begin
                    case (phase)
                        2'd0: begin
                            scl_low <= 1'b1;
                            if (bitn == 4'd8)
                                sda_low <= writing ? 1'b0 : !read_nack;   // ACK slot
                            else
                                sda_low <= writing ? !shift[7] : 1'b0;
                        end
                        2'd1: scl_low <= 1'b0;
                        2'd2: ;
                        default: scl_low <= 1'b1;
                    endcase
                    if (phase_end) begin
                        cnt   <= prescale;
                        phase <= phase + 2'd1;
                        if (phase == 2'd2) begin
                            if (bitn == 4'd8) begin
                                if (writing)
                                    nack <= sda_in;
                            end else begin
                                shift <= {shift[6:0], sda_in};
                            end
                        end
                        if (phase == 2'd3) begin
                            if (bitn == 4'd8) begin
                                if (!writing)
                                    rxdata <= shift;
                                sda_low <= 1'b0;     // release SDA after ACK
                                state   <= S_IDLE;
                            end
                            bitn <= bitn + 4'd1;
                        end
                    end else if (!stretched) begin
                        cnt <= cnt - 16'd1;
                    end
                end

                // STOP:
                //   0: SCL low, SDA low   1: release SCL   2: release SDA (STOP)   3: bus free time
                default: begin
                    case (phase)
                        2'd0: begin scl_low <= 1'b1; sda_low <= 1'b1; end
                        2'd1: scl_low <= 1'b0;
                        2'd2: sda_low <= 1'b0;
                        default: ;
                    endcase
                    if (phase_end) begin
                        cnt   <= prescale;
                        phase <= phase + 2'd1;
                        if (phase == 2'd3) begin
                            bus_active <= 1'b0;
                            state      <= S_IDLE;
                        end
                    end else if (!stretched) begin
                        cnt <= cnt - 16'd1;
                    end
                end
            endcase
        end
    end

    assign scl_oe = scl_low;
    assign sda_oe = sda_low;

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prescale <= DEFAULT_PRESCALE;
            txdata   <= 8'd0;
        end else if (wr) begin
            if (addr == R_PRESCALE) begin
                if (wstrb[0]) prescale[7:0]  <= wdata[7:0];
                if (wstrb[1]) prescale[15:8] <= wdata[15:8];
            end
            if (addr == R_TXDATA && wstrb[0])
                txdata <= wdata[7:0];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= 32'd0;
        else if (rd) begin
            case (addr)
                R_PRESCALE: rdata <= {16'd0, prescale};
                R_TXDATA:   rdata <= {24'd0, txdata};
                R_RXDATA:   rdata <= {24'd0, rxdata};
                R_STATUS:   rdata <= {29'd0, bus_active, nack, busy};
                default:    rdata <= 32'd0;
            endcase
        end
    end

endmodule
