# RISC-V pipeline: review and clean-up report

This report covers Step 1 of the project: reviewing the original
`src/` implementation, fixing what was wrong, restructuring the code, and
replacing the testbench with a self-checking one.

**Short version.** The original pipeline had the right overall structure
(5 stages, forwarding, load-use stall, branches resolved in EX) but it did
not compile in standard open-source tools, its simulation result depended on
event ordering, loads/stores of bytes and half-words were wrong, writes to
`x0` could be forwarded, and the testbench could not tell a pass from a
fail. The core has been rewritten around the same micro-architecture with
those bugs fixed, BRAM-friendly memories, a clean bus interface for
peripherals, and a testbench that checks every retired instruction against
a reference model.

---

## 1. What was wrong in the original code

Severity: **High** = wrong results on real programs, **Medium** = wrong in
some cases / tool-dependent, **Low** = style, maintainability, performance.

| # | Sev. | Where (original) | Problem |
|---|------|------------------|---------|
| 1 | High | `data_mem.v` (`data_mem_w_ctrl`) | Memory was an array of 32-bit words indexed directly by the **byte** address, so `0x400` and `0x401` were two different words. Byte/half stores did not write into a lane of the word, and loads ignored `addr[1:0]`. |
| 2 | High | `data_mem.v` | `SB` wrote `{7'h0, data[7:0]}` (a 15-bit value) to the whole word, wiping the other three bytes; `SH` always wrote the low half. |
| 3 | High | `Inst_decoder.v` | Immediate logic was in `always @(instr)` but used `opcode`, a separate continuous assignment. When `instr` changes the block can run before `opcode` updates, so the immediate is built with the *previous* instruction's format. In Icarus this happens on every instruction (e.g. `li x1, 0x400` loaded `0xdeadbeef`). Synthesis ignores sensitivity lists, so simulation and hardware disagreed. |
| 4 | High | `fwd_and_branch_hazzard.v` (`fwd_unit`) | Forwarding did not check `rd != x0`. `add x0, x7, x7` followed by `add x8, x0, x0` gave `x8 = 0x14` instead of 0. |
| 5 | High | `Pipeline_architechture.v`, `instr_mem.v` | Did not compile in Icarus or Verilator: a port declared as `wire [1:0]` with no direction in the ANSI port list, and a parameter named `program` (a SystemVerilog keyword). `fwd_tb` instantiated a non-existent `forwarding_unit`, so compiling the whole directory failed. |
| 6 | Med | `pipeline_reg.v`, `reg_file.v` | Blocking assignments (`=`) in clocked `always` blocks. Each pipeline register reads signals computed from other registers updated on the same edge, which is a classic simulation race; correctness then depends on the simulator's scheduling order. |
| 7 | Med | `pipeline_reg.v` | `always @(posedge clk or negedge rst_n) if (~rst_n \|\| clear)` mixes a synchronous clear into the asynchronous-reset condition. This is not a valid flip-flop template; synthesis tools either reject it or build something that does not match simulation. |
| 8 | Med | `PC.v` | PC reset to `0xFFFFFFFC`, so the first fetch read outside the instruction memory (X in simulation). |
| 9 | Med | `instr_mem.v`, `data_mem.v` | Addresses were not masked to the memory size: any access beyond 256 bytes (instructions) or 2048 words (data) returned X. Instruction memory was only 256 bytes. |
| 10 | Med | `control_unit.v` + datapath | `JALR` did not clear bit 0 of the target address as the ISA requires. |
| 11 | Low | `fwd_and_branch_hazzard.v` (`hazard_unit`) | Load-use detection compared `rs2` even for instructions that have no `rs2` (I-type, loads, `LUI`, `JAL`...) and did not exclude `x0`, causing unnecessary stalls. |
| 12 | Low | `Inst_decoder.v` | `rd` was driven by two `assign` statements (multiple drivers; Verilator rejects this). |
| 13 | Low | Whole design | Memories were asynchronous-read arrays, so on an FPGA they become LUTs/distributed RAM instead of block RAM, and the 2048-word data memory would use a lot of fabric. |
| 14 | Low | `Pipeline_architechture.v` | About 60 debug signals were top-level output ports; `reg_wr_en_3` was never declared (implicit net). Dead code: the single-cycle `main` (`architecture.v`), `instr_mem_old`, `data_mem`, `PC_reg`, `Counter_add_4`, large commented-out blocks; testbenches mixed into RTL files; unused `clk`/`rst_n` on the controller; file-name typos (`branh_`, `hazzard`, `architechture`). |
| 15 | Low | Decoder/controller | No handling of `FENCE`, `ECALL`/`EBREAK`, or illegal encodings (some illegal `funct7` values silently executed as other instructions). |

