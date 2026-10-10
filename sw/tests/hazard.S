# Pipeline hazards: forwarding, load-use stalls, x0 and control hazards.
#include "test_macros.h"

    .data
    .align 4
val:    .word 0x00000005, 0x00000007, 0x00000000

TEST_BEGIN
    # --- ALU -> ALU forwarding at distance 1, 2 and 3 -------------------
    li      TESTNUM, 1
    li      x1, 10
    addi    x14, x1, 1              # x1 from MEM forward
    li      x13, 11
    bne     x14, x13, fail

    li      TESTNUM, 2
    li      x1, 20
    nop
    addi    x14, x1, 1              # x1 from WB forward
    li      x13, 21
    bne     x14, x13, fail

    li      TESTNUM, 3
    li      x1, 30
    nop
    nop
    addi    x14, x1, 1              # x1 via register file write-through
    li      x13, 31
    bne     x14, x13, fail

    # Both operands forwarded, from different stages.
    li      TESTNUM, 4
    li      x1, 3
    li      x2, 4
    add     x14, x1, x2             # x1 from WB, x2 from MEM
    li      x13, 7
    bne     x14, x13, fail

    # The youngest producer must win when MEM and WB hold the same rd.
    li      TESTNUM, 5
    li      x1, 1
    li      x1, 2
    addi    x14, x1, 0
    li      x13, 2
    bne     x14, x13, fail

    # Chain of dependent instructions.
    li      TESTNUM, 6
    li      x14, 1
    add     x14, x14, x14
    add     x14, x14, x14
    add     x14, x14, x14
    add     x14, x14, x14
    li      x13, 16
    bne     x14, x13, fail

    # --- x0 is never forwarded -----------------------------------------
    li      TESTNUM, 10
    addi    x0, x0, 5
    add     x14, x0, x0
    bnez    x14, fail

    li      TESTNUM, 11
    li      x1, 0x55
    add     x0, x1, x1
    nop
    or      x14, x0, x0
    bnez    x14, fail

    la      x5, val
    li      TESTNUM, 12
    lw      x0, 0(x5)
    add     x14, x0, x0
    bnez    x14, fail

    # --- Load-use --------------------------------------------------------
    la      x5, val
    li      TESTNUM, 20
    lw      x1, 0(x5)
    addi    x14, x1, 1              # rs1 depends on the load
    li      x13, 6
    bne     x14, x13, fail

    li      TESTNUM, 21
    lw      x2, 4(x5)
    sub     x14, x0, x2             # rs2 depends on the load
    li      x13, -7
    bne     x14, x13, fail

    li      TESTNUM, 22
    lw      x1, 0(x5)
    nop
    addi    x14, x1, 2              # distance 2: WB forward, no stall needed
    li      x13, 7
    bne     x14, x13, fail

    li      TESTNUM, 23
    lw      x1, 0(x5)
    sw      x1, 8(x5)               # store data depends on the load
    lw      x14, 8(x5)
    li      x13, 5
    bne     x14, x13, fail

    li      TESTNUM, 24
    addi    x6, x5, 4
    lw      x7, -4(x6)              # load address depends on an ALU result
    lw      x14, 0(x6)
    add     x14, x14, x7
    li      x13, 12
    bne     x14, x13, fail

    li      TESTNUM, 25
    lw      x1, 0(x5)
    lw      x2, 4(x5)
    add     x14, x1, x2             # x1 from WB, x2 after a stall
    li      x13, 12
    bne     x14, x13, fail

    li      TESTNUM, 26
    la      x6, val
    lw      x6, 0(x6)               # load overwrites its own base register
    li      x13, 5
    bne     x6, x13, fail

    # A branch that depends on a load.
    li      TESTNUM, 27
    lw      x1, 0(x5)
    li      x2, 5
    bne     x1, x2, fail
    lw      x1, 4(x5)
    beq     x1, x2, fail            # 7 != 5

    # A jalr whose base comes from a load.
    li      TESTNUM, 28
    la      x1, 1f
    sw      x1, 8(x5)
    lw      x2, 8(x5)
    jalr    x0, 0(x2)
    j       fail
1:

    # --- Control hazards -------------------------------------------------
    # A taken branch must squash a younger load-use stall situation.
    li      TESTNUM, 30
    li      x14, 0
    beq     x0, x0, 2f
    lw      x14, 0(x5)
    addi    x14, x14, 1
2:  bnez    x14, fail

    # Branch directly after an ALU op that produces its operand.
    li      TESTNUM, 31
    li      x1, 9
    addi    x1, x1, 1
    li      x2, 10
    bne     x1, x2, fail

    # Back-to-back taken branches.
    li      TESTNUM, 32
    li      x14, 0
    j       3f
3:  j       4f
    addi    x14, x14, 1
4:  beqz    x14, 5f
    j       fail
5:

    j       pass

TEST_END
