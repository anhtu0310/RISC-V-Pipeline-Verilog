`timescale 1ns / 1ps

// Behavioural SPI slave for testbenches, fixed mode (CPOL, CPHA), MSB first.
//
// After its chip select goes low the slave answers the first byte with ID
// and every later byte with the byte it received just before (an echo
// delayed by one byte). Received bytes are kept in `rx_log`.
// MISO is driven only while selected.
module spi_slave_model #(
    parameter       CPOL = 0,
    parameter       CPHA = 0,
    parameter [7:0] ID   = 8'hA0,
    parameter       NAME = "spi"
) (
    input  wire sclk,
    input  wire mosi,
    input  wire cs_n,
    output wire miso
);

    reg [7:0] tx, rx;
    reg       miso_r = 1'b0;
    reg       fresh;
    integer   nbits;

    reg [7:0] rx_log [0:255];
    integer   rx_count = 0;
    integer   errors   = 0;

    assign miso = cs_n ? 1'bz : miso_r;

    always @(negedge cs_n) begin
        tx    = ID;
        nbits = 0;
        fresh = 1'b1;
        if (sclk !== CPOL[0]) begin
            errors = errors + 1;
            $display("[%0s] SCLK not at idle level %0d when selected", NAME, CPOL);
        end
        if (CPHA == 0) begin
            miso_r = tx[7];
            fresh  = 1'b0;
        end
    end

    always @(posedge cs_n) begin
        if (nbits != 0) begin
            errors = errors + 1;
            $display("[%0s] deselected after %0d bits", NAME, nbits);
        end
    end

    // Leading edge: SCLK leaves its idle level.
    always @(sclk) if (!cs_n) begin
        if (sclk !== CPOL[0])
            leading_edge;
        else
            trailing_edge;
    end

    task sample;
        begin
            rx    = {rx[6:0], mosi};
            nbits = nbits + 1;
            if (nbits == 8) begin
                if (rx_count < 256)
                    rx_log[rx_count] = rx;
                rx_count = rx_count + 1;
                nbits    = 0;
                tx       = rx;      // echo next time
                fresh    = 1'b1;
            end
        end
    endtask

    task shift_out;
        begin
            if (fresh)
                fresh = 1'b0;
            else
                tx = {tx[6:0], 1'b0};
            miso_r = tx[7];
        end
    endtask

    task leading_edge;
        if (CPHA == 0) sample; else shift_out;
    endtask

    task trailing_edge;
        if (CPHA == 0) shift_out; else sample;
    endtask

endmodule
