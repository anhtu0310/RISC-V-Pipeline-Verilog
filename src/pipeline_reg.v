module IF_reg (
    input         clk,
    input         clear,
    input         rst_n,
    input         wr_en,

    input  [31:0] PC_next_in,
    input  [31:0] instr_in,
    input  [31:0] instr_addr_in,

    output [31:0] PC_next_out,
    output [31:0] instr_out,
    output [31:0] instr_addr_out
);

    reg [95:0] IF_data;

    assign {PC_next_out,instr_out,instr_addr_out} = IF_data;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n || clear)
            IF_data = 96'h0;
        else if (wr_en)
            IF_data = {PC_next_in,instr_in,instr_addr_in};
    end
    
endmodule

module ID_reg (
    input         clk,
    input         clear,
    input         rst_n,
    input         wr_en,

    input         jump_in,
    input         branch_in,
    input         mem_read_in,
    input         ALU_OP1_mux_in,
    input         ALU_OP2_mux_in,
    input  [3:0]  ALU_OP_in,
    input  [1:0]  reg_data_mux_in,
    input         reg_wr_en_in, 
    input         mem_wr_en_in,
    input  [2:0]  mem_control_in,
    input  [31:0] PC_next_in,
    input  [31:0] instr_addr_in,
    input  [31:0] rs1_in,
    input  [31:0] rs2_in,
    input  [31:0] immediate_in,
    input  [4:0]  reg_wr_addr_in,
    input  [4:0]  rs1_addr_in,
    input  [4:0]  rs2_addr_in,
    input  [6:0]  OPCODE_in,
    input  [2:0]  funct3_in,

    output         jump_out,
    output         branch_out,
    output         mem_read_out,
    output         ALU_OP1_mux_out,
    output         ALU_OP2_mux_out,
    output  [3:0]  ALU_OP_out,
    output  [1:0]  reg_data_mux_out,
    output         reg_wr_en_out, 
    output         mem_wr_en_out,
    output  [2:0]  mem_control_out,
    output  [31:0] PC_next_out,
    output  [31:0] instr_addr_out,
    output  [31:0] rs1_out,
    output  [31:0] rs2_out,
    output  [31:0] immediate_out,
    output  [4:0]  reg_wr_addr_out,
    output  [4:0]  rs1_addr_out,
    output  [4:0]  rs2_addr_out,
    output  [6:0]  OPCODE_out,
    output  [2:0]  funct3_out

);
    reg [200:0] ID_data;

    assign {jump_out,
            branch_out,
            mem_read_out,
            ALU_OP1_mux_out,
            ALU_OP2_mux_out,
            ALU_OP_out,
            reg_data_mux_out,
            reg_wr_en_out,
            mem_wr_en_out,
            mem_control_out,
            PC_next_out,
            instr_addr_out,
            rs1_out,
            rs2_out,
            immediate_out,
            reg_wr_addr_out,
            rs1_addr_out,
            rs2_addr_out,
            OPCODE_out,
            funct3_out
            } = ID_data;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n || clear)
            ID_data = 201'h0;
        else if (wr_en)
            ID_data = { jump_in,
                        branch_in,
                        mem_read_in,
                        ALU_OP1_mux_in,
                        ALU_OP2_mux_in,
                        ALU_OP_in,
                        reg_data_mux_in,
                        reg_wr_en_in,
                        mem_wr_en_in,
                        mem_control_in,
                        PC_next_in,
                        instr_addr_in,
                        rs1_in,
                        rs2_in,
                        immediate_in,
                        reg_wr_addr_in,
                        rs1_addr_in,
                        rs2_addr_in,
                        OPCODE_in,
                        funct3_in
                        };
    end
    
endmodule


module EX_reg (
    input         clk,
    input         clear,
    input         rst_n,
    input         wr_en,

    input  [1:0]  reg_data_mux_in,
    input         reg_wr_en_in, 
    input         mem_wr_en_in,
    input  [2:0]  mem_control_in,
    input  [31:0] PC_next_in,
    input  [31:0] ALU_result_in,
    input  [31:0] rs_OP2_in,
    input  [4:0]  reg_wr_addr_in,

    output [1:0]  reg_data_mux_out,
    output        reg_wr_en_out, 
    output        mem_wr_en_out,
    output [2:0]  mem_control_out,
    output [31:0] PC_next_out,
    output [31:0] ALU_result_out,
    output [31:0] rs_OP2_out,
    output [4:0]  reg_wr_addr_out

);
    reg [107:0] EX_data;

    assign {reg_data_mux_out,
            reg_wr_en_out, 
            mem_wr_en_out,
            mem_control_out,
            PC_next_out,
            ALU_result_out,
            rs_OP2_out,
            reg_wr_addr_out
            } = EX_data;
           
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n || clear)
            EX_data = 108'h0;
        else if (wr_en)
        EX_data = { reg_data_mux_in,
                    reg_wr_en_in, 
                    mem_wr_en_in,
                    mem_control_in,
                    PC_next_in,
                    ALU_result_in,
                    rs_OP2_in,
                    reg_wr_addr_in
                    };
    end
endmodule

module WB_reg (
    input         clk,
    input         clear,
    input         rst_n,
    input         wr_en, 

    input  [1:0]  reg_data_mux_in,
    input         reg_wr_en_in, 
    input  [31:0] PC_next_in,
    input  [31:0] ALU_result_in,
    input  [4:0]  reg_wr_addr_in,
    input  [31:0] mem_data_read_in,

    output [1:0]  reg_data_mux_out,
    output        reg_wr_en_out, 
    output [31:0] PC_next_out,
    output [31:0] ALU_result_out,
    output [4:0]  reg_wr_addr_out,
    output [31:0] mem_data_read_out
);
    
reg [103:0] WB_data;

assign           { reg_data_mux_out,
                   reg_wr_en_out, 
                   PC_next_out,
                   ALU_result_out,
                   reg_wr_addr_out,
                   mem_data_read_out
                 } = WB_data;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n || clear)
            WB_data = 104'h0;
        else if (wr_en)
            WB_data = { reg_data_mux_in,
                        reg_wr_en_in, 
                        PC_next_in,
                        ALU_result_in,
                        reg_wr_addr_in,
                        mem_data_read_in
                      };
    end
endmodule