`timescale 1ns / 1ps

// Instruction-level reference model of RV32I (simulation only).
//
// The testbench calls step() once for every instruction the RTL retires and
// compares the results. The model has its own copy of RAM and register file,
// so any pipeline bug (hazard, forwarding, flush, byte-lane) shows up as a
// mismatch at the first instruction it affects.
//
// Loads outside RAM (peripherals) are not modelled: the caller passes in the
// value the RTL loaded and the model adopts it, so tests that touch MMIO
// still check everything else.
module rv32i_ref_model #(
    parameter integer RAM_ADDR_WIDTH = 12,
    parameter [31:0]  RESET_ADDR     = 32'h0000_0000
) ();
`include "rv32i_defs.vh"

    localparam integer DEPTH     = 1 << RAM_ADDR_WIDTH;
    localparam [31:0]  RAM_BYTES = 32'd4 << RAM_ADDR_WIDTH;

    reg [31:0] mem  [0:DEPTH-1];
    reg [31:0] regs [0:31];
    reg [31:0] pc;

    integer i;
    task reset;
        begin
            pc = RESET_ADDR;
            for (i = 0; i < 32; i = i + 1)
                regs[i] = 32'd0;
        end
    endtask

    task clear_mem;
        begin
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] = 32'd0;
        end
    endtask

    function in_ram(input [31:0] addr);
        in_ram = (addr < RAM_BYTES);
    endfunction

    // Execute one instruction.
    //   mmio_load_data : value the RTL loaded, used only for non-RAM loads
    //   o_pc/o_instr   : address and encoding of the executed instruction
    //   o_rd_we/o_rd/o_rd_data : register write (o_rd_we = 0 for x0)
    //   o_mmio_load    : the instruction was a load from outside RAM
    task step(
        input  [31:0] mmio_load_data,
        output [31:0] o_pc,
        output [31:0] o_instr,
        output        o_rd_we,
        output [4:0]  o_rd,
        output [31:0] o_rd_data,
        output        o_mmio_load
    );
        reg [31:0] instr, rs1v, rs2v, imm_i, imm_s, imm_b, imm_u, imm_j;
        reg [31:0] next_pc, result, addr, word, shifted;
        reg [6:0]  opcode, funct7;
        reg [2:0]  funct3;
        reg [4:0]  rd;
        reg        we;
        begin
            instr  = in_ram(pc) ? mem[pc[RAM_ADDR_WIDTH+1:2]] : 32'd0;
            opcode = instr[6:0];
            funct3 = instr[14:12];
            funct7 = instr[31:25];
            rd     = instr[11:7];
            rs1v   = regs[instr[19:15]];
            rs2v   = regs[instr[24:20]];
            imm_i  = {{21{instr[31]}}, instr[30:20]};
            imm_s  = {{21{instr[31]}}, instr[30:25], instr[11:7]};
            imm_b  = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            imm_u  = {instr[31:12], 12'd0};
            imm_j  = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

            next_pc     = pc + 32'd4;
            result      = 32'd0;
            we          = 1'b0;
            o_mmio_load = 1'b0;

            case (opcode)
                OPC_LUI:   begin we = 1'b1; result = imm_u; end
                OPC_AUIPC: begin we = 1'b1; result = pc + imm_u; end
                OPC_JAL:   begin we = 1'b1; result = pc + 32'd4; next_pc = pc + imm_j; end
                OPC_JALR:  if (funct3 == 3'b000) begin
                               we = 1'b1; result = pc + 32'd4;
                               next_pc = (rs1v + imm_i) & ~32'd1;
                           end
                OPC_BRANCH: begin
                    case (funct3)
                        BR_EQ:  if (rs1v == rs2v)                   next_pc = pc + imm_b;
                        BR_NE:  if (rs1v != rs2v)                   next_pc = pc + imm_b;
                        BR_LT:  if ($signed(rs1v) <  $signed(rs2v)) next_pc = pc + imm_b;
                        BR_GE:  if ($signed(rs1v) >= $signed(rs2v)) next_pc = pc + imm_b;
                        BR_LTU: if (rs1v <  rs2v)                   next_pc = pc + imm_b;
                        BR_GEU: if (rs1v >= rs2v)                   next_pc = pc + imm_b;
                        default: ;
                    endcase
                end
                OPC_LOAD: if (funct3 != 3'b011 && funct3 < 3'b110) begin
                    we   = 1'b1;
                    addr = rs1v + imm_i;
                    if (in_ram(addr)) begin
                        word    = mem[addr[RAM_ADDR_WIDTH+1:2]];
                        shifted = word >> (8 * addr[1:0]);
                        case (funct3)
                            MEM_B:   result = {{24{shifted[7]}},  shifted[7:0]};
                            MEM_H:   result = {{16{shifted[15]}}, shifted[15:0]};
                            MEM_BU:  result = {24'd0, shifted[7:0]};
                            MEM_HU:  result = {16'd0, shifted[15:0]};
                            default: result = word;
                        endcase
                    end else begin
                        result      = mmio_load_data;
                        o_mmio_load = 1'b1;
                    end
                end
                OPC_STORE: if (funct3 <= 3'b010) begin
                    addr = rs1v + imm_s;
                    if (in_ram(addr)) begin
                        word = mem[addr[RAM_ADDR_WIDTH+1:2]];
                        case (funct3)
                            MEM_B: case (addr[1:0])
                                2'd0: word[ 7: 0] = rs2v[7:0];
                                2'd1: word[15: 8] = rs2v[7:0];
                                2'd2: word[23:16] = rs2v[7:0];
                                2'd3: word[31:24] = rs2v[7:0];
                            endcase
                            MEM_H: if (addr[1]) word[31:16] = rs2v[15:0];
                                   else         word[15: 0] = rs2v[15:0];
                            default: word = rs2v;
                        endcase
                        mem[addr[RAM_ADDR_WIDTH+1:2]] = word;
                    end
                end
                OPC_OP_IMM: begin
                    if (!((funct3 == 3'b001 && funct7 != 7'h00) ||
                          (funct3 == 3'b101 && funct7 != 7'h00 && funct7 != 7'h20))) begin
                        we = 1'b1;
                        case (funct3)
                            3'b000: result = rs1v + imm_i;
                            3'b010: result = {31'd0, $signed(rs1v) < $signed(imm_i)};
                            3'b011: result = {31'd0, rs1v < imm_i};
                            3'b100: result = rs1v ^ imm_i;
                            3'b110: result = rs1v | imm_i;
                            3'b111: result = rs1v & imm_i;
                            3'b001: result = rs1v << instr[24:20];
                            3'b101: result = instr[30] ? $unsigned($signed(rs1v) >>> instr[24:20])
                                                       : rs1v >> instr[24:20];
                        endcase
                    end
                end
                OPC_OP: begin
                    if (funct7 == 7'h00 ||
                        (funct7 == 7'h20 && (funct3 == 3'b000 || funct3 == 3'b101))) begin
                        we = 1'b1;
                        case (funct3)
                            3'b000: result = funct7[5] ? rs1v - rs2v : rs1v + rs2v;
                            3'b001: result = rs1v << rs2v[4:0];
                            3'b010: result = {31'd0, $signed(rs1v) < $signed(rs2v)};
                            3'b011: result = {31'd0, rs1v < rs2v};
                            3'b100: result = rs1v ^ rs2v;
                            3'b101: result = funct7[5] ? $unsigned($signed(rs1v) >>> rs2v[4:0])
                                                       : rs1v >> rs2v[4:0];
                            3'b110: result = rs1v | rs2v;
                            3'b111: result = rs1v & rs2v;
                        endcase
                    end
                end
                default: ; // FENCE, SYSTEM and illegal encodings: no effect
            endcase

            o_pc      = pc;
            o_instr   = instr;
            o_rd_we   = we && (rd != 5'd0);
            o_rd      = rd;
            o_rd_data = result;

            if (o_rd_we)
                regs[rd] = result;
            pc = next_pc;
        end
    endtask

endmodule
