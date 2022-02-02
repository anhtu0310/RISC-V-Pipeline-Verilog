module ALU (
  input   wire [31:0] op_1,
  input   wire [31:0] op_2,
  input   wire [3:0]  alu_op,
  
  output  reg  [31:0] alu_out
);

  // localparam OP_ADD = 4'b0000;
  // localparam OP_SUB = 4'b0001;
  // localparam OP_SLL = 4'b0010;
  // localparam OP_LSR = 4'b0011;
  // localparam OP_ASR = 4'b0100;
  // localparam OP_OR  = 4'b0101;
  // localparam OP_AND = 4'b0110;
  // localparam OP_XOR = 4'b0111;
  // localparam OP_EQL = 4'b1000;
  // localparam OP_ULT = 4'b1001;
  // localparam OP_UGT = 4'b1010;
  // localparam OP_SLT = 4'b1011;
  // localparam OP_SGT = 4'b1100;
  // localparam OP_BP  = 4'b1101;

  localparam OP_ADD = 4'b0000;
  localparam OP_SUB = 4'b0001;
  localparam OP_SLL = 4'b0010;
  localparam OP_SLT = 4'b0100;
  localparam OP_ULT = 4'b0110;
  localparam OP_XOR = 4'b1000;
  localparam OP_LSR = 4'b1010;
  localparam OP_ASR = 4'b1011;
  localparam OP_OR  = 4'b1100;
  localparam OP_AND = 4'b1110;
  localparam OP_BP  = 4'b0111;

  localparam OP_EQL = 4'b0011;
  localparam OP_UGT = 4'b0101;
  localparam OP_SGT = 4'b1001;


  reg signed [31:0] signed_op_1;
  reg signed [31:0] signed_op_2;

  always@(*) begin
    signed_op_1 = op_1;
    signed_op_2 = op_2;
    case (alu_op)
      OP_ADD : alu_out = op_1 + op_2;
      OP_SUB : alu_out = op_1 - op_2;
      OP_SLL : alu_out = op_1 << op_2[4:0];
      OP_SGT : alu_out = {31'h0, signed_op_1 >= signed_op_2};
      OP_UGT:  alu_out = {31'h0, op_1 >= op_2};
      OP_LSR:  alu_out = op_1>> op_2[4:0];
      OP_ASR:  alu_out = signed_op_1 >>> op_2[4:0];
      OP_OR :  alu_out = op_1 | op_2;
      OP_AND:  alu_out = op_1 & op_2;
      OP_XOR:  alu_out = op_1 ^ op_2;
      OP_EQL:  alu_out = {31'h0, op_1 == op_2};
      OP_ULT:  alu_out = {31'h0, op_1 < op_2};
      OP_SLT:  alu_out = {31'h0, signed_op_1 < signed_op_2};
      OP_BP :  alu_out = op_2;
      default: alu_out = 32'h0;
    endcase
  end



endmodule