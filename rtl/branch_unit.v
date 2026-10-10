// Branch condition evaluation for B-type instructions.
module branch_unit (
    input  wire [31:0] rs1,
    input  wire [31:0] rs2,
    input  wire [2:0]  funct3,
    output reg         taken
);
`include "rv32i_defs.vh"

    always @(*) begin
        case (funct3)
            BR_EQ:   taken = (rs1 == rs2);
            BR_NE:   taken = (rs1 != rs2);
            BR_LT:   taken = ($signed(rs1) <  $signed(rs2));
            BR_GE:   taken = ($signed(rs1) >= $signed(rs2));
            BR_LTU:  taken = (rs1 <  rs2);
            BR_GEU:  taken = (rs1 >= rs2);
            default: taken = 1'b0; // 010/011 are reserved encodings
        endcase
    end

endmodule
