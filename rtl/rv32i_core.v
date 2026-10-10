`timescale 1ns / 1ps

// 5-stage in-order RV32I pipeline: IF -> ID -> EX -> MEM -> WB
//
// Memory interfaces (both are synchronous-read, so they map directly onto
// FPGA block RAM):
//
//   Instruction port: the core drives imem_addr/imem_en in IF; the memory
//   returns imem_rdata on the following cycle (that is, in ID). While
//   imem_en is low the memory must hold its previous output.
//
//   Data port: the core drives dbus_* in MEM; for a read (dbus_re) the
//   addressed device must return dbus_rdata on the following cycle (in WB).
//   dbus_addr is a byte address. dbus_wdata is already shifted onto the
//   correct byte lanes and dbus_wstrb marks which lanes to write.
//   Misaligned accesses are not supported (the low address bits select the
//   lane for byte/half accesses and are ignored for word accesses).
//
// Hazards:
//   * RAW hazards are resolved by forwarding from MEM and WB into EX.
//   * Load-use: one bubble, then the WB forward.
//   * Control: branches and jumps resolve in EX; a taken branch or jump
//     flushes the two younger instructions (2-cycle penalty). Not-taken
//     branches cost nothing (static not-taken prediction).
//
// The trace_* outputs report every retired instruction (one per cycle at
// most, in program order) and are meant for testbenches; leave them
// unconnected in a real design and synthesis will remove the logic.
module rv32i_core #(
    parameter [31:0] RESET_ADDR = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction memory port
    output wire [31:0] imem_addr,
    output wire        imem_en,
    input  wire [31:0] imem_rdata,

    // Data bus
    output wire [31:0] dbus_addr,
    output wire [31:0] dbus_wdata,
    output wire [3:0]  dbus_wstrb,
    output wire        dbus_we,
    output wire        dbus_re,
    input  wire [31:0] dbus_rdata,

    // Retirement trace (simulation / debug)
    output wire        trace_valid,
    output wire [31:0] trace_pc,
    output wire [31:0] trace_instr,
    output wire        trace_rd_we,
    output wire [4:0]  trace_rd,
    output wire [31:0] trace_rd_data
);
`include "rv32i_defs.vh"

    // Signals that flow backwards through the pipeline.
    wire        load_use_stall;
    wire        ex_redirect;
    wire [31:0] ex_target;
    wire        wb_reg_we_eff;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    // =======================================================================
    // IF: program counter
    // =======================================================================
    reg  [31:0] if_pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            if_pc <= RESET_ADDR;
        else if (ex_redirect)
            if_pc <= ex_target;
        else if (!load_use_stall)
            if_pc <= if_pc + 32'd4;
    end

    // The memory registers the address; while stalled it keeps its output so
    // the instruction in ID stays put.
    assign imem_addr = if_pc;
    assign imem_en   = !load_use_stall;

    // =======================================================================
    // IF/ID register. The instruction word itself is the memory's output
    // register, so only the PC and a valid bit are stored here.
    // =======================================================================
    reg         id_valid;
    reg  [31:0] id_pc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_valid <= 1'b0;
            id_pc    <= 32'd0;
        end else if (ex_redirect) begin
            id_valid <= 1'b0;
        end else if (!load_use_stall) begin
            id_valid <= 1'b1;
            id_pc    <= if_pc;
        end
    end

    // =======================================================================
    // ID: decode and register read
    // =======================================================================
    wire [31:0] id_instr = id_valid ? imem_rdata : INSTR_NOP;

    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [2:0]  id_funct3;
    wire [31:0] id_imm;
    wire        id_uses_rs1, id_uses_rs2, id_reg_we;
    wire [3:0]  id_alu_op;
    wire [1:0]  id_opa_sel;
    wire        id_opb_imm, id_is_branch, id_is_jal, id_is_jalr;
    wire        id_mem_re, id_mem_we, id_illegal;

    decoder u_decoder (
        .instr     (id_instr),
        .rs1       (id_rs1),
        .rs2       (id_rs2),
        .rd        (id_rd),
        .funct3    (id_funct3),
        .imm       (id_imm),
        .uses_rs1  (id_uses_rs1),
        .uses_rs2  (id_uses_rs2),
        .reg_we    (id_reg_we),
        .alu_op    (id_alu_op),
        .opa_sel   (id_opa_sel),
        .opb_imm   (id_opb_imm),
        .is_branch (id_is_branch),
        .is_jal    (id_is_jal),
        .is_jalr   (id_is_jalr),
        .mem_re    (id_mem_re),
        .mem_we    (id_mem_we),
        .illegal   (id_illegal)
    );

    wire [31:0] id_rs1_data, id_rs2_data;

    reg_file u_reg_file (
        .clk      (clk),
        .rs1_addr (id_rs1),
        .rs2_addr (id_rs2),
        .rs1_data (id_rs1_data),
        .rs2_data (id_rs2_data),
        .wr_en    (wb_reg_we_eff),
        .rd_addr  (wb_rd),
        .rd_data  (wb_data)
    );

    // =======================================================================
    // ID/EX register. A flush or a load-use stall inserts a bubble.
    // =======================================================================
    reg         ex_valid;
    reg  [31:0] ex_pc, ex_instr;
    reg  [31:0] ex_rs1_data, ex_rs2_data, ex_imm;
    reg  [4:0]  ex_rs1, ex_rs2, ex_rd;
    reg  [2:0]  ex_funct3;
    reg         ex_reg_we, ex_opb_imm, ex_is_branch, ex_is_jal, ex_is_jalr;
    reg         ex_mem_re, ex_mem_we;
    reg  [3:0]  ex_alu_op;
    reg  [1:0]  ex_opa_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_valid <= 1'b0;
        end else if (ex_redirect || load_use_stall) begin
            ex_valid <= 1'b0;
        end else begin
            ex_valid <= id_valid;
        end
    end

    // Datapath fields need no reset: every consumer is qualified by ex_valid.
    always @(posedge clk) begin
        ex_pc        <= id_pc;
        ex_instr     <= id_instr;
        ex_rs1_data  <= id_rs1_data;
        ex_rs2_data  <= id_rs2_data;
        ex_imm       <= id_imm;
        ex_rs1       <= id_uses_rs1 ? id_rs1 : 5'd0;
        ex_rs2       <= id_uses_rs2 ? id_rs2 : 5'd0;
        ex_rd        <= id_rd;
        ex_funct3    <= id_funct3;
        ex_reg_we    <= id_reg_we;
        ex_opb_imm   <= id_opb_imm;
        ex_is_branch <= id_is_branch;
        ex_is_jal    <= id_is_jal;
        ex_is_jalr   <= id_is_jalr;
        ex_mem_re    <= id_mem_re;
        ex_mem_we    <= id_mem_we;
        ex_alu_op    <= id_alu_op;
        ex_opa_sel   <= id_opa_sel;
    end

    // =======================================================================
    // EX: forwarding, ALU, branch resolution
    // =======================================================================
    reg         mem_valid;
    reg  [4:0]  mem_rd;
    reg         mem_reg_we;
    reg  [31:0] mem_result;
    reg         wb_valid;

    wire [1:0]  fwd_a, fwd_b;

    hazard_unit u_hazard_unit (
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_uses_rs1    (id_uses_rs1),
        .id_uses_rs2    (id_uses_rs2),
        .ex_rs1         (ex_rs1),
        .ex_rs2         (ex_rs2),
        .ex_valid       (ex_valid),
        .ex_mem_re      (ex_mem_re),
        .ex_rd          (ex_rd),
        .ex_reg_we      (ex_reg_we),
        .mem_valid      (mem_valid),
        .mem_rd         (mem_rd),
        .mem_reg_we     (mem_reg_we),
        .wb_valid       (wb_valid),
        .wb_rd          (wb_rd),
        .wb_reg_we      (wb_reg_we_eff),
        .fwd_a          (fwd_a),
        .fwd_b          (fwd_b),
        .load_use_stall (load_use_stall)
    );

    wire [31:0] ex_rs1_fwd = (fwd_a == 2'd1) ? mem_result :
                             (fwd_a == 2'd2) ? wb_data    : ex_rs1_data;
    wire [31:0] ex_rs2_fwd = (fwd_b == 2'd1) ? mem_result :
                             (fwd_b == 2'd2) ? wb_data    : ex_rs2_data;

    wire [31:0] ex_op_a = (ex_opa_sel == OPA_PC)   ? ex_pc :
                          (ex_opa_sel == OPA_ZERO) ? 32'd0 : ex_rs1_fwd;
    wire [31:0] ex_op_b = ex_opb_imm ? ex_imm : ex_rs2_fwd;
    wire [31:0] ex_alu_result;

    alu u_alu (
        .op_a   (ex_op_a),
        .op_b   (ex_op_b),
        .alu_op (ex_alu_op),
        .result (ex_alu_result)
    );

    wire ex_branch_taken;

    branch_unit u_branch_unit (
        .rs1    (ex_rs1_fwd),
        .rs2    (ex_rs2_fwd),
        .funct3 (ex_funct3),
        .taken  (ex_branch_taken)
    );

    // Dedicated target adder so the ALU stays free for the link value path.
    wire [31:0] ex_pc_plus4  = ex_pc + 32'd4;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] ex_jalr_sum  = ex_rs1_fwd + ex_imm;     // bit 0 is dropped
    /* verilator lint_on UNUSEDSIGNAL */
    assign ex_target   = ex_is_jalr ? {ex_jalr_sum[31:1], 1'b0} : (ex_pc + ex_imm);
    assign ex_redirect = ex_valid &&
                         (ex_is_jal || ex_is_jalr || (ex_is_branch && ex_branch_taken));

    wire [31:0] ex_result = (ex_is_jal || ex_is_jalr) ? ex_pc_plus4 : ex_alu_result;

    // =======================================================================
    // EX/MEM register
    // =======================================================================
    reg  [31:0] mem_pc, mem_instr, mem_store_data;
    reg  [2:0]  mem_funct3;
    reg         mem_mem_re, mem_mem_we;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mem_valid <= 1'b0;
        else
            mem_valid <= ex_valid;
    end

    always @(posedge clk) begin
        mem_pc         <= ex_pc;
        mem_instr      <= ex_instr;
        mem_result     <= ex_result;
        mem_store_data <= ex_rs2_fwd;
        mem_rd         <= ex_rd;
        mem_reg_we     <= ex_reg_we;
        mem_funct3     <= ex_funct3;
        mem_mem_re     <= ex_mem_re;
        mem_mem_we     <= ex_mem_we;
    end

    // =======================================================================
    // MEM: drive the data bus
    // =======================================================================
    wire [1:0] mem_byte = mem_result[1:0];

    reg  [3:0]  mem_wstrb;
    reg  [31:0] mem_wdata;

    always @(*) begin
        case (mem_funct3[1:0])
            2'b00: begin // SB
                mem_wstrb = 4'b0001 << mem_byte;
                mem_wdata = {4{mem_store_data[7:0]}};
            end
            2'b01: begin // SH
                mem_wstrb = mem_byte[1] ? 4'b1100 : 4'b0011;
                mem_wdata = {2{mem_store_data[15:0]}};
            end
            default: begin // SW
                mem_wstrb = 4'b1111;
                mem_wdata = mem_store_data;
            end
        endcase
    end

    assign dbus_addr  = mem_result;
    assign dbus_wdata = mem_wdata;
    assign dbus_wstrb = mem_wstrb;
    assign dbus_we    = mem_valid && mem_mem_we;
    assign dbus_re    = mem_valid && mem_mem_re;

    // =======================================================================
    // MEM/WB register
    // =======================================================================
    reg  [31:0] wb_pc, wb_instr, wb_result;
    reg  [2:0]  wb_funct3;
    reg  [4:0]  wb_rd_q;
    reg         wb_reg_we, wb_mem_re;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            wb_valid <= 1'b0;
        else
            wb_valid <= mem_valid;
    end

    always @(posedge clk) begin
        wb_pc     <= mem_pc;
        wb_instr  <= mem_instr;
        wb_result <= mem_result;
        wb_rd_q   <= mem_rd;
        wb_reg_we <= mem_reg_we;
        wb_funct3 <= mem_funct3;
        wb_mem_re <= mem_mem_re;
    end

    // =======================================================================
    // WB: load alignment / extension and register write-back
    // =======================================================================
    wire [1:0]  wb_byte  = wb_result[1:0];
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] wb_shift = dbus_rdata >> {wb_byte, 3'b000};
    /* verilator lint_on UNUSEDSIGNAL */
    reg  [31:0] wb_load_data;

    always @(*) begin
        case (wb_funct3)
            MEM_B:   wb_load_data = {{24{wb_shift[7]}},  wb_shift[7:0]};
            MEM_H:   wb_load_data = {{16{wb_shift[15]}}, wb_shift[15:0]};
            MEM_BU:  wb_load_data = {24'd0, wb_shift[7:0]};
            MEM_HU:  wb_load_data = {16'd0, wb_shift[15:0]};
            default: wb_load_data = dbus_rdata; // LW
        endcase
    end

    assign wb_rd         = wb_rd_q;
    assign wb_reg_we_eff = wb_valid && wb_reg_we;
    assign wb_data       = wb_mem_re ? wb_load_data : wb_result;

    // =======================================================================
    // Retirement trace
    // =======================================================================
    assign trace_valid   = wb_valid;
    assign trace_pc      = wb_pc;
    assign trace_instr   = wb_instr;
    assign trace_rd_we   = wb_reg_we_eff && (wb_rd != 5'd0);
    assign trace_rd      = wb_rd;
    assign trace_rd_data = wb_data;

    // id_illegal is decoded for a future trap unit; unused for now.
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_illegal = id_illegal;
    /* verilator lint_on UNUSEDSIGNAL */

endmodule
