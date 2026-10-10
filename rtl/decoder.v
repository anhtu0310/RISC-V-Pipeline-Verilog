`timescale 1ns / 1ps

// Instruction decoder: field extraction, immediate generation and control.
//
// Unknown or malformed encodings decode as a NOP and raise `illegal` so a
// wrapper can trap or count them. FENCE and SYSTEM (ECALL/EBREAK/CSR) are
// accepted but have no effect, since this core has no privileged architecture.
module decoder (
    input  wire [31:0] instr,

    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output reg  [31:0] imm,

    output reg         uses_rs1,   // instruction reads rs1 (for hazard detection)
    output reg         uses_rs2,   // instruction reads rs2
    output reg         reg_we,     // writes rd
    output reg  [3:0]  alu_op,
    output reg  [1:0]  opa_sel,    // OPA_RS1 / OPA_PC / OPA_ZERO
    output reg         opb_imm,    // 1: operand B is the immediate, 0: rs2
    output reg         is_branch,
    output reg         is_jal,
    output reg         is_jalr,
    output reg         mem_re,     // load
    output reg         mem_we,     // store
    output reg         illegal
);
`include "rv32i_defs.vh"

    wire [6:0] opcode = instr[6:0];
    wire [6:0] funct7 = instr[31:25];

    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];

    // Immediates, one per format.
    wire [31:0] imm_i = {{21{instr[31]}}, instr[30:20]};
    wire [31:0] imm_s = {{21{instr[31]}}, instr[30:25], instr[11:7]};
    wire [31:0] imm_b = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'd0};
    wire [31:0] imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    always @(*) begin
        imm       = 32'd0;
        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;
        reg_we    = 1'b0;
        alu_op    = ALU_ADD;
        opa_sel   = OPA_RS1;
        opb_imm   = 1'b1;
        is_branch = 1'b0;
        is_jal    = 1'b0;
        is_jalr   = 1'b0;
        mem_re    = 1'b0;
        mem_we    = 1'b0;
        illegal   = 1'b0;

        case (opcode)
            OPC_LUI: begin
                imm     = imm_u;
                reg_we  = 1'b1;
                opa_sel = OPA_ZERO;             // rd = 0 + imm
            end
            OPC_AUIPC: begin
                imm     = imm_u;
                reg_we  = 1'b1;
                opa_sel = OPA_PC;               // rd = pc + imm
            end
            OPC_JAL: begin
                imm     = imm_j;
                reg_we  = 1'b1;                 // rd = pc + 4 (selected in EX)
                is_jal  = 1'b1;
            end
            OPC_JALR: begin
                imm      = imm_i;
                uses_rs1 = 1'b1;
                reg_we   = 1'b1;
                is_jalr  = 1'b1;
                illegal  = (funct3 != 3'b000);
            end
            OPC_BRANCH: begin
                imm       = imm_b;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                is_branch = 1'b1;
                illegal   = (funct3 == 3'b010) || (funct3 == 3'b011);
            end
            OPC_LOAD: begin
                imm      = imm_i;
                uses_rs1 = 1'b1;
                reg_we   = 1'b1;
                mem_re   = 1'b1;
                illegal  = (funct3 == 3'b011) || (funct3 == 3'b110) || (funct3 == 3'b111);
            end
            OPC_STORE: begin
                imm      = imm_s;
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                mem_we   = 1'b1;
                illegal  = (funct3 > 3'b010);
            end
            OPC_OP_IMM: begin
                imm      = imm_i;
                uses_rs1 = 1'b1;
                reg_we   = 1'b1;
                // Only shifts use instr[30]; for every other OP-IMM it is
                // part of the immediate.
                alu_op   = {(funct3 == 3'b101) & instr[30], funct3};
                illegal  = ((funct3 == 3'b001) && (funct7 != 7'b0000000)) ||
                           ((funct3 == 3'b101) && (funct7 != 7'b0000000) &&
                                                  (funct7 != 7'b0100000));
            end
            OPC_OP: begin
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                reg_we   = 1'b1;
                opb_imm  = 1'b0;
                alu_op   = {instr[30], funct3};
                illegal  = !((funct7 == 7'b0000000) ||
                             ((funct7 == 7'b0100000) &&
                              ((funct3 == 3'b000) || (funct3 == 3'b101))));
            end
            OPC_FENCE: begin
                // Single-issue in-order core with no caches: FENCE is a NOP.
            end
            OPC_SYSTEM: begin
                // ECALL/EBREAK/CSR are not implemented (no privileged
                // architecture); they retire as NOPs.
            end
            default: illegal = 1'b1;
        endcase

        // An illegal instruction must not change architectural state.
        if (illegal) begin
            reg_we    = 1'b0;
            mem_re    = 1'b0;
            mem_we    = 1'b0;
            is_branch = 1'b0;
            is_jal    = 1'b0;
            is_jalr   = 1'b0;
            uses_rs1  = 1'b0;
            uses_rs2  = 1'b0;
        end
    end

endmodule
