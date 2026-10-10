# C runtime start-up: set up sp/gp, clear .bss, call main, report result.
#include "soc.h"

    .section .text.init
    .globl _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, __stack_top

    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    call    main

    # main returns 0 on success; anything else is a failure code.
    li      t0, TOHOST_ADDR
    beqz    a0, 3f
    slli    a0, a0, 1
    ori     a0, a0, 1
    sw      a0, 0(t0)
    j       4f
3:  li      a0, 1
    sw      a0, 0(t0)
4:  j       4b