### The original testbench

`pipeline_tb` compared the entire register file every cycle with
`reg_dbg.mem`, a file produced by the C++ cycle model in `simulator/`.

* `reg_dbg.mem` was generated for `program_old.mem`, but the instruction
  memory loads `program.mem`, so every cycle reported `INCORRECT OUPUT`.
* Being cycle-exact, any change to pipeline timing (an extra stall, a fix)
  breaks the reference, and the reference itself shares the RTL's bugs.
* No pass/fail summary, no `$finish`, and the check ran `#1` after an
  `always @(data_out)`, which is itself racy.
* Nothing checked memory contents, and only one hand-written program was run.

### Evidence

Bugs 1, 3 and 4 were reproduced on the original RTL with Icarus Verilog
using a 14-instruction program (`sw x2, 0x400; sb x3, 0x401; lw x4, 0x400;
add x0, x7, x7; add x8, x0, x0; lh x9, 0x402`):

```
original              : x1=deadbeef (expected 00000400)          <- bug 3
with bug 3 patched    : x4=11223344 (expected 1122aa44)          <- bugs 1/2
                        mem[1025]=000000aa (byte landed in another word)
                        x9=xxxxxxxx (expected 00001122)          <- bug 1
                        x8=00000014 (expected 00000000)          <- bug 4
```

---

## 2. What was changed

The micro-architecture is the same as before (classic 5-stage pipeline,
forwarding into EX, one-cycle load-use bubble, branches/jumps resolved in EX
with a 2-instruction flush). Everything was rewritten for correctness and
clarity, with these improvements:

### Correctness

* **Byte-addressable data path.** The core now drives a byte address, a
  4-bit write strobe and lane-shifted write data (`SB` replicates the byte to
  all lanes, `SH` the half-word). Loads shift and sign/zero-extend by
  `addr[1:0]` in WB. Fixes 1 and 2.
* **Purely combinational logic uses `always @(*)`** and every clocked block
  uses non-blocking assignments. Fixes 3 and 6.
* **x0 is never forwarded** and never written; the register file bypass and
  both forwarding paths check `rd != 0`. Fix 4.
* **Proper reset style.** Only control/valid bits have an asynchronous reset;
  datapath registers have no reset (everything downstream is qualified by a
  per-stage `valid` bit). Flushes clear the `valid` bit synchronously. Fix 7.
* **PC resets to `RESET_ADDR` (parameter, default 0).** Fix 8.
* **`JALR` clears bit 0** and uses a dedicated target adder. Fix 10.
* **Decoder** flags illegal encodings (wrong `funct7`/`funct3`) and turns
  them into NOPs; `FENCE`/`ECALL`/`EBREAK` retire as NOPs. Fix 15.

### Structure and FPGA friendliness

* **Valid bit per stage.** Bubbles and flushes are explicit, which also
  makes the retirement trace exact.
* **Load-use stall only when needed:** the decoder reports whether an
  instruction really reads `rs1`/`rs2`, and `x0` is excluded. Fix 11.
* **Synchronous-read memories** (`dp_ram.v`). The instruction word comes
  straight out of the RAM's output register into ID, and load data arrives
  in WB, so both memories map onto block RAM **without adding any pipeline
  stage or extra stalls**. During a stall the instruction RAM's read enable
  is dropped so the instruction in ID is held.
* **Unified code/data RAM.** One true dual-port block RAM holds code, data
  and stack (port A fetches, port B serves loads/stores), so a normal GCC
  linker script works and constants in `.rodata` are readable. 16 KiB by
  default (`RAM_ADDR_WIDTH`).
