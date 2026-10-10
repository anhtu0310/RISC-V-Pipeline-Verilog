/* C smoke test: exercises the compiler output (stack, calls, loops,
 * byte/half accesses) and reports through crt0 (0 = pass). */
#include <stdint.h>

static uint32_t crc32(const uint8_t *data, int len)
{
    uint32_t crc = 0xffffffffu;
    for (int i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++)
            crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1u));
    }
    return ~crc;
}

/* Software multiply, since RV32I has no M extension. Kept explicit so the
 * test does not depend on libgcc. */
static uint32_t mul(uint32_t a, uint32_t b)
{
    uint32_t r = 0;
    while (b) {
        if (b & 1u)
            r += a;
        a <<= 1;
        b >>= 1;
    }
    return r;
}

static void sort(int16_t *v, int n)
{
    for (int i = 1; i < n; i++) {
        int16_t key = v[i];
        int j = i - 1;
        while (j >= 0 && v[j] > key) {
            v[j + 1] = v[j];
            j--;
        }
        v[j + 1] = key;
    }
}

static uint32_t fib(uint32_t n)
{
    return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

static const char msg[] = "123456789";
static int16_t data[8] = { 300, -5, 42, 7, -32768, 32767, 0, 7 };
static volatile uint32_t sink;

int main(void)
{
    if (crc32((const uint8_t *)msg, 9) != 0xcbf43926u)
        return 1;

    if (mul(12345u, 6789u) != 83810205u)
        return 2;

    sort(data, 8);
    static const int16_t sorted[8] = { -32768, -5, 0, 7, 7, 42, 300, 32767 };
    for (int i = 0; i < 8; i++)
        if (data[i] != sorted[i])
            return 3;

    if (fib(15) != 610u)
        return 4;

    sink = 0xdeadbeef;
    if (sink != 0xdeadbeef)
        return 5;

    return 0;
}
