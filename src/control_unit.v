module controller(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    // input  wire       branch_taken,
    output reg         jump,
    output reg         branch,
    output reg         ALU_OP1_mux,
    output reg         ALU_OP2_mux,
    output reg  [3:0]  ALU_OP,
    output reg  [1:0]  reg_data_mux,
    output reg         reg_wr_en, 
    output reg         mem_wr_en,
    output reg  [2:0]  mem_control,
    output reg         mem_read
);

    // reg [1:0] ALU_mode;

    localparam OP_ADD = 4'b0000;
    localparam OP_BP  = 4'b0111;

    always @(opcode or funct3 or funct7) begin
        jump         = 0;
        branch       = 0;
        mem_read     = 0;
        // PC_mux       = 0;
        ALU_OP1_mux  = 0;
        ALU_OP2_mux  = 0;
        reg_wr_en    = 0;
        mem_wr_en    = 0;
        reg_data_mux = 0;
        ALU_OP       = 4'hf;
        mem_control  = 3'b010;
        // branch = 0;
        case (opcode)
            7'b011_0011: //R-type
            begin
                ALU_OP2_mux  = 1;
                reg_wr_en = 1; 
                reg_data_mux = 2'b01;
                ALU_OP = {funct3,funct7[5]};

            end
            7'b001_0011: //I-type
            begin
                reg_data_mux = 2'b01;
                reg_wr_en = 1; 
                ALU_OP = (funct3 == 3'b101) ? {funct3,funct7[5]}:{funct3,1'b0};
            end
            7'b010_0011: //s-type
            begin
                // reg_wr_en = 0;
                mem_wr_en = 1;
                reg_data_mux = 2'b01;
                mem_control = funct3;
                ALU_OP = OP_ADD;
            end
            7'b000_0011: // l-type
            begin
                mem_control = funct3;
                reg_wr_en = 1;
                ALU_OP = OP_ADD;
                mem_read = 1;
            end 
            7'b110_0011: //B-type
            begin 
                // PC_mux = 
                // if(branch_taken)
                //     PC_mux = 1;
                branch = 1;
                ALU_OP1_mux = 1; 
                // reg_wr_en = 0;
                ALU_OP = OP_ADD;

            end
            7'b110_0111: //JALR
            begin
                reg_wr_en = 1;
                reg_data_mux = 2'b11;
                ALU_OP = OP_ADD;
                jump = 1;
            end
            7'b110_1111: //JAL
            begin
                jump = 1;
                reg_wr_en = 1;
                // PC_mux = 1;
                ALU_OP1_mux = 1; 
                reg_data_mux = 2'b11;
                ALU_OP = OP_ADD;
            end
            7'b011_0111: //LUI
            begin 
                reg_wr_en = 1;
                reg_data_mux = 2'b01;
                ALU_OP = OP_BP;
            end
            7'b001_0111: //AUIPC
            begin 
                reg_wr_en = 1;
                ALU_OP1_mux = 1; 
                reg_data_mux = 2'b01;
                ALU_OP = OP_ADD;
            end
        endcase
    end
endmodule

