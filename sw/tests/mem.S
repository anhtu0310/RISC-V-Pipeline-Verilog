# Loads and stores of every width at every legal byte offset.
#include "test_macros.h"

    .data
    .align 4
buf:    .word 0x00000000, 0x00000000
src:    .word 0x8899aabb, 0x7f6e5d4c

#define TEST_LD(testnum, inst, expected, offset, base) \
    inst    x14, offset(base);                         \
    CHECK(testnum, x14, expected)

TEST_BEGIN
    la      x5, src

    # Loads with sign/zero extension
    TEST_LD( 1, lw,  0x8899aabb, 0, x5)
    TEST_LD( 2, lw,  0x7f6e5d4c, 4, x5)
    TEST_LD( 3, lb,  0xffffffbb, 0, x5)
    TEST_LD( 4, lb,  0xffffffaa, 1, x5)
    TEST_LD( 5, lb,  0xffffff99, 2, x5)
    TEST_LD( 6, lb,  0xffffff88, 3, x5)
    TEST_LD( 7, lbu, 0x000000bb, 0, x5)
    TEST_LD( 8, lbu, 0x00000088, 3, x5)
    TEST_LD( 9, lb,  0x0000004c, 4, x5)
    TEST_LD(10, lb,  0x0000007f, 7, x5)
    TEST_LD(11, lh,  0xffffaabb, 0, x5)
    TEST_LD(12, lh,  0xffff8899, 2, x5)
    TEST_LD(13, lhu, 0x0000aabb, 0, x5)
    TEST_LD(14, lhu, 0x00008899, 2, x5)
    TEST_LD(15, lh,  0x00005d4c, 4, x5)
    TEST_LD(16, lh,  0x00007f6e, 6, x5)
    addi    x6, x5, 4
    TEST_LD(17, lw,  0x8899aabb, -4, x6) # negative offset

    # Byte stores must only touch their own lane.
    la      x6, buf
    li      x7, 0x11223344
    sw      x7, 0(x6)
    li      x8, 0xa5
    sb      x8, 0(x6)
    TEST_LD(20, lw, 0x112233a5, 0, x6)
    sb      x8, 1(x6)
    TEST_LD(21, lw, 0x1122a5a5, 0, x6)
    li      x8, 0x5a
    sb      x8, 3(x6)
    TEST_LD(22, lw, 0x5a22a5a5, 0, x6)
    li      x8, 0x777
    sb      x8, 2(x6)               # only the low byte is stored
    TEST_LD(23, lw, 0x5a77a5a5, 0, x6)

    # Half-word stores
    li      x7, 0xcafe1234
    sh      x7, 4(x6)
    TEST_LD(30, lw, 0x00001234, 4, x6)
    sh      x7, 6(x6)
    TEST_LD(31, lw, 0x12341234, 4, x6)
    li      x7, 0xbeef
    sh      x7, 6(x6)
    TEST_LD(32, lw, 0xbeef1234, 4, x6)
    TEST_LD(33, lhu, 0x0000beef, 6, x6)
    TEST_LD(34, lh,  0xffffbeef, 6, x6)

    # Store then load of the same word in back-to-back instructions.
    li      x7, 0x0badf00d
    sw      x7, 0(x6)
    lw      x14, 0(x6)
    CHECK(40, x14, 0x0badf00d)

    # Loads from unmapped space read as zero.
    li      x9, 0x20000000
    TEST_LD(41, lw, 0, 0, x9)

    j       pass

TEST_END
