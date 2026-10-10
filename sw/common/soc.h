/* SoC constants shared by assembly and C programs. */
#ifndef SOC_H
#define SOC_H

/* Simulation-only "tohost" register (unmapped in hardware; the testbench
 * watches the data bus for a store here).
 *   1           -> test passed
 *   (n << 1)|1  -> test failed with code n
 */
#define TOHOST_ADDR 0xF0000000

#define RAM_BASE    0x00000000
#define PERIPH_BASE 0x10000000

/* Peripherals: one 4 KiB page each. Register maps are documented in the
 * headers of the rtl/periph sources; C helpers are in periph.h. */
#define GPIO_BASE   0x10000000
#define UART_BASE   0x10001000
#define I2C_BASE    0x10002000
#define SPI_BASE    0x10003000

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

#endif
