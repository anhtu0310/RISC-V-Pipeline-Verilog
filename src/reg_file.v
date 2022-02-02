
module reg_file (
  input   wire          clk,
  input   wire          rst_n,
  input   wire [4:0]    rs1_addr,
  input   wire [4:0]    rs2_addr,
  input   wire [4:0]    rd_addr,
  input   wire          wr_en,
  input   wire [31:0]   data_in,
    
  output  wire [31:0]   rs1_out,
  output  wire [31:0]   rs2_out
);  
  reg [31:0] regfile [31:0];	
//   regfile[0] = 0;
  assign rs1_out = rs1_addr ? ((rs1_addr == rd_addr) && wr_en) ? data_in :regfile[rs1_addr] : 32'h0;
  assign rs2_out = rs2_addr ? ((rs2_addr == rd_addr) && wr_en) ? data_in :regfile[rs2_addr] : 32'h0;

// always @(negedge clk) begin
//       rs1_out = rs1_addr ? regfile[rs1_addr] : 32'h0;
//       rs2_out = rs2_addr ? regfile[rs2_addr] : 32'h0;

// end
  integer i;

  always @(posedge clk or negedge rst_n)
    begin
      if(~rst_n)
        for (i = 0; i < 32; i = i + 1) 
          regfile [i] = 32'h0; 
      else
        if (wr_en)
            regfile[rd_addr] =  data_in;
    end

endmodule