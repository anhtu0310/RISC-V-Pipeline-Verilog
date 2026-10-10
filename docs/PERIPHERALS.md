# Peripherals: GPIO, UART, I2C and SPI

This document covers Step 2 of the project: adding I/O peripherals to the
RV32I SoC cleaned up in Step 1 (see [REPORT.md](REPORT.md)), extending the
testbench to cover them, and explaining how it all fits together.

**Short version.** Four memory-mapped peripherals now sit in the
`0x1000_0000` window: a 32-pin GPIO with edge latches, an 8N1 UART with
8-byte TX/RX FIFOs, a byte-level I2C master with clock-stretching support,
and an SPI master that supports all four modes, MSB or LSB first, with four
chip selects. Each is a single Verilog file with the same small bus
interface. They are tested at two levels: a register-level testbench (96
checks against behavioural UART, I2C and SPI devices) and four C programs
that run on the CPU and drive real traffic through the pins to the same
models. All 31 test runs pass, the RTL is Verilator `-Wall` clean, and
deliberately injected bugs are caught (section 7). On a Xilinx 7-series
part the four peripherals together cost about 510 LUTs and 420 flip-flops.

---

## 1. Architecture

```
                 +-------------------------- soc_top ---------------------------+
                 |                                                              |
  imem port  +---+------+     dbus (MEM stage)      +--------+                  |
 <---------->| rv32i    |---addr/wdata/wstrb/we/re->| decode |--sel_ram-->  RAM (BRAM, port B)
             | core     |<-----------rdata----------|  +     |--sel_gpio->  gpio.v       <-> gpio pins
             +----------+                           | read   |--sel_uart->  uart.v       <-> tx / rx
                 |                                  |  mux   |--sel_i2c-->  i2c_master.v <-> scl / sda
                 |                                  +--------+--sel_spi-->  spi_master.v <-> sclk/mosi/miso/cs_n
                 +--------------------------------------------------------------+
```

### Memory map

| Base | Device | Source |
|------|--------|--------|
| `0x0000_0000` | RAM, 16 KiB (code, data, stack) | `rtl/dp_ram.v` |
| `0x1000_0000` | GPIO | `rtl/periph/gpio.v` |
| `0x1000_1000` | UART | `rtl/periph/uart.v` |
| `0x1000_2000` | I2C master | `rtl/periph/i2c_master.v` |
| `0x1000_3000` | SPI master | `rtl/periph/spi_master.v` |
| `0xF000_0000` | `TOHOST` (simulation only) | testbench |

Each device owns a 4 KiB page. The decoder in `soc_top.v` matches
`addr[31:16] == 0x1000` and uses `addr[15:12]` to pick the page; inside the
page the peripheral sees `addr[7:2]` (64 word registers, so registers alias
every 256 bytes). Unused pages and offsets read as 0 and ignore writes.

### Bus protocol

The bus is the one Step 1 defined for the core's MEM stage, so nothing in
the CPU changed:

* In the cycle the load/store is in MEM, the core drives `dbus_addr`,
  `dbus_wdata` (already shifted onto the right byte lanes), `dbus_wstrb`,
  and one of `dbus_we` / `dbus_re`.
* A write takes effect at the end of that cycle.
* For a read, the slave **registers** its read data at the end of that
  cycle, and the core picks it up in WB on the next cycle.

Every peripheral therefore has the same port list:

```verilog
input  wire        sel,     // this device is addressed
input  wire        we, re,  // write / read strobe (one cycle)
input  wire [5:0]  addr,    // word offset in the page
input  wire [31:0] wdata,
input  wire [3:0]  wstrb,
output reg  [31:0] rdata    // registered; valid the cycle after sel && re
```

`soc_top` registers which slave a read went to (`rd_sel_q`) together with
the request and uses it to steer the read-data mux in the next cycle. There
are no wait states, so a peripheral access costs the same as a RAM access.

**Reads with side effects.** Reading the UART `DATA` register pops the RX
FIFO. This is safe because a load that reaches MEM is never cancelled in
this pipeline (branches resolve in EX and only flush IF and ID), so every
`dbus_re` is a real, architecturally executed load, issued exactly once.

