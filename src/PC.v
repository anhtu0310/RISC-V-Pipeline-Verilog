module PC_reg(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] PC_next,
    
    output reg  [31:0] PC
);

    always @(posedge clk or negedge rst_n) 
    begin
        if (~ rst_n)
            PC <= 32'h0;
        else 
            PC <= PC_next;
    end
    
endmodule

module Counter_add_4 (
    input  wire [31:0]PC_in,
    output wire [31:0]PC_out
);
    assign PC_out = PC_in + 4;
endmodule

module PC_counter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        PC_en,
    input  wire [31:0] PC_in,
    input  wire        input_sel,   
    
    output reg  [31:0] PC,
    output wire [31:0] PC_next
);
    // wire        PC_next;
    // reg  [31:0] PC_next;
    assign PC_next = PC + 4;

    // always @(PC or input_sel) begin
    //     PC_next = PC + 4; 
    // end

    always @(posedge clk or negedge rst_n) 
    begin
        if (~ rst_n)
            PC <= 32'd4294967292;//hFFFFFFB;
        else if(PC_en)
            PC <= input_sel ? PC_in :PC_next ;
    end

endmodule

module PC_tb ();
    reg         clk;
    reg         sel;
    reg         rst_n;
    wire [31:0] out; 
    PC_counter DUT (.clk(clk),
                    .rst_n(rst_n),
                    .input_sel(sel),
                    .PC(out)
                    );
    always #5 clk=~clk;

    initial begin
        clk = 0;
        sel = 0;
        rst_n = 0;
        # 10 
        rst_n = 1;
        #100 
        sel = 1;
    end
endmodule