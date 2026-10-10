/* SPI test. The testbench has one slave per chip select, in SPI mode 0..3
 * (CPOL = mode >> 1, CPHA = mode & 1). Each answers the first byte after
 * select with its ID (0xA0 + mode) and then echoes the previous byte.
 * Returns 0 on success, else the number of the failing check. */
#include "periph.h"

static const uint8_t pattern[4] = { 0x3c, 0x81, 0xff, 0x00 };

int main(void)
{
    for (uint32_t mode = 0; mode < 4; mode++) {
        uint32_t ctrl = ((mode >> 1) ? SPI_CPOL : 0) | ((mode & 1) ? SPI_CPHA : 0);
        spi_init(ctrl, mode);           /* different clock divider per mode */
        spi_select(1u << mode);

        uint8_t expect = 0xa0 + mode;
        for (int i = 0; i < 4; i++) {
            if (spi_xfer(pattern[i]) != expect)
                return 1 + mode;
            expect = pattern[i];
        }
        spi_select(0);
    }

    /* LSB first on the mode-0 (MSB-first) slave: it sees bytes reversed */
    spi_init(SPI_LSB_FIRST, 1);
    spi_select(1);
    if (spi_xfer(0x01) != 0x05)        /* ID 0xA0 bit-reversed */
        return 5;
    if (spi_xfer(0x00) != 0x01)        /* echo of 0x01, reversed twice */
        return 6;
    spi_select(0);

    if (REG(SPI_BASE, SPI_CTRL) != SPI_LSB_FIRST || REG(SPI_BASE, SPI_STATUS) != 0)
        return 7;
    return 0;
}
