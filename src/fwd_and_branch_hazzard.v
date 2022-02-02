module fwd_unit (
    input  [4:0] rs1_addr,
    input  [4:0] rs2_addr,

    input  [4:0] rd_addr_stg_4,
    input  [4:0] rd_addr_stg_5,
    input         rw_stg_4,
    input         rw_stg_5,

    output [1:0]  fwd_mux_1,
    output [1:0]  fwd_mux_2 
);

// assign fwd_mux_1 = rw_stg_4 ? (rs1_addr == rd_addr_stg_4) ? 2'b01 :  
//                    rw_stg_5 ? (rs1_addr == rd_addr_stg_5) ? 2'b10 : 2'b00 :2'b00:2'b00 ;

// assign fwd_mux_2 = rw_stg_4 ? (rs2_addr == rd_addr_stg_4) ? 2'b01 : 
//                    rw_stg_5 ? (rs2_addr == rd_addr_stg_5) ? 2'b10 : 2'b00 :2'b00:2'b00;


assign fwd_mux_1 = (rw_stg_4 && (rs1_addr == rd_addr_stg_4)) ? 2'b01 :  
                   (rw_stg_5 && (rs1_addr == rd_addr_stg_5)) ? 2'b10 : 
                   2'b00 ;


assign fwd_mux_2 = (rw_stg_4 && (rs2_addr == rd_addr_stg_4)) ? 2'b01 :  
                   (rw_stg_5 && (rs2_addr == rd_addr_stg_5)) ? 2'b10 : 
                   2'b00 ;

endmodule


module fwd_tb ();
reg [31:0] rs1, rs2,stg4,stg5;
reg rw1,rw2;
wire [1:0] out1, out2;
forwarding_unit DUT(
                    .rs1_addr(rs1),
                    .rs2_addr(rs2),
                    .rd_addr_stg_4(stg4),
                    .rd_addr_stg_5(stg5),
                    .rw_stg_4(rw1),
                    .rw_stg_5(rw2),
                    .fwd_mux_1(out1),
                    .fwd_mux_2(out2)
                    );
initial begin
    rs1 = 32'hdeadbeef;
    rs2 = 32'h0;
    #5
    rw1 = 1;
    rw2 = 1;
    stg5 = 32'hdeadbeef;
    stg4 = 32'h0;
    #5
    stg5 = 32'hdeadbe2f;
    stg4 = 32'hda2dbe2f;



end
endmodule

module hazard_unit (
    input  [4:0] reg_wr_addr,
    input  [4:0] rs1_addr,
    input  [4:0] rs2_addr,
    input         mem_rd,

    output wire   load_hazard      
);
    assign load_hazard = mem_rd &&((reg_wr_addr == rs1_addr) || (reg_wr_addr == rs2_addr)); 
endmodule