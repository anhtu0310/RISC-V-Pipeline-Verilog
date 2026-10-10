# Build and test flow for the RV32I pipeline.
#
#   make test         build programs (if a toolchain is present) and run every test
#   make unit         ALU / branch unit unit tests
#   make isa          directed assembly tests
#   make ctest        C program test
#   make periph       peripheral tests: register level (tb_periph) and
#                     firmware on the SoC (GPIO, UART, I2C, SPI)
#   make random       random lockstep tests (SEEDS="1 2 3", COUNT=600)
#   make lint         Verilator lint of the RTL (soc_top and fpga_top)
#   make synth        Yosys Xilinx 7-series synthesis, LUT/FF per module
#   make sw           rebuild sw/build/*.hex (needs riscv64-unknown-elf-gcc)
#   make run HEX=...  run one image (add TRACE=1 / VCD=wave.vcd)

RTL      := $(wildcard rtl/*.v rtl/periph/*.v)
INC      := -Irtl -Irtl/periph
BUILD    := build
SWBUILD  := sw/build

IVERILOG ?= iverilog
VVP      ?= vvp
PYTHON   ?= python3
CROSS    ?= riscv64-unknown-elf-
CC       := $(CROSS)gcc
OBJCOPY  := $(CROSS)objcopy
OBJDUMP  := $(CROSS)objdump

ARCH     := -march=rv32i -mabi=ilp32
ASFLAGS  := $(ARCH) -nostdlib -nostartfiles -Isw/common -T sw/common/link.ld -Wl,--no-warn-rwx-segments
CFLAGS   := $(ARCH) -O2 -ffreestanding -nostdlib -nostartfiles -Isw/common -T sw/common/link.ld -Wl,--no-warn-rwx-segments -Wall

ISA_TESTS := alu branch mem hazard
PERIPH_TESTS := gpio_test uart_test i2c_test spi_test
TB_MODELS := $(wildcard tb/models/*.v)
SEEDS     ?= 1 2 3 4 5 6 7 8
COUNT     ?= 600

.PHONY: test unit isa ctest periph periph-unit periph-sw random lint synth sw run clean

test: unit isa ctest periph random

# ---------------------------------------------------------------------------
# Software
# ---------------------------------------------------------------------------
sw: $(addprefix $(SWBUILD)/,$(addsuffix .hex,$(ISA_TESTS) ctest $(PERIPH_TESTS)))

$(SWBUILD)/%.elf: sw/tests/%.S sw/common/*.h sw/common/link.ld | $(SWBUILD)
	$(CC) $(ASFLAGS) -o $@ $<

$(SWBUILD)/ctest.elf: sw/c/main.c sw/common/crt0.S sw/common/*.h sw/common/link.ld | $(SWBUILD)
	$(CC) $(CFLAGS) -o $@ sw/common/crt0.S sw/c/main.c

$(SWBUILD)/%_test.elf: sw/periph/%_test.c sw/common/crt0.S sw/common/*.h sw/common/link.ld | $(SWBUILD)
	$(CC) $(CFLAGS) -o $@ sw/common/crt0.S $<

$(SWBUILD)/%.hex: $(SWBUILD)/%.elf
	$(OBJCOPY) -O binary $< $(SWBUILD)/$*.bin
	$(PYTHON) tools/bin2hex.py $(SWBUILD)/$*.bin $@
	$(OBJDUMP) -d $< > $(SWBUILD)/$*.dis
	rm -f $(SWBUILD)/$*.bin

# Keep the committed images usable without a cross compiler.
.PRECIOUS: $(SWBUILD)/%.elf

$(SWBUILD) $(BUILD):
	mkdir -p $@

# ---------------------------------------------------------------------------
# Simulation
# ---------------------------------------------------------------------------
$(BUILD)/tb_soc.vvp: $(RTL) rtl/rv32i_defs.vh tb/tb_soc.v tb/rv32i_ref_model.v $(TB_MODELS) | $(BUILD)
	$(IVERILOG) -g2012 -Wall $(INC) -o $@ -s tb_soc tb/tb_soc.v tb/rv32i_ref_model.v $(TB_MODELS) $(RTL)

$(BUILD)/tb_periph.vvp: $(wildcard rtl/periph/*.v) tb/tb_periph.v $(TB_MODELS) | $(BUILD)
	$(IVERILOG) -g2012 -Wall $(INC) -o $@ -s tb_periph tb/tb_periph.v $(TB_MODELS) $(wildcard rtl/periph/*.v)

$(BUILD)/tb_units.vvp: rtl/alu.v rtl/branch_unit.v rtl/decoder.v rtl/rv32i_defs.vh tb/tb_units.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall $(INC) -o $@ -s tb_units tb/tb_units.v rtl/alu.v rtl/branch_unit.v rtl/decoder.v

unit: $(BUILD)/tb_units.vvp
	$(VVP) -n $<

# Run one image and fail unless the testbench printed TEST PASSED.
define run_sim
	$(VVP) -n $(BUILD)/tb_soc.vvp +HEX=$(1) $(3) > $(BUILD)/$(2).log 2>&1; \
	  grep -E "^(cycles|TEST|MISMATCH|RAM MISMATCH|  rtl|  model|UART|SPI|\[uart\])" $(BUILD)/$(2).log; \
	  grep -q "^TEST PASSED" $(BUILD)/$(2).log
endef

isa: $(BUILD)/tb_soc.vvp
	@set -e; for t in $(ISA_TESTS); do \
	  echo "=== isa: $$t"; \
	  $(call run_sim,$(SWBUILD)/$$t.hex,isa_$$t); \
	done

ctest: $(BUILD)/tb_soc.vvp
	@echo "=== C test"
	@$(call run_sim,$(SWBUILD)/ctest.hex,ctest)

periph: periph-unit periph-sw

periph-unit: $(BUILD)/tb_periph.vvp
	@echo "=== peripherals: register-level tests"
	@$(VVP) -n $< > $(BUILD)/tb_periph.log 2>&1; \
	  grep -E "^(---|FAIL|peripheral|TEST)" $(BUILD)/tb_periph.log; \
	  grep -q "^TEST PASSED" $(BUILD)/tb_periph.log

# The UART test must also put its banner on the wire.
UART_BANNER := "+UART_EXPECT=Hello from RV32I over UART!"

periph-sw: $(BUILD)/tb_soc.vvp
	@set -e; for t in $(PERIPH_TESTS); do \
	  echo "=== periph: $$t"; \
	  $(call run_sim,$(SWBUILD)/$$t.hex,$$t,$$( [ $$t = uart_test ] && echo $(UART_BANNER) )); \
	done

random: $(BUILD)/tb_soc.vvp
	@set -e; for s in $(SEEDS); do \
	  echo "=== random seed $$s"; \
	  $(PYTHON) tools/gen_random.py --seed $$s --count $(COUNT) -o $(BUILD)/random_$$s.hex; \
	  $(call run_sim,$(BUILD)/random_$$s.hex,random_$$s); \
	done

run: $(BUILD)/tb_soc.vvp
	$(VVP) -n $< +HEX=$(HEX) $(if $(TRACE),+TRACE) $(if $(VCD),+VCD=$(VCD))

lint:
	verilator --lint-only -Wall $(INC) --top-module soc_top $(RTL)
	verilator --lint-only -Wall $(INC) --top-module fpga_top rtl/fpga/fpga_top.v $(RTL)

# Xilinx 7-series mapping of fpga_top (16 GPIO pins), per-module LUT/FF/BRAM.
synth: | $(BUILD)
	yosys -q -p "read_verilog $(INC) $(RTL) rtl/fpga/fpga_top.v; synth_xilinx -top fpga_top -family xc7; tee -o $(BUILD)/synth_xc7.txt stat" > /dev/null
	@$(PYTHON) tools/synth_summary.py $(BUILD)/synth_xc7.txt

clean:
	rm -rf $(BUILD)
