`timescale 1ns / 1ps

// UART: 8 data bits, no parity, 1 stop bit (8N1), with TX and RX FIFOs.
//
// The baud rate is set by BAUD_DIV = clock frequency / baud rate (clock
// cycles per bit, minimum 4). The receiver synchronises uart_rx, detects
// the falling edge of the start bit, re-checks it half a bit later (to
// reject glitches) and then samples every bit in its middle.
//
// Registers (word offsets from the UART base):
//   0x00 DATA      W: push wdata[7:0] into the TX FIFO (dropped if full)
//                  R: pop the RX FIFO. [7:0] = byte, [31] = 1 if the FIFO
//                     was empty (byte not valid, nothing popped)
//   0x04 STATUS    R: [0] TX_FULL   [1] TX_EMPTY  [2] TX_IDLE (FIFO empty and
//                     last stop bit sent)  [3] RX_AVAIL  [4] RX_FULL
//                     [5] RX_OVERRUN (byte lost, RX FIFO was full)
//                     [6] FRAME_ERR (stop bit was 0, byte dropped)
//                  W: write 1 to bit 5 / bit 6 to clear those flags
//   0x08 BAUD_DIV  RW [15:0] clock cycles per bit
//   0x0C CTRL      RW [0] LOOPBACK: receiver listens to its own transmitter
//
// Reading DATA has a side effect (the pop), which the bus allows because a
// load in MEM is never cancelled.
module uart #(
    parameter integer   FIFO_DEPTH  = 8,
    parameter [15:0]    DEFAULT_DIV = 16'd868     // 115200 baud at 100 MHz
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

    output wire        uart_tx,
    input  wire        uart_rx
);

    localparam [5:0] R_DATA = 6'd0, R_STATUS = 6'd1, R_BAUD = 6'd2, R_CTRL = 6'd3;

    wire wr = sel && we;
    wire rd = sel && re;

    reg [15:0] baud_div;
    reg        loopback;
    reg        rx_overrun, frame_err;

    // ------------------------------------------------------------------
    // FIFOs
    // ------------------------------------------------------------------
    wire       tx_push = wr && addr == R_DATA && wstrb[0];
    wire       tx_pop;
    wire [7:0] tx_head;
    wire       tx_empty, tx_full;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_tx_fifo (
        .clk (clk), .rst_n (rst_n),
        .push (tx_push), .wr_data (wdata[7:0]),
        .pop (tx_pop), .rd_data (tx_head),
        .empty (tx_empty), .full (tx_full)
    );

    wire       rx_push;
    wire [7:0] rx_byte;
    wire       rx_pop = rd && addr == R_DATA;
    wire [7:0] rx_head;
    wire       rx_empty, rx_full;

    sync_fifo #(.WIDTH(8), .DEPTH(FIFO_DEPTH)) u_rx_fifo (
        .clk (clk), .rst_n (rst_n),
        .push (rx_push), .wr_data (rx_byte),
        .pop (rx_pop), .rd_data (rx_head),
        .empty (rx_empty), .full (rx_full)
    );

    // ------------------------------------------------------------------
    // Transmitter
    // ------------------------------------------------------------------
    reg [8:0]  tx_shift;    // {stop, data}, shifted out LSB first
    reg [3:0]  tx_bits;     // bits left to send, including the stop bit
    reg [15:0] tx_cnt;
    reg        tx_line;

    wire tx_busy = (tx_bits != 4'd0);
    assign tx_pop = !tx_busy && !tx_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift <= 9'h1ff;
            tx_bits  <= 4'd0;
            tx_cnt   <= 16'd0;
            tx_line  <= 1'b1;
        end else if (tx_pop) begin
            // Start bit goes out now.
            tx_shift <= {1'b1, tx_head};
            tx_line  <= 1'b0;
            tx_bits  <= 4'd10;
            tx_cnt   <= baud_div - 16'd1;
        end else if (tx_busy) begin
            if (tx_cnt == 16'd0) begin
                tx_cnt  <= baud_div - 16'd1;
                tx_bits <= tx_bits - 4'd1;
                if (tx_bits != 4'd1) begin
                    tx_line  <= tx_shift[0];
                    tx_shift <= {1'b1, tx_shift[8:1]};
                end
            end else begin
                tx_cnt <= tx_cnt - 16'd1;
            end
        end
    end

    assign uart_tx = tx_line;

    // ------------------------------------------------------------------
    // Receiver
    // ------------------------------------------------------------------
    reg rx_s1, rx_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s1 <= 1'b1;
            rx_s2 <= 1'b1;
        end else begin
            rx_s1 <= loopback ? tx_line : uart_rx;
            rx_s2 <= rx_s1;
        end
    end

    localparam [1:0] RX_IDLE = 2'd0, RX_START = 2'd1, RX_DATA = 2'd2, RX_STOP = 2'd3;

    reg [1:0]  rx_state;
    reg [15:0] rx_cnt;
    reg [2:0]  rx_bitn;
    reg [7:0]  rx_shift;
    reg        rx_done, rx_bad;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_cnt   <= 16'd0;
            rx_bitn  <= 3'd0;
            rx_shift <= 8'd0;
            rx_done  <= 1'b0;
            rx_bad   <= 1'b0;
        end else begin
            rx_done <= 1'b0;
            rx_bad  <= 1'b0;
            case (rx_state)
                RX_IDLE:
                    if (!rx_s2) begin
                        rx_state <= RX_START;
                        rx_cnt   <= {1'b0, baud_div[15:1]} - 16'd1;   // to mid-bit
                    end
                RX_START:
                    if (rx_cnt == 16'd0) begin
                        if (rx_s2) begin
                            rx_state <= RX_IDLE;            // glitch, not a start bit
                        end else begin
                            rx_state <= RX_DATA;
                            rx_cnt   <= baud_div - 16'd1;
                            rx_bitn  <= 3'd0;
                        end
                    end else begin
                        rx_cnt <= rx_cnt - 16'd1;
                    end
                RX_DATA:
                    if (rx_cnt == 16'd0) begin
                        rx_shift <= {rx_s2, rx_shift[7:1]};
                        rx_cnt   <= baud_div - 16'd1;
                        rx_bitn  <= rx_bitn + 3'd1;
                        if (rx_bitn == 3'd7)
                            rx_state <= RX_STOP;
                    end else begin
                        rx_cnt <= rx_cnt - 16'd1;
                    end
                default: // RX_STOP
                    if (rx_cnt == 16'd0) begin
                        rx_state <= RX_IDLE;
                        rx_done  <= rx_s2;
                        rx_bad   <= !rx_s2;
                    end else begin
                        rx_cnt <= rx_cnt - 16'd1;
                    end
            endcase
        end
    end

    assign rx_byte = rx_shift;
    assign rx_push = rx_done;

    // ------------------------------------------------------------------
    // Registers
    // ------------------------------------------------------------------
    wire clr_flags = wr && addr == R_STATUS && wstrb[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_div   <= DEFAULT_DIV;
            loopback   <= 1'b0;
            rx_overrun <= 1'b0;
            frame_err  <= 1'b0;
        end else begin
            if (wr && addr == R_BAUD) begin
                if (wstrb[0]) baud_div[7:0]  <= wdata[7:0];
                if (wstrb[1]) baud_div[15:8] <= wdata[15:8];
            end
            if (wr && addr == R_CTRL && wstrb[0])
                loopback <= wdata[0];

            if (rx_done && rx_full)
                rx_overrun <= 1'b1;
            else if (clr_flags && wdata[5])
                rx_overrun <= 1'b0;

            if (rx_bad)
                frame_err <= 1'b1;
            else if (clr_flags && wdata[6])
                frame_err <= 1'b0;
        end
    end

    wire [31:0] status = {25'd0, frame_err, rx_overrun, rx_full, !rx_empty,
                          !tx_busy && tx_empty, tx_empty, tx_full};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rdata <= 32'd0;
        else if (rd) begin
            case (addr)
                R_DATA:   rdata <= {rx_empty, 23'd0, rx_empty ? 8'd0 : rx_head};
                R_STATUS: rdata <= status;
                R_BAUD:   rdata <= {16'd0, baud_div};
                R_CTRL:   rdata <= {31'd0, loopback};
                default:  rdata <= 32'd0;
            endcase
        end
    end

endmodule
