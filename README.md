# RISC-V Pipeline (Verilog)

A 5-stage in-order RV32I CPU (IF, ID, EX, MEM, WB) with forwarding, a
load-use interlock and branch resolution in EX, plus a small SoC with GPIO,
UART, I2C and SPI peripherals and a self-checking testbench. Written in plain Verilog-2005; simulates with
Icarus Verilog and lints clean with Verilator `-Wall`.

See [docs/REPORT.md](docs/REPORT.md) for the review of the original code,
the list of fixes, and the verification approach, and
[docs/PERIPHERALS.md](docs/PERIPHERALS.md) for how the peripherals work,
their register maps and how they are tested.

## Layout

| Path | Contents |
|------|----------|
| `rtl/rv32i_core.v` | The pipeline (top of the CPU) |
| `rtl/decoder.v` | Instruction decode, immediates, control signals |
| `rtl/alu.v`, `rtl/branch_unit.v` | ALU and branch comparator |
| `rtl/hazard_unit.v` | Forwarding and load-use stall |
| `rtl/reg_file.v` | 32 x 32 register file |
| `rtl/dp_ram.v` | Dual-port block RAM (instruction + data ports) |
| `rtl/soc_top.v` | Core + RAM + peripherals + address decode |
| `rtl/periph/` | GPIO, UART, I2C master, SPI master, FIFO |
| `rtl/fpga/fpga_top.v` | Board wrapper: I/O pads, reset synchroniser |
| `rtl/rv32i_defs.vh` | Shared opcode / ALU constants |
| `tb/tb_soc.v` | System testbench: lockstep against a reference model |
| `tb/rv32i_ref_model.v` | Instruction-level RV32I reference model |
| `tb/tb_units.v` | Unit tests for ALU, branch unit, immediates |
| `tb/tb_periph.v` | Register-level tests of the peripherals |
| `tb/models/` | UART terminal, I2C slave and SPI slave models |
| `sw/tests/*.S` | Directed self-checking assembly tests |
| `sw/c/main.c` | C program test (built with GCC) |
| `sw/periph/*_test.c` | Peripheral test programs (GPIO, UART, I2C, SPI) |
| `sw/common/` | Linker script, start-up code, test macros, `soc.h` register map, `periph.h` drivers |
| `sw/build/*.hex` | Pre-built program images (no cross compiler needed to run tests) |
| `tools/gen_random.py` | Random program generator for lockstep testing |
| `tools/bin2hex.py` | Binary to `$readmemh` converter |
| `simulator/` | The original C++ cycle model (not used by the new testbench) |

## Memory map

| Address | Size | Device |
|---------|------|--------|
| `0x0000_0000` | 16 KiB (parameter) | RAM: code, data and stack |
| `0x1000_0000` | 4 KiB | GPIO |
| `0x1000_1000` | 4 KiB | UART |
| `0x1000_2000` | 4 KiB | I2C master |
| `0x1000_3000` | 4 KiB | SPI master |
| `0xF000_0000` | - | `TOHOST`, simulation only: the testbench watches stores here |

The CPU starts executing at `0x0000_0000`.

## Running the tests

Needs `iverilog` (12+) and `python3`. `verilator` is used for lint, and
`riscv64-unknown-elf-gcc` only to rebuild the programs in `sw/`.

```sh
make test                 # unit + directed ISA + C + peripheral + random lockstep tests
make unit                 # ALU / branch / immediate unit tests
make isa                  # directed assembly tests
make ctest                # C program test
make periph               # peripheral tests (register level + firmware on the SoC)
make random SEEDS="1 2 3" COUNT=1000
make lint                 # verilator -Wall
make synth                # Yosys, Xilinx 7-series: LUT/FF per module
make sw                   # rebuild sw/build/*.hex with the cross compiler
make run HEX=sw/build/hazard.hex TRACE=1 VCD=wave.vcd
```

On Ubuntu 24.04 everything installs with
`sudo apt-get install iverilog verilator gcc-riscv64-unknown-elf`.

Each run ends with `TEST PASSED` or `TEST FAILED: <reason>`; failures exit
non-zero so `make` stops.

## Using it on an FPGA

Use `rtl/fpga/fpga_top.v` as the top level: it adds the GPIO and open-drain
I2C pads and a reset synchroniser around `soc_top`. Set `INIT_FILE` to a
`$readmemh` image (such as `sw/build/uart_test.hex`) to preload the RAM and
`CLK_HZ` to the board clock (the UART then starts at 115200 baud and I2C at
100 kHz). The RAM is written so Vivado/Yosys infer true dual-port block
RAM, and the register file maps to distributed RAM. I2C needs pull-ups on
SCL and SDA. See [docs/PERIPHERALS.md](docs/PERIPHERALS.md) section 9.
