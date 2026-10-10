/* Minimal self-checking test framework for RV32I assembly tests.
 *
 * Each TEST_* macro computes a result into x14, compares it with the expected
 * value and, on mismatch, jumps to `fail` with the test number in gp (x3).
 * Registers x1, x2, x13, x14 are used as scratch; x3 holds the test number.
 */
#ifndef TEST_MACROS_H
#define TEST_MACROS_H

#include "soc.h"

#define TESTNUM gp

#define TEST_BEGIN                      \
    .section .text.init;                \
    .globl _start;                      \
_start:                                 \
    li      TESTNUM, 0;

#define TEST_END                        \
pass:                                   \
    li      t0, TOHOST_ADDR;            \
    li      t1, 1;                      \
    sw      t1, 0(t0);                  \
1:  j       1b;                         \
fail:                                   \
    li      t0, TOHOST_ADDR;            \
    slli    t1, TESTNUM, 1;             \
    ori     t1, t1, 1;                  \
    sw      t1, 0(t0);                  \
2:  j       2b;

#define CHECK(testnum, reg, expected)   \
    li      TESTNUM, testnum;           \
    li      x13, expected;              \
    bne     reg, x13, fail;

/* rd = op(rs1, rs2) */
#define TEST_RR(testnum, inst, expected, val1, val2)    \
    li      x1, val1;                                   \
    li      x2, val2;                                   \
    inst    x14, x1, x2;                                \
    CHECK(testnum, x14, expected)

/* rd = op(rs1, imm) */
#define TEST_IMM(testnum, inst, expected, val1, imm)    \
    li      x1, val1;                                   \
    inst    x14, x1, imm;                               \
    CHECK(testnum, x14, expected)

/* Branch must be taken: falls through to fail if not. */
#define TEST_BR_TAKEN(testnum, inst, val1, val2)        \
    li      TESTNUM, testnum;                           \
    li      x1, val1;                                   \
    li      x2, val2;                                   \
    inst    x1, x2, 1f;                                 \
    j       fail;                                       \
1:

/* Branch must not be taken. */
#define TEST_BR_NOT_TAKEN(testnum, inst, val1, val2)    \
    li      TESTNUM, testnum;                           \
    li      x1, val1;                                   \
    li      x2, val2;                                   \
    inst    x1, x2, fail;

#endif
