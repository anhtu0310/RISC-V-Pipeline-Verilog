`timescale 1ns / 1ps

// 32 x 32-bit register file, two asynchronous read ports, one write port.
//
// * x0 is hard-wired to zero (never written, always reads 0).
// * Write-first bypass: a register written by WB in this cycle is seen by the
//   ID-stage read in the same cycle, so no WB->ID forwarding path is needed.
// * No reset on the storage, so FPGA tools can map it to distributed RAM; the
//   initial block gives a defined power-up value (supported by FPGA bitstreams).
module reg_file (
    input  wire        clk,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs1_data,
    output wire [31:0] rs2_data,
    input  wire        wr_en,
    input  wire [4:0]  rd_addr,
    input  wire [31:0] rd_data
);

    reg [31:0] regs [1:31];

    integer i;
    initial begin
        for (i = 1; i < 32; i = i + 1)
            regs[i] = 32'd0;
    end

    wire wr_valid = wr_en && (rd_addr != 5'd0);

    always @(posedge clk) begin
        if (wr_valid)
            regs[rd_addr] <= rd_data;
    end

    assign rs1_data = (rs1_addr == 5'd0)                    ? 32'd0   :
                      (wr_valid && (rs1_addr == rd_addr))   ? rd_data :
                                                              regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0)                    ? 32'd0   :
                      (wr_valid && (rs2_addr == rd_addr))   ? rd_data :
                                                              regs[rs2_addr];

endmodule
