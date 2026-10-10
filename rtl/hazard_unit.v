`timescale 1ns / 1ps

// Data-hazard handling: EX-stage operand forwarding and load-use stall.
//
// Forwarding priority is MEM over WB (the younger producer wins). A producer
// is only considered when it is a valid instruction that writes a register
// other than x0.
module hazard_unit (
    // ID stage (instruction being decoded)
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_uses_rs1,
    input  wire       id_uses_rs2,

    // EX stage
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire       ex_valid,
    input  wire       ex_mem_re,
    input  wire [4:0] ex_rd,
    input  wire       ex_reg_we,

    // MEM stage
    input  wire       mem_valid,
    input  wire [4:0] mem_rd,
    input  wire       mem_reg_we,

    // WB stage
    input  wire       wb_valid,
    input  wire [4:0] wb_rd,
    input  wire       wb_reg_we,

    output wire [1:0] fwd_a,      // 0: register file, 1: from MEM, 2: from WB
    output wire [1:0] fwd_b,
    output wire       load_use_stall
);

    wire mem_writes = mem_valid && mem_reg_we && (mem_rd != 5'd0);
    wire wb_writes  = wb_valid  && wb_reg_we  && (wb_rd  != 5'd0);

    assign fwd_a = (mem_writes && (mem_rd == ex_rs1)) ? 2'd1 :
                   (wb_writes  && (wb_rd  == ex_rs1)) ? 2'd2 : 2'd0;
    assign fwd_b = (mem_writes && (mem_rd == ex_rs2)) ? 2'd1 :
                   (wb_writes  && (wb_rd  == ex_rs2)) ? 2'd2 : 2'd0;

    // A load in EX produces its data only at the end of MEM, so a dependent
    // instruction in ID must wait one cycle and then take the WB forward.
    wire ex_load = ex_valid && ex_mem_re && ex_reg_we && (ex_rd != 5'd0);
    assign load_use_stall = ex_load &&
                            ((id_uses_rs1 && (id_rs1 == ex_rd)) ||
                             (id_uses_rs2 && (id_rs2 == ex_rd)));

endmodule
