/* AES accelerator test. Checks the hardware against the FIPS-197 and
 * NIST SP 800-38A vectors plus random vectors from tools/aes_ref.py
 * (aes_vectors.h), and against the software AES in aes_soft.h.
 * Returns 0 on success, else the number of the failing check. */
#include "periph.h"
#include "aes_soft.h"
#include "aes_vectors.h"

static uint32_t out[AES_NVEC][4];
static uint32_t buf[4];

static int same(const uint32_t *a, const uint32_t *b)
{
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];
}

int main(void)
{
    /* 1: idle after reset, nothing queued */
    uint32_t s = aes_status();
    if ((s & ~AES_PIPELINED) != AES_READY || REG(AES_BASE, AES_BLOCKS) != 0)
        return 1;

    /* 2: FIPS-197 Appendix B and C.1, one block at a time */
    for (int i = 0; i < 2; i++) {
        aes_encrypt_block(aes_vec_key[i], aes_vec_pt[i], buf);
        if (!same(buf, aes_vec_ct[i]))
            return 2;
    }

    /* 3: SP 800-38A ECB, four blocks with one key, streamed */
    aes_ecb_encrypt(aes_vec_key[2], &aes_vec_pt[2][0], &out[0][0], 4);
    for (int i = 0; i < 4; i++)
        if (!same(out[i], aes_vec_ct[2 + i]))
            return 3;

    /* 4: all vectors streamed with a different key per block: the key
     * registers change while earlier blocks are still in the pipeline */
    {
        uint32_t sent = 0, done = 0;
        while (done < AES_NVEC) {
            s = aes_status();
            if (sent < AES_NVEC && (s & AES_READY)) {
                aes_set_key(aes_vec_key[sent]);
                aes_push(aes_vec_pt[sent]);
                sent++;
            }
            if (s & AES_OUT_VALID)
                aes_pop(out[done++]);
        }
        for (int i = 0; i < AES_NVEC; i++)
            if (!same(out[i], aes_vec_ct[i]))
                return 4;
    }

    /* 5: the software AES agrees (it is also used by aes_bench) */
    for (int i = 0; i < 3; i++) {
        aes_soft_encrypt(aes_vec_key[8 + i], aes_vec_pt[8 + i], buf);
        if (!same(buf, aes_vec_ct[8 + i]))
            return 5;
    }

    /* 6: block counter, nothing left over, no overflow */
    s = aes_status();
    if (REG(AES_BASE, AES_BLOCKS) != 2 + 4 + AES_NVEC ||
        (s & ~AES_PIPELINED) != AES_READY)
        return 6;

    /* 7: CLEAR discards results */
    aes_push(aes_vec_pt[0]);
    while (!(aes_status() & AES_OUT_VALID))
        ;
    REG(AES_BASE, AES_CMD) = AES_CLEAR;
    if ((aes_status() & ~AES_PIPELINED) != AES_READY)
        return 7;
    return 0;
}
