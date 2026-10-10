`timescale 1ns / 1ps

// Behavioural UART terminal for testbenches (8N1).
//
//   * Receives what the DUT transmits on `rx` (bit time = `div` clocks of
//     `clk`), checks the stop bit, logs the text and keeps every byte in
//     `rx_buf`.
//   * If `echo` is set, sends every received byte straight back on `tx`.
//   * send_byte / send_bad_frame let a testbench drive the DUT's receiver.
//
// `div` and `echo` are variables so a testbench can change them at run time.
module uart_model #(
    parameter integer DIV  = 16,
    parameter         NAME = "uart"
) (
    input  wire clk,
    input  wire rx,         // from DUT uart_tx
    output reg  tx          // to DUT uart_rx
);

    integer div  = DIV;
    reg     echo = 1'b0;
    reg     verbose = 1'b1;

    reg [7:0] rx_buf [0:1023];
    integer   rx_count     = 0;
    integer   frame_errors = 0;

    reg [8*128-1:0] line;
    integer         line_len = 0;

    initial tx = 1'b1;

    // ------------------------------------------------------------------
    // Receiver
    // ------------------------------------------------------------------
    reg [7:0] b;
    integer   i;
    always begin
        @(negedge rx);
        // Middle of the start bit
        repeat (div / 2) @(posedge clk);
        if (rx == 1'b0) begin
            for (i = 0; i < 8; i = i + 1) begin
                repeat (div) @(posedge clk);
                b[i] = rx;
            end
            repeat (div) @(posedge clk);
            if (rx !== 1'b1) begin
                frame_errors = frame_errors + 1;
                $display("[%0s] framing error (byte %02h)", NAME, b);
            end else begin
                if (rx_count < 1024)
                    rx_buf[rx_count] = b;
                rx_count = rx_count + 1;
                log_char(b);
                if (echo)
                    fork send_byte(b); join_none
            end
        end
    end

    task log_char(input [7:0] c);
        begin
            if (c == 8'h0a || line_len == 127) begin
                if (verbose)
                    $display("[%0s] %0s", NAME, line);
                line     = 0;
                line_len = 0;
            end else if (c != 8'h0d) begin
                line     = {line[8*127-1:0], c};
                line_len = line_len + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Transmitter (serialised so overlapping callers queue up)
    // ------------------------------------------------------------------
    reg tx_lock = 1'b0;

    task automatic send_frame(input [7:0] data, input stop_bit);
        integer k;
        begin
            while (tx_lock) @(posedge clk);
            tx_lock = 1'b1;
            tx = 1'b0;
            repeat (div) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                tx = data[k];
                repeat (div) @(posedge clk);
            end
            tx = stop_bit;
            repeat (div) @(posedge clk);
            tx = 1'b1;
            repeat (div) @(posedge clk);   // idle gap
            tx_lock = 1'b0;
        end
    endtask

    task automatic send_byte(input [7:0] data);
        send_frame(data, 1'b1);
    endtask

    task automatic send_bad_frame(input [7:0] data);
        send_frame(data, 1'b0);
    endtask

    // Short low pulse that must not be taken as a start bit.
    task automatic send_glitch(input integer clocks);
        begin
            while (tx_lock) @(posedge clk);
            tx = 1'b0;
            repeat (clocks) @(posedge clk);
            tx = 1'b1;
        end
    endtask

endmodule
