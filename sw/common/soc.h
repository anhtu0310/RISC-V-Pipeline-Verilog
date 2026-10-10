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

#endif
