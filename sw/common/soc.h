/* SoC constants shared by assembly and C programs. */
#ifndef SOC_H
#define SOC_H

/* Simulation-only "tohost" register (unmapped in hardware; the testbench
 * watches the data bus for a store here).
 *   1           -> test passed
 *   (n << 1)|1  -> test failed with code n
 */
#define TOHOST_ADDR 0xF0000000

/* Simulation-only marker: tb_soc prints the cycle count for every store
 * here ("[mark] <value> at cycle <n>"), used to time code sections. */
#define MARK_ADDR   0xF0000004

#define RAM_BASE    0x00000000
#define PERIPH_BASE 0x10000000

/* Peripherals: one 4 KiB page each. Register maps are documented in the
 * headers of the rtl/periph sources; C helpers are in periph.h. */
#define GPIO_BASE   0x10000000
#define UART_BASE   0x10001000
#define I2C_BASE    0x10002000
#define SPI_BASE    0x10003000
#define AES_BASE    0x10004000

/* GPIO */
#define GPIO_DATA_IN    0x00
#define GPIO_DATA_OUT   0x04
#define GPIO_DIR        0x08
#define GPIO_OUT_SET    0x0C
#define GPIO_OUT_CLR    0x10
#define GPIO_OUT_TGL    0x14
#define GPIO_RISE       0x18
#define GPIO_FALL       0x1C

/* UART */
#define UART_DATA       0x00
#define UART_STATUS     0x04
#define UART_BAUD_DIV   0x08
#define UART_CTRL       0x0C

#define UART_TX_FULL    (1u << 0)
#define UART_TX_EMPTY   (1u << 1)
#define UART_TX_IDLE    (1u << 2)
#define UART_RX_AVAIL   (1u << 3)
#define UART_RX_FULL    (1u << 4)
#define UART_RX_OVERRUN (1u << 5)
#define UART_FRAME_ERR  (1u << 6)
#define UART_RX_EMPTY   (1u << 31)   /* in a DATA read */
#define UART_LOOPBACK   (1u << 0)    /* CTRL */

/* I2C */
#define I2C_PRESCALE    0x00
#define I2C_TXDATA      0x04
#define I2C_RXDATA      0x08
#define I2C_CMD         0x0C
#define I2C_STATUS      0x10

#define I2C_CMD_START   (1u << 0)
#define I2C_CMD_STOP    (1u << 1)
#define I2C_CMD_WRITE   (1u << 2)
#define I2C_CMD_READ    (1u << 3)
#define I2C_CMD_NACK    (1u << 4)
#define I2C_BUSY        (1u << 0)
#define I2C_NACKED      (1u << 1)
#define I2C_BUS_ACTIVE  (1u << 2)

/* SPI */
#define SPI_CTRL        0x00
#define SPI_CLKDIV      0x04
#define SPI_CS          0x08
#define SPI_DATA        0x0C
#define SPI_STATUS      0x10

#define SPI_CPOL        (1u << 0)
#define SPI_CPHA        (1u << 1)
#define SPI_LSB_FIRST   (1u << 2)
#define SPI_BUSY        (1u << 0)

/* AES-128 accelerator */
#define AES_CTRL        0x00
#define AES_STATUS      0x04
#define AES_CMD         0x08
#define AES_BLOCKS      0x0C
#define AES_KEY0        0x10    /* KEY0..3 at 0x10, 0x14, 0x18, 0x1C */
#define AES_DIN0        0x20    /* DIN0..3 at 0x20 .. 0x2C */
#define AES_DOUT0       0x30    /* DOUT0..3 at 0x30 .. 0x3C, DOUT3 read pops */

#define AES_AUTO_START  (1u << 0)    /* CTRL */
#define AES_START       (1u << 0)    /* CMD */
#define AES_CLEAR       (1u << 1)
#define AES_READY       (1u << 0)    /* STATUS */
#define AES_OUT_VALID   (1u << 1)
#define AES_BUSY        (1u << 2)
#define AES_OVERFLOW    (1u << 3)
#define AES_OUT_COUNT(s)  (((s) >> 8) & 0x1f)
#define AES_IN_FLIGHT(s)  (((s) >> 16) & 0xf)
#define AES_PIPELINED   (1u << 31)

#endif