* **Register file without reset**, with an `initial` power-up value, so it
  maps to distributed RAM (12 `RAM32M` on Xilinx) instead of 1024 flip-flops.
* **Clean core boundary.** `rv32i_core` has an instruction port, a data bus
  and an optional retirement trace; `soc_top` holds memories and address
  decode. The debug port soup is gone.
* **Cleanup.** Dead modules, commented-out code and in-file testbenches
  removed; constants shared through `rv32i_defs.vh`; consistent naming;
  Verilator `-Wall` lint is clean (Fixes 5, 12, 14).

Synthesis sanity check with Yosys `synth_xilinx` (not Vivado; numbers are
indicative): the core is about 1,150 LUTs and 410 flip-flops, and the 16 KiB
RAM infers 4 `RAMB36E1`.

### File mapping

| Original | New |
|----------|-----|
| `Pipeline_architechture.v`, `pipeline_reg.v`, `PC.v`, `muxes.v` | `rtl/rv32i_core.v` (pipeline registers and muxes are inline) |
| `Inst_decoder.v`, `control_unit.v` | `rtl/decoder.v` |
| `ALU.v` | `rtl/alu.v` |
| `branh_comparator.v` | `rtl/branch_unit.v` |
| `fwd_and_branch_hazzard.v` | `rtl/hazard_unit.v` |
| `reg_file.v` | `rtl/reg_file.v` |
| `instr_mem.v`, `data_mem.v` | `rtl/dp_ram.v` + `rtl/soc_top.v` |
| `architecture.v` (single-cycle) | removed (still in git history) |
| `program*.mem`, `reg_dbg.mem` | replaced by `sw/` sources and `sw/build/*.hex` |

The C++ model in `simulator/` was left untouched; the new testbench does not
use it.

---

## 3. The new testbench

### How it checks

`tb/tb_soc.v` runs a program image on `soc_top` and checks it in two ways:

