# Build and test flow for the RV32I pipeline.
#
#   make test         build programs (if a toolchain is present) and run every test
#   make unit         ALU / branch unit unit tests
#   make isa          directed assembly tests
#   make ctest        C program test
#   make random       random lockstep tests (SEEDS="1 2 3", COUNT=600)
#   make lint         Verilator lint of the RTL
#   make sw           rebuild sw/build/*.hex (needs riscv64-unknown-elf-gcc)
#   make run HEX=...  run one image (add TRACE=1 / VCD=wave.vcd)

RTL      := $(wildcard rtl/*.v)
INC      := -Irtl
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
SEEDS     ?= 1 2 3 4 5 6 7 8
COUNT     ?= 600

.PHONY: test unit isa ctest random lint sw run clean

test: unit isa ctest random

# ---------------------------------------------------------------------------
# Software
# ---------------------------------------------------------------------------
sw: $(addprefix $(SWBUILD)/,$(addsuffix .hex,$(ISA_TESTS) ctest))

$(SWBUILD)/%.elf: sw/tests/%.S sw/common/*.h sw/common/link.ld | $(SWBUILD)
	$(CC) $(ASFLAGS) -o $@ $<

$(SWBUILD)/ctest.elf: sw/c/main.c sw/common/crt0.S sw/common/*.h sw/common/link.ld | $(SWBUILD)
	$(CC) $(CFLAGS) -o $@ sw/common/crt0.S sw/c/main.c

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
$(BUILD)/tb_soc.vvp: $(RTL) rtl/rv32i_defs.vh tb/tb_soc.v tb/rv32i_ref_model.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall $(INC) -o $@ -s tb_soc tb/tb_soc.v tb/rv32i_ref_model.v $(RTL)

$(BUILD)/tb_units.vvp: rtl/alu.v rtl/branch_unit.v rtl/decoder.v rtl/rv32i_defs.vh tb/tb_units.v | $(BUILD)
	$(IVERILOG) -g2012 -Wall $(INC) -o $@ -s tb_units tb/tb_units.v rtl/alu.v rtl/branch_unit.v rtl/decoder.v

unit: $(BUILD)/tb_units.vvp
	$(VVP) -n $<

# Run one image and fail unless the testbench printed TEST PASSED.
define run_sim
	$(VVP) -n $(BUILD)/tb_soc.vvp +HEX=$(1) > $(BUILD)/$(2).log 2>&1; \
	  grep -E "^(cycles|TEST|MISMATCH|RAM MISMATCH|  rtl|  model)" $(BUILD)/$(2).log; \
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

clean:
	rm -rf $(BUILD)