**Byte access.** All registers are word registers and are best accessed with
`lw`/`sw`. GPIO `DATA_OUT` and `DIR` honour the byte strobes, so `sb`/`sh`
change only the addressed bytes. The other devices only use the low byte(s)
of their registers and take a write when the strobe for that byte is set,
so `sb` to a register's base address also works.

**No interrupts.** The core has no interrupt or CSR support yet (Step 1,
known limitations), so all drivers poll status bits. The status bits are
laid out so that adding an interrupt line per device later is a few lines
(e.g. UART `RX_AVAIL`, GPIO `RISE | FALL`).

---

## 2. GPIO (`rtl/periph/gpio.v`)

Parameter `N` pins (32 in `soc_top`, 16 in the FPGA wrapper). Each pin has
an output value, a direction bit and an input.

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | `DATA_IN` | R | Synchronised pin values |
| `0x04` | `DATA_OUT` | RW | Output values (byte strobes honoured) |
| `0x08` | `DIR` | RW | 1 = output (drives the pin), 0 = input |
| `0x0C` | `OUT_SET` | W | `DATA_OUT \|= wdata` |
| `0x10` | `OUT_CLR` | W | `DATA_OUT &= ~wdata` |
| `0x14` | `OUT_TGL` | W | `DATA_OUT ^= wdata` |
| `0x18` | `RISE` | R / W1C | Rising edges seen since last cleared |
| `0x1C` | `FALL` | R / W1C | Falling edges seen since last cleared |

How it works:

* **Input synchroniser.** Pins are asynchronous to the clock, so each input
  goes through two flip-flops before anything uses it. This avoids
  metastability reaching the CPU, at the cost of two cycles of latency.
* **Atomic set / clear / toggle.** Without them, changing one LED means a
  read-modify-write (`lw`, `or`, `sw`), which is three instructions and
  not safe if an interrupt handler (in the future) touches the same port.
  `OUT_SET`/`OUT_CLR`/`OUT_TGL` do it in one store.
* **Edge latches.** A third flop holds the previous synchronised value;
  `rise = now & ~prev`, `fall = ~now & prev`. Detected edges are OR-ed into
  sticky registers, which software clears by writing 1s. A new edge in the
  same cycle as a clear wins, so no edge is ever lost. A pulse only one
  clock wide is still caught (the register-level test checks exactly that).
* **Pads.** `soc_top` exposes `gpio_out`, `gpio_oe` and `gpio_in`
  separately. `rtl/fpga/fpga_top.v` turns them into real bidirectional
  pins: `assign gpio[i] = gpio_oe[i] ? gpio_out[i] : 1'bz`. Reading
  `DATA_IN` on an output pin returns the pin's actual level, which is handy
  for spotting a shorted pin.

---

## 3. UART (`rtl/periph/uart.v`)

8 data bits, no parity, 1 stop bit (8N1), LSB first, with an 8-entry FIFO
on each side (`sync_fifo.v`, parameter `FIFO_DEPTH`).

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | `DATA` | W | Push `wdata[7:0]` into the TX FIFO (dropped if full) |
| | | R | Pop the RX FIFO: `[7:0]` byte, `[31]` = 1 if it was empty |
| `0x04` | `STATUS` | R | `[0]` TX_FULL `[1]` TX_EMPTY `[2]` TX_IDLE `[3]` RX_AVAIL `[4]` RX_FULL `[5]` RX_OVERRUN `[6]` FRAME_ERR |
| | | W | Write 1 to bit 5 / 6 to clear those sticky flags |
| `0x08` | `BAUD_DIV` | RW | Clock cycles per bit (16 bits, >= 4) |
| `0x0C` | `CTRL` | RW | `[0]` LOOPBACK: RX listens to the TX line internally |

`BAUD_DIV` resets to `CLK_HZ / UART_BAUD` (868 for 115200 baud at 100 MHz;
both are `soc_top` parameters).

**Transmitter.** When the shifter is idle and the TX FIFO is not empty, it
pops a byte, drives the start bit (0) and loads `{1, byte}` into a 9-bit
shift register. Every `BAUD_DIV` clocks it shifts the next bit out; after 8
data bits the stop bit (1) comes out of the top of the register, and after
one more bit time the shifter is free again. `TX_IDLE` means "FIFO empty
and the last stop bit is finished", which is what software waits for
before, say, turning the transmitter off.

