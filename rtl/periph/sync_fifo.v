`timescale 1ns / 1ps

// Small synchronous FIFO (first-word fall-through: rd_data shows the head
// entry whenever the FIFO is not empty). DEPTH must be a power of two.
// Pushing when full and popping when empty are ignored.
module sync_fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 8
) (
    input  wire             clk,
    input  wire             rst_n,

    input  wire             push,
    input  wire [WIDTH-1:0] wr_data,
    input  wire             pop,
    output wire [WIDTH-1:0] rd_data,

    output wire             empty,
    output wire             full
);

    localparam integer AW = $clog2(DEPTH);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [AW:0]      wr_ptr, rd_ptr;

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always @(posedge clk) begin
        if (do_push)
            mem[wr_ptr[AW-1:0]] <= wr_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(AW+1){1'b0}};
            rd_ptr <= {(AW+1){1'b0}};
        end else begin
            if (do_push)
                wr_ptr <= wr_ptr + 1'b1;
            if (do_pop)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

    assign rd_data = mem[rd_ptr[AW-1:0]];
    assign empty   = (wr_ptr == rd_ptr);
    assign full    = (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]) && (wr_ptr[AW] != rd_ptr[AW]);

endmodule
