/* I2C test against the testbench's two 256-byte slave devices:
 *   0x50: stretches SCL after every ACK, 0x51: no stretching.
 * Both power up with mem[i] = i ^ 0x5a.
 * Returns 0 on success, else the number of the failing check. */
#include "periph.h"

int main(void)
{
    i2c_init(4);    /* SCL = clk / 23 in simulation */

    if (REG(I2C_BASE, I2C_STATUS) != 0)
        return 1;

    static const uint8_t wr[4] = { 0x11, 0x22, 0xc3, 0xf4 };
    if (i2c_write_regs(0x50, 0x20, wr, 4))
        return 2;
    if (REG(I2C_BASE, I2C_STATUS) & (I2C_BUSY | I2C_BUS_ACTIVE))
        return 3;

    uint8_t rd[6];
    if (i2c_read_regs(0x50, 0x1f, rd, 6))
        return 4;
    /* 0x1f and 0x24 are untouched: i ^ 0x5a */
    if (rd[0] != (0x1f ^ 0x5a) || rd[1] != 0x11 || rd[2] != 0x22 ||
        rd[3] != 0xc3 || rd[4] != 0xf4 || rd[5] != (0x24 ^ 0x5a))
        return 5;

    /* The other device is unchanged */
    if (i2c_read_regs(0x51, 0x20, rd, 2))
        return 6;
    if (rd[0] != (0x20 ^ 0x5a) || rd[1] != (0x21 ^ 0x5a))
        return 7;

    /* Nobody answers at 0x23 */
    if (i2c_write_byte(0x23 << 1, I2C_CMD_START) == 0)
        return 8;
    i2c_cmd(I2C_CMD_STOP);
    if (REG(I2C_BASE, I2C_STATUS) != I2C_NACKED)
        return 9;

    return 0;
}
