`timescale 1ns / 1ps

// Behavioural I2C slave for testbenches: a 256-byte register file / EEPROM.
//
//   write: START, ADDR+W, ptr, data0, data1, ...  (pointer auto-increments)
//   read:  START, ADDR+R, then bytes mem[ptr++] until the master NACKs
//
// Other addresses are not acknowledged. With STRETCH > 0 the slave holds
// SCL low for STRETCH ns after each ACK bit (clock stretching), so the
// master's wait logic gets exercised. Protocol events are counted so a
// testbench can check them.
module i2c_slave_model #(
    parameter [6:0]   ADDR    = 7'h50,
    parameter integer STRETCH = 0,
    parameter         NAME    = "i2c"
) (
    inout wire scl,
    inout wire sda
);

    reg sda_low = 1'b0;
    reg scl_low = 1'b0;
    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_low ? 1'b0 : 1'bz;

    reg [7:0] mem [0:255];
    reg [7:0] ptr = 8'd0;

    integer starts = 0, stops = 0, bytes_rx = 0, bytes_tx = 0;
    reg     verbose = 1'b0;

    integer k;
    initial for (k = 0; k < 256; k = k + 1) mem[k] = k[7:0] ^ 8'h5a;

    localparam S_IDLE = 0, S_ADDR = 1, S_ACK = 2, S_RX = 3, S_TX = 4, S_MACK = 5;
    integer state = S_IDLE, next = S_IDLE;
    integer bitcnt = 0;
    reg [7:0] sh;
    reg       first_byte;
    reg       master_ack;

    // START / STOP: SDA changes while SCL is high.
    always @(negedge sda) if (scl === 1'b1) begin
        starts  = starts + 1;
        state   = S_ADDR;
        bitcnt  = 0;
        sda_low = 1'b0;
        if (verbose) $display("[%0s] START", NAME);
    end

    always @(posedge sda) if (scl === 1'b1) begin
        stops   = stops + 1;
        state   = S_IDLE;
        sda_low = 1'b0;
        if (verbose) $display("[%0s] STOP", NAME);
    end

    // Rising SCL: sample SDA
    always @(posedge scl) begin
        case (state)
            S_ADDR, S_RX: begin
                sh     = {sh[6:0], sda === 1'b0 ? 1'b0 : 1'b1};
                bitcnt = bitcnt + 1;
            end
            S_TX:   bitcnt = bitcnt + 1;
            S_MACK: master_ack = (sda === 1'b0);
            default: ;
        endcase
    end

    // Falling SCL: drive SDA for the next bit
    always @(negedge scl) begin
        case (state)
            S_ADDR:
                if (bitcnt == 8) begin
                    if (sh[7:1] == ADDR) begin
                        sda_low    = 1'b1;              // ACK
                        first_byte = 1'b1;
                        next       = sh[0] ? S_TX : S_RX;
                        state      = S_ACK;
                    end else begin
                        state = S_IDLE;                 // not us
                    end
                end
            S_RX:
                if (bitcnt == 8) begin
                    bytes_rx = bytes_rx + 1;
                    if (first_byte)
                        ptr = sh;
                    else begin
                        mem[ptr] = sh;
                        ptr      = ptr + 8'd1;
                    end
                    if (verbose) $display("[%0s] rx %02h", NAME, sh);
                    first_byte = 1'b0;
                    sda_low    = 1'b1;                  // ACK
                    next       = S_RX;
                    state      = S_ACK;
                end
            S_ACK: begin
                // End of the ACK clock
                sda_low = 1'b0;
                bitcnt  = 0;
                state   = next;
                if (next == S_TX)
                    load_tx;
                if (STRETCH > 0) begin
                    scl_low = 1'b1;
                    #(STRETCH) scl_low = 1'b0;
                end
            end
            S_TX:
                if (bitcnt == 8) begin
                    sda_low = 1'b0;                     // release for master ACK
                    state   = S_MACK;
                end else begin
                    sda_low = !sh[7 - bitcnt];
                end
            S_MACK:
                if (master_ack) begin
                    bitcnt = 0;
                    state  = S_TX;
                    load_tx;
                end else begin
                    state = S_IDLE;                     // NACK: wait for STOP / START
                end
            default: ;
        endcase
    end

    task load_tx;
        begin
            sh       = mem[ptr];
            ptr      = ptr + 8'd1;
            bytes_tx = bytes_tx + 1;
            sda_low  = !sh[7];
            if (verbose) $display("[%0s] tx %02h", NAME, sh);
        end
    endtask

endmodule
