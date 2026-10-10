/* UART test. The testbench terminal (tb/models/uart_model.v) runs at 16
 * clocks per bit, logs what it receives and echoes every byte back.
 * Returns 0 on success, else the number of the failing check. */
#include "periph.h"

#define DIV     16
#define TIMEOUT 2000

static const char banner[] = "Hello from RV32I over UART!\n";

int main(void)
{
    uart_init(DIV);
    if (REG(UART_BASE, UART_BAUD_DIV) != DIV)
        return 1;
    if ((REG(UART_BASE, UART_STATUS) & (UART_TX_IDLE | UART_RX_AVAIL)) != UART_TX_IDLE)
        return 2;

    /* Send the banner one character at a time and check the echo. */
    for (const char *p = banner; *p; p++) {
        uart_putc(*p);
        if (uart_getc_timeout(TIMEOUT) != (uint8_t)*p)
            return 3;
    }

    /* Burst: fill the TX FIFO, then collect all echoes (the RX FIFO is
     * as deep as the burst, so nothing is lost). */
    static const char burst[] = "01234567";
    for (int i = 0; i < 8; i++)
        uart_putc(burst[i]);
    for (int i = 0; i < 8; i++)
        if (uart_getc_timeout(TIMEOUT) != burst[i])
            return 4;
    if (REG(UART_BASE, UART_STATUS) & (UART_RX_OVERRUN | UART_FRAME_ERR))
        return 5;

    /* Internal loopback: the terminal's echo arrives on the pin but is
     * ignored while loopback is on. Wait for it before switching back. */
    uart_flush();
    REG(UART_BASE, UART_CTRL) = UART_LOOPBACK;
    uart_putc('Z');
    if (uart_getc_timeout(TIMEOUT) != 'Z')
        return 6;
    for (volatile int i = 0; i < 100; i++)      /* > one frame */
        ;
    REG(UART_BASE, UART_CTRL) = 0;
    if (uart_getc_timeout(50) != -1)
        return 7;                               /* echo must not have been received */

    uart_putc('\n');
    if (uart_getc_timeout(TIMEOUT) != '\n')
        return 8;
    uart_flush();
    return 0;
}
