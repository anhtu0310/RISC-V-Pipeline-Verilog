# Register-register and register-immediate ALU instructions.
#include "test_macros.h"

TEST_BEGIN
    # ADD / SUB
    TEST_RR( 1, add,  0x00000000, 0x00000000, 0x00000000)
    TEST_RR( 2, add,  0x00000002, 0x00000001, 0x00000001)
    TEST_RR( 3, add,  0x80000000, 0x7fffffff, 0x00000001)
    TEST_RR( 4, add,  0x00000000, 0xffffffff, 0x00000001)
    TEST_RR( 5, sub,  0xffffffff, 0x00000000, 0x00000001)
    TEST_RR( 6, sub,  0x7fffffff, 0x80000000, 0x00000001)
    TEST_RR( 7, sub,  0x00000000, 0x12345678, 0x12345678)

    # Logic
    TEST_RR(10, and,  0x0f000f00, 0xff00ff00, 0x0f0f0f0f)
    TEST_RR(11, or,   0xff0fff0f, 0xff00ff00, 0x0f0f0f0f)
    TEST_RR(12, xor,  0xf00ff00f, 0xff00ff00, 0x0f0f0f0f)

    # Shifts (only rs2[4:0] is used)
    TEST_RR(20, sll,  0x80000000, 0x00000001, 31)
    TEST_RR(21, sll,  0x00000002, 0x00000001, 0xffffffe1)
    TEST_RR(22, srl,  0x00000001, 0x80000000, 31)
    TEST_RR(23, srl,  0x01ffffff, 0xffffffff, 7)
    TEST_RR(24, sra,  0xffffffff, 0x80000000, 31)
    TEST_RR(25, sra,  0x00ffffff, 0x7fffffff, 7)
    TEST_RR(26, sra,  0xff000000, 0x80000000, 0xffffffe7)

    # Set-less-than
    TEST_RR(30, slt,  1, 0xffffffff, 0x00000000)
    TEST_RR(31, slt,  0, 0x00000000, 0xffffffff)
    TEST_RR(32, slt,  1, 0x80000000, 0x7fffffff)
    TEST_RR(33, sltu, 0, 0xffffffff, 0x00000000)
    TEST_RR(34, sltu, 1, 0x00000000, 0xffffffff)
    TEST_RR(35, sltu, 0, 0x12345678, 0x12345678)

    # Immediate forms (12-bit sign-extended immediate)
    TEST_IMM(40, addi,  0x00000000, 0x00000001, -1)
    TEST_IMM(41, addi,  0x800007fe, 0x7fffffff, 0x7ff)
    TEST_IMM(42, addi,  0x7ffff800, 0x80000000, -2048)
    TEST_IMM(43, andi,  0x00000700, 0xff00ff00, 0x70f)
    TEST_IMM(44, andi,  0xff00ff00, 0xff00ff00, -1)
    TEST_IMM(45, ori,   0xff00fff0, 0xff00ff00, 0x0f0)
    TEST_IMM(46, ori,   0xffffffff, 0x00000000, -1)
    TEST_IMM(47, xori,  0x00ff000f, 0xff00ff0f, -256)
    TEST_IMM(48, slti,  1, 0xffffffff, 0)
    TEST_IMM(49, slti,  0, 0x00000000, -1)
    TEST_IMM(50, sltiu, 1, 0x00000000, -1)      # -1 compares as 0xffffffff
    TEST_IMM(51, sltiu, 0, 0xffffffff, 1)
    TEST_IMM(52, slli,  0x80000000, 0x00000001, 31)
    TEST_IMM(53, srli,  0x00000001, 0x80000000, 31)
    TEST_IMM(54, srai,  0xffffffff, 0x80000000, 31)
    TEST_IMM(55, srai,  0x0000007f, 0x00000fff, 5)
    TEST_IMM(56, srli,  0x07ffffff, 0xffffffff, 5)

    # LUI / AUIPC
    li      TESTNUM, 60
    lui     x14, 0xfffff
    li      x13, 0xfffff000
    bne     x14, x13, fail

    li      TESTNUM, 61
1:  auipc   x14, 0x1
    la      x13, 1b
    sub     x14, x14, x13
    li      x13, 0x1000
    bne     x14, x13, fail

    li      TESTNUM, 62
    lui     x0, 0x12345             # writes to x0 are discarded
    bnez    x0, fail

    j       pass

TEST_END
