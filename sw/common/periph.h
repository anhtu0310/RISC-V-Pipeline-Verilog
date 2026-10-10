/* Small polling drivers for the SoC peripherals (GPIO, UART, I2C, SPI). */
#ifndef PERIPH_H
#define PERIPH_H

#include <stdint.h>
#include "soc.h"

#define REG(base, off) (*(volatile uint32_t *)((base) + (off)))

/* ---------------------------------------------------------------- GPIO */
static inline void     gpio_set_dir(uint32_t out_mask) { REG(GPIO_BASE, GPIO_DIR) = out_mask; }
static inline void     gpio_write(uint32_t v)          { REG(GPIO_BASE, GPIO_DATA_OUT) = v; }
static inline uint32_t gpio_read(void)                 { return REG(GPIO_BASE, GPIO_DATA_IN); }
static inline void     gpio_set(uint32_t m)            { REG(GPIO_BASE, GPIO_OUT_SET) = m; }
static inline void     gpio_clear(uint32_t m)          { REG(GPIO_BASE, GPIO_OUT_CLR) = m; }
static inline void     gpio_toggle(uint32_t m)         { REG(GPIO_BASE, GPIO_OUT_TGL) = m; }

/* ---------------------------------------------------------------- UART */
static inline void uart_init(uint32_t clocks_per_bit)
{
    REG(UART_BASE, UART_BAUD_DIV) = clocks_per_bit;
}

static inline void uart_putc(char c)
{
    while (REG(UART_BASE, UART_STATUS) & UART_TX_FULL)
        ;
    REG(UART_BASE, UART_DATA) = (uint8_t)c;
}

/* Returns the next received byte, or -1 if none arrived within `tries`
 * polls. */
static inline int uart_getc_timeout(uint32_t tries)
{
    do {
        uint32_t d = REG(UART_BASE, UART_DATA);
        if (!(d & UART_RX_EMPTY))
            return (int)(d & 0xff);
    } while (tries--);
    return -1;
}

static inline void uart_flush(void)
{
    while (!(REG(UART_BASE, UART_STATUS) & UART_TX_IDLE))
        ;
}

/* ----------------------------------------------------------------- I2C */
static inline void i2c_init(uint32_t prescale)
{
    REG(I2C_BASE, I2C_PRESCALE) = prescale;
}

/* Runs one command; returns the STATUS register once it has finished. */
static inline uint32_t i2c_cmd(uint32_t cmd)
{
    uint32_t s;
    REG(I2C_BASE, I2C_CMD) = cmd;
    while ((s = REG(I2C_BASE, I2C_STATUS)) & I2C_BUSY)
        ;
    return s;
}

/* Sends one byte (optionally with START and/or STOP); returns 0 on ACK. */
static inline int i2c_write_byte(uint8_t b, uint32_t extra)
{
    REG(I2C_BASE, I2C_TXDATA) = b;
    return (i2c_cmd(I2C_CMD_WRITE | extra) & I2C_NACKED) ? -1 : 0;
}

static inline uint8_t i2c_read_byte(uint32_t extra)
{
    i2c_cmd(I2C_CMD_READ | extra);
    return (uint8_t)REG(I2C_BASE, I2C_RXDATA);
}

/* Register-style write: START, addr+W, reg, data..., STOP. 0 on success. */
static inline int i2c_write_regs(uint8_t dev, uint8_t reg, const uint8_t *buf, int n)
{
    int err = i2c_write_byte((uint8_t)(dev << 1), I2C_CMD_START);
    if (!err)
        err = i2c_write_byte(reg, 0);
    for (int i = 0; i < n && !err; i++)
        err = i2c_write_byte(buf[i], 0);
    i2c_cmd(I2C_CMD_STOP);
    return err;
}

/* Register-style read with a repeated START. 0 on success. */
static inline int i2c_read_regs(uint8_t dev, uint8_t reg, uint8_t *buf, int n)
{
    int err = i2c_write_byte((uint8_t)(dev << 1), I2C_CMD_START);
    if (!err)
        err = i2c_write_byte(reg, 0);
    if (!err)
        err = i2c_write_byte((uint8_t)(dev << 1 | 1), I2C_CMD_START);
    if (err) {
        i2c_cmd(I2C_CMD_STOP);
        return err;
    }
    for (int i = 0; i < n; i++)
        buf[i] = i2c_read_byte(i == n - 1 ? (I2C_CMD_NACK | I2C_CMD_STOP) : 0);
    return 0;
}

/* ----------------------------------------------------------------- SPI */
static inline void spi_init(uint32_t mode_flags, uint32_t clkdiv)
{
    REG(SPI_BASE, SPI_CTRL)   = mode_flags;
    REG(SPI_BASE, SPI_CLKDIV) = clkdiv;
}

static inline void spi_select(uint32_t cs_mask) { REG(SPI_BASE, SPI_CS) = cs_mask; }

static inline uint8_t spi_xfer(uint8_t b)
{
    REG(SPI_BASE, SPI_DATA) = b;
    while (REG(SPI_BASE, SPI_STATUS) & SPI_BUSY)
        ;
    return (uint8_t)REG(SPI_BASE, SPI_DATA);
}

#endif
