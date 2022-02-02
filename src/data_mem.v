module data_mem (
    input   wire          clk,
    input   wire [31:0]   mem_addr,
    input   wire          mem_wr_en,
    input   wire [31:0]   mem_data_in,
    output  wire  [31:0]   mem_data_out
);

    reg    [31:0] data_memory [2048:0];
    assign mem_data_out = data_memory[mem_addr];

    always @(posedge clk)
    begin
        if(mem_wr_en)
             data_memory[mem_addr] <= mem_data_in;
    end 
endmodule

module data_mem_w_ctrl (
    input   wire          clk,
    input   wire [31:0]   mem_addr,
    input   wire [2:0]    mem_control,
    input   wire          mem_wr_en,
    input   wire [31:0]   mem_data_in,
    output  wire [31:0]   mem_data_out
);
 
    reg    [31:0] data_memory [2047:0];
    assign mem_data_out = (mem_control == 3'b010) ? data_memory[mem_addr]:
                          (mem_control == 3'b001) ? {{16{data_memory[mem_addr][15]}},data_memory[mem_addr][15:0]}:
                          (mem_control == 3'b000) ? {{24{data_memory[mem_addr][7]}},data_memory[mem_addr][7:0]}:
                          (mem_control == 3'b101) ? {{16{1'b0}},data_memory[mem_addr][15:0]}:
                          (mem_control == 3'b100) ? {{24{1'b0}},data_memory[mem_addr][7:0]}:data_memory[mem_addr];
    // integer i;
    // initial begin
    //     for (i = 0; i < 2048; i = i + 1) 
    //       data_memory [i] = 32'h0; 
    // end

    always @(posedge clk)
    begin
        if(mem_wr_en)
            case(mem_control[1:0])
                2'b10: data_memory[mem_addr] <= mem_data_in;
                2'b01: data_memory[mem_addr][15:0] <= {16'h0,mem_data_in[15:0]};
                2'b00: data_memory[mem_addr] <= {7'h0,mem_data_in[7:0]};
            default : data_memory[mem_addr] <= mem_data_in;
            endcase
    end 
endmodule

module data_mem_tb();
    reg         clk;
    reg         WE;
    reg  [31:0] addr;
    reg  [31:0] data_in;
    reg  [2:0]  control;
    wire [31:0] data_out;

    data_mem_w_ctrl DUT(.clk(clk),
                            .mem_addr(addr),
                            .mem_control(control),
                            .mem_wr_en(WE),
                            .mem_data_in(data_in),
                            .mem_data_out(data_out)
                            );

    always #5 clk = ~clk;

    initial begin
        clk = 1;
        WE = 1;
        addr= 32'h0;
        data_in = 32'hffffffff;
        #20
        WE = 0;
        data_in = 32'h0;
        control = 3'b001;
        #20
        control = 3'b010;
        #20
        control = 3'b100;
        #20
        control = 3'b101;

         
    end

endmodule