**Receiver.** The input passes a two-flop synchroniser. In idle the
receiver waits for a 0 (the start bit's falling edge), waits half a bit
time and checks the line is *still* 0; a shorter glitch is ignored. From
there it samples each data bit and the stop bit in the middle of the bit
(every `BAUD_DIV` clocks), which gives the most tolerance to baud-rate
mismatch (roughly ±4% between the two ends). If the stop bit is 0 the byte is
dropped and `FRAME_ERR` is set; if the RX FIFO is full the byte is dropped
and `RX_OVERRUN` is set.

**Reading `DATA`** returns the FIFO head and pops it in the same access.
Bit 31 tells software the FIFO was empty, so one load is enough for a
non-blocking "get character" (no need to read `STATUS` first).

**Loopback** routes the TX line into the receiver inside the chip, so
software can test the UART without anything connected.

---

## 4. I2C master (`rtl/periph/i2c_master.v`)

A single-master I2C controller with a byte-level command interface. The
CPU does not bit-bang anything; it tells the controller what to do for one
byte at a time and polls `BUSY`.

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | `PRESCALE` | RW | SCL timing (16 bits), see below |
| `0x04` | `TXDATA` | RW | Byte for the next WRITE |
| `0x08` | `RXDATA` | R | Byte from the last READ |
| `0x0C` | `CMD` | W | `[0]` START `[1]` STOP `[2]` WRITE `[3]` READ `[4]` NACK (answer the READ with NACK) |
| `0x10` | `STATUS` | R | `[0]` BUSY `[1]` NACK (slave did not ACK the last WRITE) `[2]` BUS_ACTIVE (between START and STOP) |

One `CMD` write can combine parts; they run in the order
START, then WRITE or READ, then STOP. For example, reading register `r` of
device `d`:

```
TXDATA = d<<1 | 0;   CMD = START | WRITE       ; address, write
TXDATA = r;          CMD = WRITE               ; register number
TXDATA = d<<1 | 1;   CMD = START | WRITE       ; repeated START, address, read
                     CMD = READ | NACK | STOP  ; last (only) byte
value = RXDATA
```

`sw/common/periph.h` wraps this as `i2c_write_regs()` / `i2c_read_regs()`.

**Open drain.** I2C lines are wired-AND: devices only ever pull SCL/SDA low
or let go, and a pull-up resistor makes them high. So the controller has
`scl_oe`/`sda_oe` outputs (1 = pull low) and `scl_i`/`sda_i` inputs that
read the real line level. `fpga_top.v` makes the pads:
`assign i2c_sda = sda_oe ? 1'b0 : 1'bz`.

**Bit engine.** Every bus action is four phases, each `PRESCALE + 1` clocks:

| Action | Phase 0 | Phase 1 | Phase 2 | Phase 3 |
|--------|---------|---------|---------|---------|
| START (or repeated START) | release SDA | release SCL | **SDA low** while SCL high | SCL low |
| data / ACK bit | SCL low, put bit on SDA | release SCL | SCL high; **sample SDA** at the end | SCL low |
| STOP | SCL low, SDA low | release SCL | **release SDA** while SCL high | bus free time |

SDA only changes in phase 0 (SCL low), except for START and STOP, which by
definition change SDA while SCL is high. A byte is 9 bits: 8 data bits MSB
first plus the ACK bit. For a WRITE the controller releases SDA in the ACK
slot and samples the slave's ACK into `STATUS.NACK`; for a READ it releases
SDA for the 8 data bits and then drives ACK (or NACK if the command said
so; the last byte of a read must be NACKed).

**Clock stretching.** A slave that needs more time holds SCL low after the
master releases it. In phase 1 the timer does not run until SCL is really
seen high, so the controller waits for as long as the slave stretches and
the high time is always the full length. The test devices stretch the
clock after every ACK.

**Timing.** Because SCL goes through a 2-flop synchroniser before phase 1
can see it high, one bit takes `4 * (PRESCALE + 1) + 3` clocks:
`f_SCL = f_clk / (4 * (PRESCALE + 1) + 3)`. `PRESCALE` resets to
`CLK_HZ / (4 * I2C_HZ) - 1` = 249 for 100 kHz at 100 MHz (99.7 kHz in
practice); 61 gives about 400 kHz.

**Between commands** the controller keeps SCL low (the bus stays owned and
slaves simply wait), so software can take as long as it likes between
bytes.

---

## 5. SPI master (`rtl/periph/spi_master.v`)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x00` | `CTRL` | RW | `[0]` CPOL `[1]` CPHA `[2]` LSB_FIRST (change while idle) |
| `0x04` | `CLKDIV` | RW | SCLK half period = `CLKDIV + 1` clocks (16 bits) |
| `0x08` | `CS` | RW | `[3:0]` 1 = assert that chip select (pin low) |
| `0x0C` | `DATA` | W | Start an 8-bit transfer of `wdata[7:0]` (ignored while busy) |
| | | R | Byte received by the last transfer |
| `0x10` | `STATUS` | R | `[0]` BUSY |

`f_SCLK = f_clk / (2 * (CLKDIV + 1))`, so 50 MHz down to about 760 Hz at a
100 MHz clock.

**Modes.** SPI has four modes made of two bits:

* **CPOL** is the clock's idle level. The controller holds SCLK at CPOL
  whenever it is not transferring.
* **CPHA** says on which edge data is sampled. With CPHA = 0, both sides
  put the first bit out before the first edge, *sample on the leading
  edge* and change data on the trailing edge. With CPHA = 1 they change
  data on the leading edge and *sample on the trailing edge*.

The engine counts SCLK edges 0 to 15 (16 edges = 8 clock pulses). Even
edges are leading edges, odd ones trailing. On each edge it either samples
MISO into the receive register (`edge[0] == CPHA`) or shifts the next bit
onto MOSI. For CPHA = 1 the very first leading edge does not shift: the
first bit is already on MOSI. Half a period after the 16th edge, the
received byte is copied to `DATA` and `BUSY` drops. MOSI is always the top
bit of the transmit shift register; LSB-first mode simply bit-reverses the
byte on the way in and the received byte on the way out.

**Chip selects** are plain register bits rather than toggled automatically
per byte. Most SPI devices (flash, ADCs, displays) need CS held low across
a multi-byte command such as "read, address, data...", so software asserts
CS, transfers as many bytes as it needs and releases it.

---

## 6. Software support

* `sw/common/soc.h`: base addresses, register offsets and bit names, usable
  from C and assembly.
* `sw/common/periph.h`: small polling drivers as `static inline` functions:
  `gpio_*`, `uart_init/putc/getc_timeout/flush`, `i2c_init/cmd/write_byte/
  read_byte/write_regs/read_regs`, `spi_init/select/xfer`.
* `sw/periph/*_test.c`: one test program per peripheral. They are built
  with the same `crt0.S` and `link.ld` as the Step 1 C test and report
  through `TOHOST` (0 = pass, otherwise the number of the failed check).
* `sw/build/*_test.hex`: pre-built images, so the tests run without a
  RISC-V compiler. CI rebuilds them and fails if they differ.

Example: echo characters from the UART and mirror them on the LEDs.

```c
#include "periph.h"

int main(void)
{
    uart_init(868);                 /* 115200 baud at 100 MHz */
    gpio_set_dir(0xff);
    for (;;) {
        int c = uart_getc_timeout(1000000);
        if (c >= 0) {
            gpio_write(c);
            uart_putc(c);
        }
    }
}
```

---

## 7. Verification

### 7.1 Behavioural models of the outside world (`tb/models/`)

| Model | What it does | What it checks |
|-------|--------------|----------------|
| `uart_model.v` | Terminal: receives from the SoC's TX, logs text lines, optionally echoes every byte back; tasks to send good frames, frames with a bad stop bit, and short glitches | Framing of every byte the SoC sends |
| `i2c_slave_model.v` | 256-byte register file / EEPROM with a pointer: write `ptr, data...`, read sequentially; does not ACK other addresses; optional clock stretching after each ACK | Counts START/STOP and bytes so tests can check the framing |
| `spi_slave_model.v` | Fixed-mode slave (CPOL/CPHA parameters), MSB first; answers the first byte after CS with its ID and then echoes the previous byte; drives MISO only while selected | SCLK must be at its idle level when CS falls; CS must not rise in the middle of a byte |

The models are written independently from the RTL, from the protocol
definitions, so the RTL and the model cannot share the same mistake.

### 7.2 Register-level testbench (`tb/tb_periph.v`, `make periph-unit`)

Drives each peripheral through its bus port with the same timing as the
core and checks 96 things, including:

* **GPIO:** reset values, `DIR`/`DATA_OUT`, byte and half-word writes,
  `SET`/`CLR`/`TGL`, the input synchroniser, a one-clock pulse caught by
  `RISE`, `FALL`, write-1-to-clear, unused offsets.
* **UART:** bit timing on the wire, TX FIFO full (11 bytes written, 9 sent),
  RX of 0x00/0xFF/0xA5, empty-read flag, RX FIFO overrun (9 bytes into 8),
  framing error, a glitch shorter than half a bit rejected, an odd divider
  (13) on both sides, internal loopback.
* **I2C:** write 3 bytes and read them back through a repeated START on the
  clock-stretching device, checking the slave's memory and that stretching
  really happened; a second device without stretching; NACK on an absent
  address; SCL period against the formula; lines released after STOP.
* **SPI:** all four modes against four slaves (16 SCLK edges per byte, SCLK
  idle level per CPOL, chip-select pins, ID + echo data both ways), LSB
  first, the fastest divider (0) and the exact transfer length in clocks.

### 7.3 Firmware on the SoC (`tb/tb_soc.v`, `make periph-sw`)

`tb_soc.v` now connects the SoC's pins to a small "board": GPIO pins 7:0
are wired back to pins 31:24 and pins 23:16 read 0xA5; a UART terminal at
16 clocks per bit echoes everything; the two I2C devices sit on a
pulled-up open-drain bus; one SPI slave per chip select, CS *n* in mode *n*.
Each C test runs on the CPU with the full Step 1 checking still active
(every retired instruction compared against the reference model; loads
from peripherals take the RTL's value, since the model has no peripherals)
and reports pass or fail through `TOHOST`:

| Program | What it does |
|---------|--------------|
| `gpio_test.c` | Pad readback and external loopback, set/clear/toggle, rise and fall latches with W1C, byte store to `DATA_OUT`, counting 5 short pulses with the edge latch |
| `uart_test.c` | Sends "Hello from RV32I over UART!" a character at a time and checks each echo; an 8-byte burst through both FIFOs; loopback mode, and that the external echo is ignored while it is on. The testbench also checks that the banner arrived on the wire (`+UART_EXPECT`) |
| `i2c_test.c` | Writes 4 bytes to device 0x50 (clock stretching), reads 6 back across the written range with a repeated START, reads device 0x51, and checks the NACK from an absent address |
| `spi_test.c` | For modes 0..3, with a different clock divider each, sends 4 bytes and checks the slave's ID plus the echoes; then LSB-first mode |

The testbench additionally fails a run if the UART terminal saw a framing
error or an SPI slave saw a protocol error, whatever the program reported.

### 7.4 Do the tests catch bugs?

Each of these bugs was injected into the RTL one at a time, and the test
suites were run (pass = the bug was **not** caught):

| Injected bug | `tb_periph` | firmware tests |
|--------------|-------------|----------------|
| UART TX sends bit n+1 instead of bit n | caught | `uart_test` caught |
| UART RX samples at the bit edge instead of the middle | caught | not caught (ideal timing in simulation) |
| SPI ignores CPHA | caught | `spi_test` caught |
| I2C ignores clock stretching | caught | not caught |
| I2C ignores the slave's NACK | caught | `i2c_test` caught |
| GPIO edge latch not sticky | caught | `gpio_test` caught |
| SPI decoded at the wrong page in `soc_top` | n/a | `spi_test` caught |

Every injected bug was caught by at least one suite, which is why both
levels exist: the register-level tests reach timing corner cases that
firmware cannot easily create, and the firmware tests check the
integration (decode, read mux, drivers).

### 7.5 Results

`make test` (CI runs it with 20 random seeds):

| Suite | Runs | Result |
|-------|------|--------|
| Unit tests (ALU, branch, immediates) | 1 (47,152 checks) | pass |
| Directed ISA tests | 4 | pass |
| C test | 1 | pass |
| Peripheral register-level tests | 1 (96 checks) | pass |
| Peripheral firmware tests | 4 | pass |
| Random lockstep tests | 20 | pass |

`make lint`: Verilator `-Wall`, no warnings, for both `soc_top` and
`fpga_top`.

Cycle counts for the firmware tests (100 MHz in simulation): GPIO 339,
SPI 1,179, I2C 5,073, UART 12,487 (dominated by waiting for characters at
16 clocks per bit).

---

## 8. FPGA resources

`make synth` maps `fpga_top` (16 GPIO pins) to a Xilinx 7-series part with
Yosys (`synth_xilinx`). Per module:

| Block | LUT | FF | Other |
|-------|-----|----|-------|
| CPU core (core, ALU, decoder, branch, hazard, register file) | 1,222 | 408 | 44 LUTRAM (register file) |
| RAM 16 KiB | 4 | 0 | 4 x RAMB36 |
| SoC decode and read mux | 92 | 5 | |
| GPIO (16 pins) | 104 | 128 | |
| UART (incl. two 8-byte FIFOs) | 215 | 116 | 4 LUTRAM |
| I2C master | 105 | 94 | |
| SPI master | 82 | 86 | |

The four peripherals add about 510 LUTs and 420 flip-flops, roughly 40% of
the CPU's LUTs. Most of the flip-flops are the 16-bit divider/prescaler
counters and the GPIO synchronisers and edge latches. The FIFOs map to
distributed RAM (`RAM32M`), not flip-flops. These are Yosys numbers;
Vivado usually comes out somewhat smaller.

---

## 9. Using it on a board

`rtl/fpga/fpga_top.v` wraps `soc_top` with:

* a reset synchroniser (asynchronous assert, synchronous release) for an
  active-low reset button;
* bidirectional GPIO pads (`inout gpio[GPIO_N-1:0]`);
* open-drain I2C pads (`inout i2c_scl, i2c_sda`), which need pull-ups
  (2.2 to 4.7 kOhm on the board, or the FPGA's internal pull-ups for short
  wires at 100 kHz);
* plain UART and SPI pins.

Set `INIT_FILE` to a program image (`sw/build/uart_test.hex` or your own),
`CLK_HZ` to the board clock, and map the ports in the constraint file. With
`CLK_HZ` set correctly the UART starts at 115200 baud and I2C at 100 kHz
without any software set-up.

---

## 10. Files added or changed

| File | Change |
|------|--------|
| `rtl/periph/gpio.v`, `uart.v`, `i2c_master.v`, `spi_master.v`, `sync_fifo.v` | New peripherals |
| `rtl/soc_top.v` | Peripheral decode, read mux, I/O ports, `CLK_HZ`/`UART_BAUD`/`I2C_HZ`/`GPIO_N` parameters |
| `rtl/fpga/fpga_top.v` | New board-level wrapper |
| `tb/models/*.v` | New UART, I2C, SPI device models |
| `tb/tb_periph.v` | New register-level testbench |
| `tb/tb_soc.v` | Board models on the SoC pins, `+UART_EXPECT`, model error checks |
| `sw/common/soc.h`, `sw/common/periph.h` | Register map and drivers |
| `sw/periph/*_test.c`, `sw/build/*_test.hex` | Firmware tests and their images |
| `Makefile` | `periph`, `periph-unit`, `periph-sw`, `synth` targets; lint of `fpga_top` |
| `tools/synth_summary.py` | LUT/FF table from the Yosys report |

---

## 11. Limitations and next steps

* **No interrupts.** Everything is polled because the core has no trap
  support. Adding `mtvec`/`mie`/`mip` and an external interrupt input to
  the core would let the UART RX and GPIO edges raise interrupts.
* **I2C** is single-master: no arbitration-lost detection, and no slave
  mode. 10-bit addressing works by sending the two address bytes as
  WRITEs.
* **SPI** transfers are 8 bits at a time with no FIFO, so the CPU polls per
  byte; at the fastest divider the polling loop, not the bus, is the limit.
  A TX/RX FIFO or a DMA engine would be the next step for SD cards or
  displays.
* **UART** has fixed 8N1 framing (no parity, no 2 stop bits) and no
  hardware flow control.
* The peripheral page decode only looks at `addr[7:2]`, so registers alias
  inside each 4 KiB page.
