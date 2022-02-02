module branch_comp (
    input wire  [31:0] branch_OP1,
    input wire  [31:0] branch_OP2,
    input wire  [2:0]  branch_OPCODE,
    // input wire  [6:0]  opcode,
    output wire        branch_taken
);

    localparam OP_EQL = 3'b000;
    localparam OP_NEQ = 3'b001;
    localparam OP_UGT = 3'b111; //Unsigned Greater Than or Equal
    localparam OP_SGT = 3'b101; //Signed Greater Than or Equal
    localparam OP_SLT = 3'b100;
    localparam OP_ULT = 3'b110;

    reg signed [31:0] signed_op_1;
    reg signed [31:0] signed_op_2;

    always @(*) 
    // if(opcode == 7'b110_0011)
    begin
        signed_op_1 = branch_OP1;
        signed_op_2 = branch_OP2;
    end
    
    // always @(*) begin
    // if(opcode == 7'b110_0011)
    // begin
    //     signed_op_1 = branch_OP1;
    //     signed_op_2 = branch_OP2;
    //     case (branch_OPCODE)
    //         OP_EQL: branch_taken = (branch_OP1 == branch_OP2);
    //         OP_NEQ: branch_taken = (branch_OP1 != branch_OP2);
    //         OP_UGT: branch_taken = (branch_OP1 >= branch_OP2);
    //         OP_ULT: branch_taken = (branch_OP1 <  branch_OP2);
    //         OP_SGT: branch_taken = (signed_op_1 >= signed_op_2);
    //         OP_SLT: branch_taken = (signed_op_1 < signed_op_2);
    //         default: branch_taken = 0;
    //     endcase
    // end
    // else 
    // branch_taken = 0;
    // end
    

    assign branch_taken = //(opcode == 7'b110_0011) ? 
                          (branch_OPCODE == OP_EQL) ? (branch_OP1 == branch_OP2):
                          (branch_OPCODE == OP_NEQ) ? (branch_OP1 != branch_OP2):
                          (branch_OPCODE == OP_UGT) ? (branch_OP1 >= branch_OP2):
                          (branch_OPCODE == OP_ULT) ? (branch_OP1 <  branch_OP2):
                          (branch_OPCODE == OP_SGT) ? (signed_op_1 >= signed_op_2):
                          (branch_OPCODE == OP_SLT) ? (signed_op_1 < signed_op_2):
                          1'b0;//:1'b0;

    // always @(branch_OPCODE) begin
    //     case(branch_OPCODE)
    //     3'b
    // end

endmodule

module comp_tb ();
    wire out;
    reg [31:0] a, b;
    reg [2:0] op;

    branch_comp bc(.branch_OP1(a),
                   .branch_OP2(b),
                   .branch_OPCODE(op),
                   .branch_taken(out));
    initial begin
        a = 5;
        b = -2;
        op = 3'b100;
        #10
        op = 3'b000;
        #10
        op = 3'b001;
    end
endmodule