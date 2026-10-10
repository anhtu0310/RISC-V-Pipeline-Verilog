// Shared constants for the RV32I pipeline.
// Included inside module bodies, so everything here is a localparam.
// verilator lint_off UNUSEDPARAM

// ---------------------------------------------------------------------------
// Major opcodes (instr[6:0])
// ---------------------------------------------------------------------------
localparam [6:0] OPC_LUI    = 7'b0110111;
localparam [6:0] OPC_AUIPC  = 7'b0010111;
localparam [6:0] OPC_JAL    = 7'b1101111;
localparam [6:0] OPC_JALR   = 7'b1100111;
localparam [6:0] OPC_BRANCH = 7'b1100011;
localparam [6:0] OPC_LOAD   = 7'b0000011;
localparam [6:0] OPC_STORE  = 7'b0100011;
localparam [6:0] OPC_OP_IMM = 7'b0010011;
localparam [6:0] OPC_OP     = 7'b0110011;
localparam [6:0] OPC_FENCE  = 7'b0001111;
localparam [6:0] OPC_SYSTEM = 7'b1110011;

// ---------------------------------------------------------------------------
// ALU operations: {alt, funct3}, where alt is instr[30] for SUB/SRA.
// Using the ISA encoding directly keeps the control unit trivial.
// ---------------------------------------------------------------------------
localparam [3:0] ALU_ADD  = 4'b0_000;
localparam [3:0] ALU_SUB  = 4'b1_000;
localparam [3:0] ALU_SLL  = 4'b0_001;
localparam [3:0] ALU_SLT  = 4'b0_010;
localparam [3:0] ALU_SLTU = 4'b0_011;
localparam [3:0] ALU_XOR  = 4'b0_100;
localparam [3:0] ALU_SRL  = 4'b0_101;
localparam [3:0] ALU_SRA  = 4'b1_101;
localparam [3:0] ALU_OR   = 4'b0_110;
localparam [3:0] ALU_AND  = 4'b0_111;

// ---------------------------------------------------------------------------
// ALU operand A select
// ---------------------------------------------------------------------------
localparam [1:0] OPA_RS1  = 2'd0;
localparam [1:0] OPA_PC   = 2'd1;
localparam [1:0] OPA_ZERO = 2'd2;

// ---------------------------------------------------------------------------
// Branch conditions (funct3 of B-type)
// ---------------------------------------------------------------------------
localparam [2:0] BR_EQ  = 3'b000;
localparam [2:0] BR_NE  = 3'b001;
localparam [2:0] BR_LT  = 3'b100;
localparam [2:0] BR_GE  = 3'b101;
localparam [2:0] BR_LTU = 3'b110;
localparam [2:0] BR_GEU = 3'b111;

// ---------------------------------------------------------------------------
// Load/store size (funct3 of LOAD/STORE)
// ---------------------------------------------------------------------------
localparam [2:0] MEM_B  = 3'b000;
localparam [2:0] MEM_H  = 3'b001;
localparam [2:0] MEM_W  = 3'b010;
localparam [2:0] MEM_BU = 3'b100;
localparam [2:0] MEM_HU = 3'b101;

localparam [31:0] INSTR_NOP = 32'h0000_0013; // addi x0, x0, 0
// verilator lint_on UNUSEDPARAM
