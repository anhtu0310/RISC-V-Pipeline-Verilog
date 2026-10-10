/* AES speed comparison. Writes markers to MARK_ADDR; tb_soc prints the
 * cycle count at each one, so the cost of each section is the difference:
 *   1 -> 2   software AES (aes_soft.h), BENCH_SOFT blocks
 *   2 -> 3   accelerator, one block at a time (aes_encrypt_block)
 *   3 -> 4   accelerator, streamed ECB (aes_ecb_encrypt), BENCH_HW blocks
 * Also checks that all three give the same ciphertext.
 * Returns 0 on success, else the number of the failing check. */
#include "periph.h"
#include "aes_soft.h"

#define BENCH_SOFT 4
#define BENCH_HW   64
#define MARK(n) (*(volatile uint32_t *)MARK_ADDR = (n))

static const uint32_t key[4] = { 0x16157e2b, 0xa6d2ae28, 0x8815f7ab, 0x3c4fcf09 };
static uint32_t pt[BENCH_HW][4];
static uint32_t ct_soft[BENCH_SOFT][4];
static uint32_t ct_one[BENCH_SOFT][4];
static uint32_t ct_ecb[BENCH_HW][4];

int main(void)
{
    for (uint32_t i = 0; i < BENCH_HW; i++)
        for (uint32_t j = 0; j < 4; j++)
            pt[i][j] = (i * 0x9e3779b9u) ^ (j * 0x7f4a7c15u);

    MARK(1);
    for (int i = 0; i < BENCH_SOFT; i++)
        aes_soft_encrypt(key, pt[i], ct_soft[i]);
    MARK(2);
    for (int i = 0; i < BENCH_SOFT; i++)
        aes_encrypt_block(key, pt[i], ct_one[i]);
    MARK(3);
    aes_ecb_encrypt(key, &pt[0][0], &ct_ecb[0][0], BENCH_HW);
    MARK(4);

    for (int i = 0; i < BENCH_SOFT; i++)
        for (int j = 0; j < 4; j++)
            if (ct_soft[i][j] != ct_one[i][j] || ct_one[i][j] != ct_ecb[i][j])
                return 1;
    if (REG(AES_BASE, AES_BLOCKS) != BENCH_SOFT + BENCH_HW)
        return 2;
    return 0;
}
