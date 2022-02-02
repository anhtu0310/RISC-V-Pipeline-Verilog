module RiscV_pipeline (
       input wire clk,
    input wire rst_n,
// );
    output
    wire [31:0] instr_0,
                instr_1,

                rs1_out_0,
                rs1_out_1,

                rs2_out_0,
                rs2_out_1,
                
                rs1_w_fwd,
                rs2_w_fwd_0,
                rs2_w_fwd_1,


                PC_next_0,
                PC_next_1,
                PC_next_2,
                PC_next_3,
                PC_next_4,
                
                ALU_OP1,
                ALU_OP2,

                immediate_0,
                immediate_1,

                ALU_result_0,
                ALU_result_1,
                ALU_result_2,

                reg_data_in,

                mem_data_out_0,
                mem_data_out_1,
                instr_mem_addr_0,
                instr_mem_addr_1,
                instr_mem_addr_2,
                // instr_mem_addr_3,
    output
    wire        PC_mux,
                branch_0,
                branch_1,

                jump_0,
                jump_1,

                // PC_mux_cu,/
                ALU_OP1_mux_0,
                ALU_OP1_mux_1,

                ALU_OP2_mux_0,
                ALU_OP2_mux_1,

                reg_wr_en_0,
                reg_wr_en_1,
                reg_wr_en_2,

                mem_wr_en_0,
                mem_wr_en_1,
                mem_wr_en_2,

                branch_taken,
                if_clear,
                if_en,
                id_clear,
                PC_en,
                // branch,//;
    output
    wire [4:0]  rs1_addr_0,
                rs1_addr_1,

                rs2_addr_0,
                rs2_addr_1,

                rd_addr_0,//;
                rd_addr_1,
                rd_addr_2,
                rd_addr_3,

    output wire mem_read_0,
                mem_read_1,
                load_hazard,

    output wire [6:0]  opcode_0,
                       opcode_1,

    output wire [2:0]  funct3_0,
                       funct3_1,
    output wire [6:0]  funct7,
    
    output wire [2:0]  mem_control_0,
                       mem_control_1,
                       mem_control_2,

    output wire [1:0]  reg_data_mux_0,
                       reg_data_mux_1,
                       reg_data_mux_2,
                       reg_data_mux_3,
    output wire [3:0]  ALU_OP_0,
                       ALU_OP_1,   

    wire [1:0]         fwd_mux_2_ctrl,
                       fwd_mux_1_ctrl
);
//  wire JB_wire;

    assign PC_mux = jump_1 | (branch_1 & branch_taken );
    assign if_en = ~load_hazard;
    assign if_clear = PC_mux; 
    assign PC_en = if_en;
    assign id_clear = load_hazard | PC_mux;
/* Instruction fetch */
    PC_counter    PC (
                    .clk(clk),
                    .rst_n(rst_n),
                    .PC_en(PC_en),
                    .PC_in(ALU_result_0),
                    .input_sel(PC_mux),
                    .PC(instr_mem_addr_0),
                    .PC_next(PC_next_0)
                    );

    instr_mem    IM (
                    // .rst_n(rst_n),
                    .instr_addr(instr_mem_addr_0),
                    .instr_out(instr_0)
                    );


    IF_reg      IFR (//Input
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear(if_clear),
                    .wr_en(if_en),
                    .PC_next_in(PC_next_0),
                    .instr_in(instr_0),    
                    .instr_addr_in(instr_mem_addr_0),
                    //Output
                    .PC_next_out(PC_next_1),
                    .instr_out(instr_1),
                    .instr_addr_out(instr_mem_addr_1)
                    );
