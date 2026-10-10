# Conditional branches, JAL and JALR.
#include "test_macros.h"

TEST_BEGIN
    TEST_BR_TAKEN    ( 1, beq,  5, 5)
    TEST_BR_NOT_TAKEN( 2, beq,  5, 6)
    TEST_BR_TAKEN    ( 3, bne,  5, 6)
    TEST_BR_NOT_TAKEN( 4, bne,  5, 5)
    TEST_BR_TAKEN    ( 5, blt,  -1, 0)
    TEST_BR_NOT_TAKEN( 6, blt,  0, -1)
    TEST_BR_NOT_TAKEN( 7, blt,  3, 3)
    TEST_BR_TAKEN    ( 8, bge,  0, -1)
    TEST_BR_TAKEN    ( 9, bge,  3, 3)
    TEST_BR_NOT_TAKEN(10, bge,  -1, 0)
    TEST_BR_TAKEN    (11, bltu, 0, -1)
    TEST_BR_NOT_TAKEN(12, bltu, -1, 0)
    TEST_BR_TAKEN    (13, bgeu, -1, 0)
    TEST_BR_TAKEN    (14, bgeu, 7, 7)
    TEST_BR_NOT_TAKEN(15, bgeu, 0, -1)

    # Backward branch: count down a loop.
    li      TESTNUM, 20
    li      x1, 10
    li      x14, 0
1:  addi    x14, x14, 3
    addi    x1, x1, -1
    bnez    x1, 1b
    li      x13, 30
    bne     x14, x13, fail

    # Instructions after a taken branch must be squashed.
    li      TESTNUM, 21
    li      x14, 0
    beq     x0, x0, 2f
    addi    x14, x14, 1
    addi    x14, x14, 2
    addi    x14, x14, 4
2:  bnez    x14, fail

    # JAL: link register holds pc+4 and the shadow is squashed.
    li      TESTNUM, 30
    li      x14, 0
3:  jal     x1, 4f
    addi    x14, x14, 1
4:  bnez    x14, fail
    la      x13, 3b
    addi    x13, x13, 4
    bne     x1, x13, fail

    # JALR: target = (rs1 + imm) & ~1.
    li      TESTNUM, 31
    la      x2, 5f
    addi    x2, x2, 1               # odd address: bit 0 must be cleared
    jalr    x1, 0(x2)
    j       fail
5:

    li      TESTNUM, 32
    la      x2, 7f
    jalr    x1, 4(x2)               # skip the 'j fail' at 7
7:  j       fail
    la      x13, 7b                 # link = address of the instruction after jalr
    bne     x1, x13, fail

    # JALR with rd == rs1 (link written after the target is computed).
    li      TESTNUM, 33
    la      x1, 8f
    jalr    x1, 0(x1)
    j       fail
8:  la      x13, 8b
    addi    x13, x13, -4
    bne     x1, x13, fail

    # Call/return through the stack-style ra.
    li      TESTNUM, 34
    li      x14, 0
    jal     ra, 9f
    li      x13, 7
    bne     x14, x13, fail
    j       pass
9:  addi    x14, x14, 7
    ret

TEST_END
