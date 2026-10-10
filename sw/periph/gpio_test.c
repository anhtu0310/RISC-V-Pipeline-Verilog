/* GPIO test. The testbench wires the pins like a small board:
 *   pins  7:0   outputs; also wired externally to pins 31:24
 *   pins 23:16  inputs tied to 0xA5
 *   pins 15:8   inputs tied to 0
 * Returns 0 on success, else the number of the failing check. */
#include "periph.h"

static uint32_t read_settled(void)
{
    /* Inputs pass a 2-flop synchroniser: give them a few cycles. */
    for (volatile int i = 0; i < 2; i++)
        ;
    return gpio_read();
}

int main(void)
{
    gpio_set_dir(0x000000ff);
    if (REG(GPIO_BASE, GPIO_DIR) != 0x000000ff)
        return 1;

    gpio_write(0x5a);
    if (read_settled() != 0x5aa5005a)
        return 2;

    REG(GPIO_BASE, GPIO_RISE) = 0xffffffff;
    REG(GPIO_BASE, GPIO_FALL) = 0xffffffff;

    gpio_set(0x81);                         /* 0x5a -> 0xdb */
    if ((read_settled() & 0xff0000ff) != 0xdb0000db)
        return 3;
    gpio_clear(0x0f);                       /* 0xdb -> 0xd0 */
    gpio_toggle(0xff);                      /* 0xd0 -> 0x2f */
    if (REG(GPIO_BASE, GPIO_DATA_OUT) != 0x2f)
        return 4;
    if ((read_settled() & 0xff0000ff) != 0x2f00002f)
        return 5;

    /* Edges since the clear: 0x5a -> 0xdb -> 0xd0 -> 0x2f */
    uint32_t rise = REG(GPIO_BASE, GPIO_RISE);
    uint32_t fall = REG(GPIO_BASE, GPIO_FALL);
    if (rise != 0xaf0000af || fall != 0xdb0000db)
        return 6;

    REG(GPIO_BASE, GPIO_RISE) = 0x000000ff; /* W1C: low byte only */
    if (REG(GPIO_BASE, GPIO_RISE) != 0xaf000000)
        return 7;

    /* Byte store to DATA_OUT only touches that byte */
    *(volatile uint8_t *)(GPIO_BASE + GPIO_DATA_OUT) = 0x99;
    if (REG(GPIO_BASE, GPIO_DATA_OUT) != 0x99)
        return 8;

    /* Count a burst of pulses with the edge latch */
    int pulses = 0;
    for (int i = 0; i < 5; i++) {
        REG(GPIO_BASE, GPIO_RISE) = 1u << 24;
        gpio_toggle(1);
        gpio_toggle(1);
        (void)read_settled();
        if (REG(GPIO_BASE, GPIO_RISE) & (1u << 24))
            pulses++;
    }
    if (pulses != 5)
        return 9;

    return 0;
}