/* Instruction Decode*/
    inst_decoder ID (//Input
                    .instr(instr_1),
                    //Ouput
                    .rs1(rs1_addr_0),
                    .rs2(rs2_addr_0),
                    .rd(rd_addr_0),
                    .opcode(opcode_0),
                    .funct3(funct3_0),
                    .funct7(funct7),
                    .immediate(immediate_0)
                    );
    reg_file     RF (//input
                    .clk(clk),
                    .rst_n(rst_n),
                    .rs1_addr(rs1_addr_0),
                    .rs2_addr(rs2_addr_0),
                    .rd_addr(rd_addr_3),
                    .data_in(reg_data_in),
                    //Output
                    .wr_en(reg_wr_en_3),
                    .rs1_out(rs1_out_0),
                    .rs2_out(rs2_out_0)
                    );
   

    controller   CU (//Input
                    .clk(clk),
                    .rst_n(rst_n),
                    .opcode(opcode_0),
                    .funct3(funct3_0),
                    .funct7(funct7),
                    //Output
                    .jump(jump_0),
                    .branch(branch_0),
                    .ALU_OP1_mux(ALU_OP1_mux_0),
                    .ALU_OP2_mux(ALU_OP2_mux_0),
                    .ALU_OP(ALU_OP_0),
                    .reg_data_mux(reg_data_mux_0),
                    .reg_wr_en(reg_wr_en_0),
                    .mem_wr_en(mem_wr_en_0),
                    .mem_control(mem_control_0),
                    .mem_read(mem_read_0)
                    // .branch(branch)
                    );
          
    ID_reg      IDR (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear(id_clear),
                    .wr_en(1'b1),
                    .jump_in(jump_0),
                    .branch_in(branch_0),
                    .mem_read_in(mem_read_0),
                    .ALU_OP1_mux_in(ALU_OP1_mux_0),
                    .ALU_OP2_mux_in(ALU_OP2_mux_0),
                    .ALU_OP_in(ALU_OP_0),
                    .reg_data_mux_in(reg_data_mux_0),
                    .reg_wr_en_in(reg_wr_en_0),
                    .mem_wr_en_in(mem_wr_en_0),
                    .mem_control_in(mem_control_0),
                    .PC_next_in(PC_next_1),
                    .instr_addr_in(instr_mem_addr_1),
                    .rs1_in(rs1_out_0),
                    .rs2_in(rs2_out_0),
                    .immediate_in(immediate_0),
                    .reg_wr_addr_in(rd_addr_0),
                    .rs1_addr_in(rs1_addr_0),
                    .rs2_addr_in(rs2_addr_0),
                    .OPCODE_in(opcode_0),
                    .funct3_in(funct3_0),

                    //Output
                    .jump_out(jump_1),
                    .branch_out(branch_1),
                    .mem_read_out(mem_read_1),
                    .ALU_OP1_mux_out(ALU_OP1_mux_1),
                    .ALU_OP2_mux_out(ALU_OP2_mux_1),
                    .ALU_OP_out(ALU_OP_1),
                    .reg_data_mux_out(reg_data_mux_1),
                    .reg_wr_en_out(reg_wr_en_1),
                    .mem_wr_en_out(mem_wr_en_1),
                    .mem_control_out(mem_control_1),
                    .PC_next_out(PC_next_2),
                    .instr_addr_out(instr_mem_addr_2),
                    .rs1_out(rs1_out_1),
                    .rs2_out(rs2_out_1),
                    .immediate_out(immediate_1),
                    .reg_wr_addr_out(rd_addr_1),
                    .rs1_addr_out(rs1_addr_1),
                    .rs2_addr_out(rs2_addr_1),
                    .OPCODE_out(opcode_1),
                    .funct3_out(funct3_1)
                     ); 

/* Execution */
  
    MUX_3_1      M4 (
                    .I1(rs1_out_1), //default
                    .I2(ALU_result_1),//stage 4 fwd
                    .I3(reg_data_in), //stage 5 fwd
                    .S(fwd_mux_1_ctrl),
                    .out(rs1_w_fwd)
                    );

    MUX_3_1      M5 (
                    .I1(rs2_out_1),//default
                    .I2(ALU_result_1),//stage 4 fwd
                    .I3(reg_data_in),//stage 5 fwd
                    .S(fwd_mux_2_ctrl),
                    .out(rs2_w_fwd_0)
                    );


    MUX_2_1      M1 (
                    .I1(rs1_w_fwd),
                    .I2(instr_mem_addr_2),
                    .S(ALU_OP1_mux_1),
                    .out(ALU_OP1)
                    );

    MUX_2_1      M2 (
                    .I1(immediate_1),
                    .I2(rs2_w_fwd_0),
                    .S(ALU_OP2_mux_1),
                    .out(ALU_OP2)
                    );

    ALU          A1 (
                    .op_1(ALU_OP1),
                    .op_2(ALU_OP2),
                    .alu_op(ALU_OP_1),
                    .alu_out(ALU_result_0)
                    );

    fwd_unit     FU (
                    .rs1_addr(rs1_addr_1),
                    .rs2_addr(rs2_addr_1),
                    .rd_addr_stg_4(rd_addr_2),
                    .rd_addr_stg_5(rd_addr_3),
                    .rw_stg_4(reg_wr_en_2),
                    .rw_stg_5(reg_wr_en_3),
                    //Output
                    .fwd_mux_1(fwd_mux_1_ctrl),
                    .fwd_mux_2(fwd_mux_2_ctrl)
                    );

    hazard_unit  HU (
                    .reg_wr_addr(rd_addr_1),
                    .rs1_addr(rs1_addr_0),
                    .rs2_addr(rs2_addr_0),
                    .mem_rd(mem_read_1),
                    .load_hazard(load_hazard)
                    );


    EX_reg      EXR (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear(1'b0),
                    .wr_en(1'b1),
                    .reg_data_mux_in(reg_data_mux_1),
                    .reg_wr_en_in(reg_wr_en_1), 
                    .mem_wr_en_in(mem_wr_en_1),
                    .mem_control_in(mem_control_1),
                    .PC_next_in(PC_next_2),
                    .ALU_result_in(ALU_result_0),
                    .rs_OP2_in(rs2_w_fwd_0),
                    .reg_wr_addr_in(rd_addr_1),
                    //Output
                    .reg_data_mux_out(reg_data_mux_2),
                    .reg_wr_en_out(reg_wr_en_2), 
                    .mem_wr_en_out(mem_wr_en_2),
                    .mem_control_out(mem_control_2),
                    .PC_next_out(PC_next_3),
                    .ALU_result_out(ALU_result_1),
                    .rs_OP2_out(rs2_w_fwd_1),
                    .reg_wr_addr_out(rd_addr_2)
                    );


    branch_comp  BC (
                    .branch_OP1(rs1_w_fwd),
                    .branch_OP2(rs2_w_fwd_0),
                    .branch_OPCODE(funct3_1),
                    .branch_taken(branch_taken)
    );
 
/* Write Back */

    data_mem_w_ctrl Mem (
                    .clk(clk),
                    .mem_control(mem_control_2),
                    .mem_wr_en(mem_wr_en_2),
                    .mem_addr(ALU_result_1),
                    .mem_data_in(rs2_w_fwd_1),
                    //Output
                    .mem_data_out(mem_data_out_0)
                    );                      
    
    WB_reg      WBR (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear(1'b0),
                    .wr_en(1'b1),
                    .reg_data_mux_in(reg_data_mux_2),
                    .reg_wr_en_in(reg_wr_en_2), 
                    .PC_next_in(PC_next_3),
                    .ALU_result_in(ALU_result_1),
                    .reg_wr_addr_in(rd_addr_2),
                    .mem_data_read_in(mem_data_out_0),
                    //Ouput
                    .reg_data_mux_out(reg_data_mux_3),
                    .reg_wr_en_out(reg_wr_en_3), 
                    .PC_next_out(PC_next_4),
                    .ALU_result_out(ALU_result_2),
                    .reg_wr_addr_out(rd_addr_3),
                    .mem_data_read_out(mem_data_out_1)
                    );

    MUX_3_1      M3 (
                    .I1(mem_data_out_1),
                    .I2(ALU_result_2),
                    .I3(PC_next_4),
                    .S(reg_data_mux_3),
                    //Output
                    .out(reg_data_in)
                    );
endmodule


module pipeline_tb();
reg clk, rst_n;

RiscV_pipeline DUT (.clk(clk),
                    .rst_n(rst_n)
        //   .instr(output_data[159:128]),
        //   .immediate(output_data[127:96]),
        //   .reg_data_in(output_data[95:64]),
        //   .instr_mem_addr(output_data[63:32]),
        //   .ALU_result(output_data[31:0])
);
        //   .PC_next(output_data[63:32]);
    reg [1023:0] test_data[79:0];
    wire [1023:0] data_out;
    reg [1023:0]current_data;// reg [7:0] addr;
    reg incorect;

assign data_out = {DUT.RF.regfile[0],     DUT.RF.regfile[1],
                   DUT.RF.regfile[2],     DUT.RF.regfile[3],
                   DUT.RF.regfile[4],     DUT.RF.regfile[5],
                   DUT.RF.regfile[6],     DUT.RF.regfile[7],
                   DUT.RF.regfile[8],     DUT.RF.regfile[9],
                   DUT.RF.regfile[10],     DUT.RF.regfile[11],
                   DUT.RF.regfile[12],     DUT.RF.regfile[13],
                   DUT.RF.regfile[14],     DUT.RF.regfile[15],
                   DUT.RF.regfile[16],     DUT.RF.regfile[17],
                   DUT.RF.regfile[18],     DUT.RF.regfile[19],
                   DUT.RF.regfile[20],     DUT.RF.regfile[21],
                   DUT.RF.regfile[22],     DUT.RF.regfile[23],
                   DUT.RF.regfile[24],     DUT.RF.regfile[25],
                   DUT.RF.regfile[26],     DUT.RF.regfile[27],
                   DUT.RF.regfile[28],     DUT.RF.regfile[29],
                   DUT.RF.regfile[30],     DUT.RF.regfile[31]
                   };

always #5 clk=~clk;
	integer addr;
initial begin
    clk=1;
    rst_n = 0;
    incorect = 0;
    #10
    rst_n = 1;
    addr =-1;
    $display("signal %b ", DUT.jump_0);
end

initial begin: get_test_cases
		$readmemh("reg_dbg.mem",test_data);
    end

    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            addr = 0;
        else 
       begin
            addr = addr+1;
        end
    end

    always @(data_out) begin
        #1
            current_data = test_data[addr];
            if (data_out!=current_data)
                begin
                    incorect = 1; 
                    $display(" INCORRECT OUPUT !!! - %t:",$time);
                end
            else
                incorect = 0;
    end     
endmodule