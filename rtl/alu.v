// RV32I integer ALU (purely combinational).
module alu (
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result
);
`include "rv32i_defs.vh"

    wire [4:0] shamt = op_b[4:0];

    always @(*) begin
        case (alu_op)
            ALU_ADD:  result = op_a + op_b;
            ALU_SUB:  result = op_a - op_b;
            ALU_SLL:  result = op_a << shamt;
            ALU_SLT:  result = {31'd0, $signed(op_a) < $signed(op_b)};
            ALU_SLTU: result = {31'd0, op_a < op_b};
            ALU_XOR:  result = op_a ^ op_b;
            ALU_SRL:  result = op_a >> shamt;
            ALU_SRA:  result = $unsigned($signed(op_a) >>> shamt);
            ALU_OR:   result = op_a | op_b;
            ALU_AND:  result = op_a & op_b;
            default:  result = 32'd0;
        endcase
    end

endmodule