1. **Lockstep against a reference model.** `tb/rv32i_ref_model.v` is an
   instruction-level RV32I model with its own registers and RAM. Every time
   the pipeline retires an instruction (the core's `trace_*` port), the model
   executes one instruction and the testbench compares the PC, the
   instruction word, and the destination register and value. A forwarding,
   stall or flush bug is reported at the exact instruction it corrupts. At
   the end the whole RAM is compared with the model's RAM too.
2. **Program result.** Programs store to `TOHOST` (`0xF000_0000`): `1` means
   pass, `(n << 1) | 1` means internal check `n` failed.

It prints cycles, retired instructions and CPI, then `TEST PASSED` or
`TEST FAILED: <reason>` (non-zero exit). A timeout also fails.

### Test suites

| Suite | What it covers |
|-------|----------------|
| `make unit` (`tb/tb_units.v`) | ALU (all ops, corner values + 2,000 random vectors each), branch unit (all conditions), immediate decoding for I/S/B/U/J formats. 47,152 checks. |
| `sw/tests/alu.S` | All register-register and immediate ALU instructions, `LUI`, `AUIPC`, writes to `x0`. |
| `sw/tests/branch.S` | All six branches taken/not-taken incl. signed/unsigned edges, loops, squashing after taken branches, `JAL`/`JALR` link values, `JALR` bit-0 clear, `rd == rs1`. |
| `sw/tests/mem.S` | Every load/store width at every byte offset, sign/zero extension, byte lanes not clobbered, store-then-load, unmapped reads. |
| `sw/tests/hazard.S` | Forwarding at distances 1-3, both operands, youngest-producer priority, `x0` never forwarded, load-use on `rs1`/`rs2`/store data/load address/branch/`JALR`, flushes during would-be stalls, back-to-back jumps. |
| `sw/c/main.c` | C program compiled with GCC `-O2`: CRC-32, software multiply, insertion sort on `int16_t`, recursion, volatile memory. |
| `make random` (`tools/gen_random.py`) | Random programs (default 600 blocks, about 550 retired instructions each) with dense register dependencies, loads/stores of all widths, forward branches/`JAL`/`AUIPC+JALR`, writes to `x0`, `FENCE`. Checked only by the lockstep model, so the program needs no expected values. |

### Results

All suites pass. A long regression of 61 random seeds x 1,500 blocks
(about 73,000 retired instructions) also passes.

| Program | Cycles | Retired | CPI |
|---------|-------:|--------:|----:|
| alu.S | 278 | 272 | 1.02 |
| branch.S | 192 | 138 | 1.39 |
| mem.S | 165 | 159 | 1.04 |
| hazard.S | 147 | 124 | 1.19 |
| C test | 17,667 | 15,054 | 1.17 |
| random (typical) | ~690 | ~550 | ~1.25 |

### Does the testbench actually catch bugs?

To check, ten bugs were injected into the new RTL one at a time and the
suites re-run. Every one was caught by several suites (random = seeds 1-3):

| Injected bug | unit | alu | branch | mem | hazard | C | random |
|--------------|:----:|:---:|:------:|:---:|:------:|:-:|:------:|
| Forward from `x0` | - | pass | pass | pass | **FAIL** | pass | **2/3 fail** |
| No load-use stall | - | pass | pass | pass | **FAIL** | **FAIL** | **3/3 fail** |
| WB forward has priority over MEM | - | **FAIL** | **FAIL** | pass | **FAIL** | pass | **3/3 fail** |
| `SB` always writes lane 0 | - | pass | pass | **FAIL** | pass | pass | **3/3 fail** |
| `JALR` keeps bit 0 | - | pass | **FAIL** | pass | pass | pass | **3/3 fail** |
| Taken branch does not flush ID | - | **FAIL** | **FAIL** | **FAIL** | **FAIL** | **FAIL** | **3/3 fail** |
| `SRA` behaves as `SRL` | **FAIL**\* | **FAIL** | pass | pass | pass | pass | **2/3 fail** |
| `LH` zero-extends | - | pass | pass | **FAIL** | pass | **FAIL** | **1/3 fail** |
| No register-file write-through | - | **FAIL** | **FAIL** | **FAIL** | **FAIL** | **FAIL** | **3/3 fail** |
| Instruction RAM not held on stall | - | pass | pass | pass | **FAIL** | **FAIL** | **3/3 fail** |

\* the unit test checks the ALU directly.

---

## 4. Notes for the next step (peripherals)

* **Where peripherals go:** the `0x1000_0000` window in `soc_top.v` (the
  `sel_periph` decode is stubbed there). A suggested layout is one 4 KiB
  page per device, e.g. GPIO `0x1000_0000`, UART `0x1000_1000`, I2C
  `0x1000_2000`, SPI `0x1000_3000`.
* **Bus protocol** (MEM stage, see the header of `rv32i_core.v`):
  `dbus_addr` (byte address), `dbus_wdata` (lane-aligned), `dbus_wstrb`,
  `dbus_we`, `dbus_re` are valid for one cycle; a slave must return
  `dbus_rdata` **registered, on the next cycle**. `soc_top` registers the
  slave select alongside the request to steer the read mux. There are no
  wait states; a device with side-effects on read (e.g. a UART RX FIFO pop)
  should act on `dbus_re`.
* **Testbench and MMIO:** the reference model does not model peripherals. For
  loads outside RAM it adopts the value the RTL loaded, so lockstep checking
  keeps working; peripheral behaviour needs its own checks (e.g. a UART
  receiver model in the testbench).
* **Programs:** C programs build with `sw/common/crt0.S` + `link.ld`; add
  them to the `Makefile` like `ctest`. `sw/common/soc.h` holds addresses.

## 5. Known limitations

* No exceptions, interrupts or CSRs (`ECALL`/`EBREAK`/`CSR*` are NOPs,
  illegal instructions are NOPs). A trap unit could use the decoder's
  `illegal` output.
* No M extension (multiply/divide).
* Misaligned loads/stores are not detected (half/word accesses use the
  aligned address).
* Taken branches and jumps cost 2 cycles; a small branch predictor or
  resolving branches in ID would lower CPI further.
