module instr_mem_old (
    input  wire rst_n,
    input  wire [31:0] instr_addr,
    output wire [31:0] instr_out
);
    reg [31:0] intruction_memory [255:0];
    assign instr_out = intruction_memory[instr_addr];
//for testing only 
    always @(negedge rst_n) begin
        intruction_memory[0] = 32'h04000513;
        intruction_memory[1] = 32'h00f00593;
        intruction_memory[2] = 32'h00b506b3;
        intruction_memory[3] = 32'h40a58733;
        intruction_memory[4] = 32'h00e6a7b3;
        intruction_memory[5] = 32'h00d627b3;
        intruction_memory[6] = 32'h00b6a793;
        intruction_memory[7] = 32'h00373793;
        intruction_memory[8] = 32'hfffff7b7;
        intruction_memory[9] = 32'h0000d817;
    end
endmodule

module instr_mem #(parameter program = "program.mem")(
    input  wire [31:0] instr_addr,
    output wire [31:0] instr_out
);
    reg [7:0] intr_mem [255:0];//256 byte
    initial $readmemh(program, intr_mem);
    assign instr_out = {intr_mem[instr_addr+3],intr_mem[instr_addr+2],intr_mem[instr_addr+1],intr_mem[instr_addr]};

endmodule