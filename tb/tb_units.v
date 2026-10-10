// Unit tests for the combinational blocks: ALU, branch unit and the
// decoder's immediate generation. Each block is driven with corner cases
// plus random vectors and compared with a behavioural expression.
module tb_units;
`include "rv32i_defs.vh"

    integer errors = 0;
    integer checks = 0;
    integer n, k;

    // ------------------------------------------------------------------
    // ALU
    // ------------------------------------------------------------------
    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] alu_y;

    alu u_alu (.op_a(a), .op_b(b), .alu_op(op), .result(alu_y));

    function [31:0] alu_ref(input [3:0] f, input [31:0] x, input [31:0] y);
        case (f)
            ALU_ADD:  alu_ref = x + y;
            ALU_SUB:  alu_ref = x - y;
            ALU_SLL:  alu_ref = x << y[4:0];
            ALU_SLT:  alu_ref = ($signed(x) < $signed(y)) ? 32'd1 : 32'd0;
            ALU_SLTU: alu_ref = (x < y) ? 32'd1 : 32'd0;
            ALU_XOR:  alu_ref = x ^ y;
            ALU_SRL:  alu_ref = x >> y[4:0];
            ALU_SRA:  alu_ref = $unsigned($signed(x) >>> y[4:0]);
            ALU_OR:   alu_ref = x | y;
            ALU_AND:  alu_ref = x & y;
            default:  alu_ref = 32'd0;
        endcase
    endfunction

    reg [3:0] alu_ops [0:9];
    reg [31:0] corners [0:7];

    task check_alu;
        begin
            #1;
            checks = checks + 1;
            if (alu_y !== alu_ref(op, a, b)) begin
                errors = errors + 1;
                if (errors < 20)
                    $display("ALU FAIL op=%b a=%08h b=%08h got=%08h exp=%08h",
                             op, a, b, alu_y, alu_ref(op, a, b));
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Branch unit
    // ------------------------------------------------------------------
    reg  [2:0] f3;
    wire       taken;

    branch_unit u_br (.rs1(a), .rs2(b), .funct3(f3), .taken(taken));

    function br_ref(input [2:0] f, input [31:0] x, input [31:0] y);
        case (f)
            BR_EQ:   br_ref = (x == y);
            BR_NE:   br_ref = (x != y);
            BR_LT:   br_ref = ($signed(x) <  $signed(y));
            BR_GE:   br_ref = ($signed(x) >= $signed(y));
            BR_LTU:  br_ref = (x <  y);
            BR_GEU:  br_ref = (x >= y);
            default: br_ref = 1'b0;
        endcase
    endfunction

    task check_br;
        begin
            #1;
            checks = checks + 1;
            if (taken !== br_ref(f3, a, b)) begin
                errors = errors + 1;
                if (errors < 20)
                    $display("BRANCH FAIL f3=%b a=%08h b=%08h got=%b", f3, a, b, taken);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Decoder immediates: encode a known immediate, decode, compare.
    // ------------------------------------------------------------------
    reg  [31:0] instr;
    wire [31:0] imm;

    decoder u_dec (
        .instr(instr), .rs1(), .rs2(), .rd(), .funct3(), .imm(imm),
        .uses_rs1(), .uses_rs2(), .reg_we(), .alu_op(), .opa_sel(), .opb_imm(),
        .is_branch(), .is_jal(), .is_jalr(), .mem_re(), .mem_we(), .illegal()
    );

    task check_imm(input [31:0] exp, input [8*8-1:0] fmt);
        begin
            #1;
            checks = checks + 1;
            if (imm !== exp) begin
                errors = errors + 1;
                if (errors < 20)
                    $display("IMM FAIL %0s instr=%08h got=%08h exp=%08h", fmt, instr, imm, exp);
            end
        end
    endtask

    reg [31:0] v;

    initial begin
        alu_ops[0] = ALU_ADD;  alu_ops[1] = ALU_SUB;  alu_ops[2] = ALU_SLL;
        alu_ops[3] = ALU_SLT;  alu_ops[4] = ALU_SLTU; alu_ops[5] = ALU_XOR;
        alu_ops[6] = ALU_SRL;  alu_ops[7] = ALU_SRA;  alu_ops[8] = ALU_OR;
        alu_ops[9] = ALU_AND;
        corners[0] = 32'h0000_0000; corners[1] = 32'h0000_0001;
        corners[2] = 32'hffff_ffff; corners[3] = 32'h8000_0000;
        corners[4] = 32'h7fff_ffff; corners[5] = 32'h0000_001f;
        corners[6] = 32'h0000_0020; corners[7] = 32'haaaa_5555;

        // ALU: all corner pairs, then random.
        for (k = 0; k < 10; k = k + 1) begin
            op = alu_ops[k];
            for (n = 0; n < 64; n = n + 1) begin
                a = corners[n / 8];
                b = corners[n % 8];
                check_alu;
            end
            for (n = 0; n < 2000; n = n + 1) begin
                a = $random;
                b = $random;
                check_alu;
            end
        end

        // Branch unit
        for (k = 0; k < 8; k = k + 1) begin
            f3 = k;
            for (n = 0; n < 64; n = n + 1) begin
                a = corners[n / 8];
                b = corners[n % 8];
                check_br;
            end
            for (n = 0; n < 2000; n = n + 1) begin
                a = $random;
                b = (n % 4 == 0) ? a : $random;   // exercise equality
                check_br;
            end
        end

        // Immediates
        for (n = 0; n < 2000; n = n + 1) begin
            v = $random;

            // I-type (ADDI): imm[11:0] -> instr[31:20]
            instr = {v[11:0], 5'd1, 3'b000, 5'd2, OPC_OP_IMM};
            check_imm({{20{v[11]}}, v[11:0]}, "I");

            // S-type (SW)
            instr = {v[11:5], 5'd3, 5'd1, 3'b010, v[4:0], OPC_STORE};
            check_imm({{20{v[11]}}, v[11:0]}, "S");

            // B-type (BEQ), imm[0] = 0
            instr = {v[12], v[10:5], 5'd3, 5'd1, 3'b000, v[4:1], v[11], OPC_BRANCH};
            check_imm({{19{v[12]}}, v[12:1], 1'b0}, "B");

            // U-type (LUI)
            instr = {v[31:12], 5'd4, OPC_LUI};
            check_imm({v[31:12], 12'd0}, "U");

            // J-type (JAL), imm[0] = 0
            instr = {v[20], v[10:1], v[11], v[19:12], 5'd1, OPC_JAL};
            check_imm({{11{v[20]}}, v[20:1], 1'b0}, "J");
        end

        $display("------------------------------------------------------------");
        $display("unit tests: %0d checks, %0d errors", checks, errors);
        if (errors == 0) begin
            $display("TEST PASSED");
            $finish;
        end else begin
            $display("TEST FAILED");
            $fatal(1);
        end
    end

endmodule
