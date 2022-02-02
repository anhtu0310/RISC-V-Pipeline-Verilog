module main(
    input wire clk,
    input wire rst_n,
// );
    output
    wire [31:0] instr,
                rs1_out,
                rs2_out,
                PC_next,
                ALU_OP1,
                ALU_OP2,
                immediate,
                ALU_result,
                reg_data_in,
                mem_data_out,
                instr_mem_addr,//;
    output
    wire        PC_mux,
                branch,
                jump,
                // PC_mux_cu,/
                ALU_OP1_mux,
                ALU_OP2_mux,
                reg_wr_en,
                mem_wr_en,
                branch_taken,
                // branch,//;
    output
    wire [4:0]  rs1_addr,
                rs2_addr,
                rd_addr,//;

    output wire [6:0]  opcode,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,
    
    output wire [2:0]  mem_control,
    output wire [1:0]  reg_data_mux,
    output wire [3:0]  ALU_OP,   

    output wire [2:0]  branch_OPCODE
    // wire [2:0]  mem_control;
);

    wire JB_wire;

    assign PC_mux = jump | JB_wire ;
    assign JB_wire = branch & branch_taken ;

    PC_counter    PC (
                    .clk(clk),
                    .rst_n(rst_n),
                    .PC_in(ALU_result),
                    .input_sel(PC_mux),
                    .PC(instr_mem_addr),
                    .PC_next(PC_next)
                    );

    instr_mem    IM (
                    // .rst_n(rst_n),
                    .instr_addr(instr_mem_addr),
                    .instr_out(instr)
                    );

    inst_decoder ID (
                    .instr(instr),
                    .rs1(rs1_addr),
                    .rs2(rs2_addr),
                    .rd(rd_addr),
                    .opcode(opcode),
                    .funct3(funct3),
                    .funct7(funct7),
                    .immediate(immediate)
                    );

    reg_file     RF (
                    .clk(clk),
                    .rst_n(rst_n),
                    .rs1_addr(rs1_addr),
                    .rs2_addr(rs2_addr),
                    .rd_addr(rd_addr),
                    .wr_en(reg_wr_en),
                    .data_in(reg_data_in),
                    .rs1_out(rs1_out),
                    .rs2_out(rs2_out)
                    );
   
    MUX_2_1      M1 (
                    .I1(rs1_out),
                    .I2(instr_mem_addr),
                    .S(ALU_OP1_mux),
                    .out(ALU_OP1)
                    );

    MUX_2_1      M2 (
                    .I1(immediate),
                    .I2(rs2_out),
                    .S(ALU_OP2_mux),
                    .out(ALU_OP2)
                    );

    ALU          A1 (
                    .op_1(ALU_OP1),
                    .op_2(ALU_OP2),
                    .alu_op(ALU_OP),
                    .alu_out(ALU_result)
                    );

    data_mem_w_ctrl Mem (
                    .clk(clk),
                    .mem_control(mem_control),
                    .mem_wr_en(mem_wr_en),
                    .mem_addr(ALU_result),
                    .mem_data_in(rs2_out),
                    .mem_data_out(mem_data_out)
                    );                      
        
    MUX_3_1      M3 (
                    .I1(mem_data_out),
                    .I2(ALU_result),
                    .I3(PC_next),
                    .S(reg_data_mux),
                    .out(reg_data_in)
                    );
    
    branch_comp  BC (
                    .branch_OP1(rs1_out),
                    .branch_OP2(rs2_out),
                    .branch_OPCODE(funct3),
                    .branch_taken(branch_taken)
    );
 
    controller   CU (
                    .clk(clk),
                    .rst_n(rst_n),
                    .opcode(opcode),
                    .funct3(funct3),
                    .funct7(funct7),
                    .jump(jump),
                    .branch(branch),
                    .ALU_OP1_mux(ALU_OP1_mux),
                    .ALU_OP2_mux(ALU_OP2_mux),
                    .ALU_OP(ALU_OP),
                    .reg_data_mux(reg_data_mux),
                    .reg_wr_en(reg_wr_en),
                    .mem_wr_en(mem_wr_en),
                    .mem_control(mem_control)
                    // .branch(branch)
                    );
    // or            O1 ()

endmodule



module main_tb();
reg clk, rst_n, incorect;
reg [159:0] test_data [39:0];
wire [159:0] output_data;
reg [159:0] current_data;

main DUT (.clk(clk),
          .rst_n(rst_n),
          .instr(output_data[159:128]),
          .immediate(output_data[127:96]),
          .reg_data_in(output_data[95:64]),
          .instr_mem_addr(output_data[63:32]),
          .ALU_result(output_data[31:0])
);
        //   .PC_next(output_data[63:32]);
always #5 clk=~clk;
initial begin
    clk = 1;
    rst_n = 0;
    #20
    rst_n = 1;
end
	initial begin: get_test_cases
		$readmemh("test_data.mem",test_data);
    end
	integer addr;
    always @(posedge clk or negedge rst_n) begin
        if(~rst_n)
            addr = 0;
        else 
       begin
            addr = addr+1;
        end
    end

    always @(output_data) begin
        #1
            current_data = test_data[addr];
            if (output_data!=current_data)
                begin
                    incorect = 1; 
                    $display(" INCORRECT OUPUT !!! - %t:",$time);
                end
            else
                incorect = 0;
    end     
endmodule