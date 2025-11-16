# Makefile for RISC-V Core Testing
# Uses riscv-tests submodule for verification with cocotb

# Default goal
.DEFAULT_GOAL := all

# Simulator configuration
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
SIM_BUILD ?= sim_build

# Paths
PROJECT_ROOT = $(abspath ..)
RISCV_TESTS = $(PROJECT_ROOT)/deps/riscv-tests/isa
RTL_DIR = $(PROJECT_ROOT)/rtl/core
DEPS_DIR = $(PROJECT_ROOT)/deps
HEX_DIR = riscv_test_hex

# Test categories for RV32I
RV32UI_TESTS = $(wildcard $(RISCV_TESTS)/rv32ui-p-*)
RV32UM_TESTS = $(wildcard $(RISCV_TESTS)/rv32um-p-*)

# Filter out .dump files
RV32UI_BINS = $(filter-out %.dump, $(RV32UI_TESTS))
RV32UM_BINS = $(filter-out %.dump, $(RV32UM_TESTS))

# Hex file targets
RV32UI_HEXS = $(patsubst $(RISCV_TESTS)/%,$(HEX_DIR)/%.hex,$(RV32UI_BINS))
RV32UM_HEXS = $(patsubst $(RISCV_TESTS)/%,$(HEX_DIR)/%.hex,$(RV32UM_BINS))

# RTL source files
VERILOG_SOURCES = \
	$(RTL_DIR)/*.sv \
	$(RTL_DIR)/*.vh \
	$(RTL_DIR)/*.svh \
	$(DEPS_DIR)/apb/src/apb_pkg.sv \
	$(DEPS_DIR)/apb/src/apb_intf.sv 

# Include directories
VERILOG_INCLUDE_DIRS = \
	$(RTL_DIR) \
	$(DEPS_DIR)/apb/src

# Top level module
TOPLEVEL = top_with_ram_sim

# Python test module
MODULE ?= test_riscv_single

# Verilator flags
# Disable tracing by default for faster simulation (enable with WAVES=1)
ifeq ($(WAVES),1)
    EXTRA_ARGS += --trace --trace-structs
endif
EXTRA_ARGS += -v
COMPILE_ARGS += -Wno-fatal
COMPILE_ARGS += -Wno-PINMISSING
COMPILE_ARGS += -Wno-IMPLICIT
COMPILE_ARGS += -Wno-WIDTHEXPAND
COMPILE_ARGS += -Wno-WIDTHTRUNC
COMPILE_ARGS += -Wno-DECLFILENAME

# Defines
COMPILE_ARGS += -DCLINT_BASE=32\'h02000000
COMPILE_ARGS += -DCLINT_END=32\'h0200FFFF
COMPILE_ARGS += -DDEBUG_AREA_START=32\'h00000000
COMPILE_ARGS += -DDEBUG_AREA_END=32\'h00001000

# Module parameters for RISC-V tests
# Tests start at 0x00000000 with custom linker script
COMPILE_ARGS += -GSTART_ADDR=32\'h00000000
# tohost is at 0x00000480 (standard RISC-V test location for -p virtual tests)
COMPILE_ARGS += -GTOHOST_ADDR=32\'h00000480

# Cocotb settings
export TEST_NAME

# Default target
.PHONY: all
all: test

# Prepare hex files from ELF binaries
$(HEX_DIR)/%.hex: $(RISCV_TESTS)/%
	@mkdir -p $(HEX_DIR)
	@echo "Converting $< to hex..."
# 	@riscv32-unknown-elf-objcopy -O verilog $< $@

# Prepare all hex files
.PHONY: prepare-hex
prepare-hex: prepare-hex-rv32ui prepare-hex-rv32um

.PHONY: prepare-hex-rv32ui
prepare-hex-rv32ui: $(RV32UI_HEXS)
	@echo "RV32UI hex files prepared: $(words $(RV32UI_HEXS)) files"

.PHONY: prepare-hex-rv32um
prepare-hex-rv32um: $(RV32UM_HEXS)
	@echo "RV32UM hex files prepared: $(words $(RV32UM_HEXS)) files"

# IMPORTANT: Do NOT call these targets from scripts - they trigger cocotb
# Include cocotb makefiles LAST to avoid interference
include $(shell cocotb-config --makefiles)/Makefile.sim

# Wrapper targets that bypass cocotb's default behavior
.PHONY: sim-single sim-rv32ui sim-rv32um

# Run single test wrapper (user-facing) - bypasses cocotb make integration
sim-single:
	@if [ -z "$(TEST)" ]; then \
		echo "Usage: make sim-single TEST=<test_name>"; \
		echo "Example: make sim-single TEST=rv32ui-p-add"; \
		exit 1; \
	fi
	@if [ ! -f $(HEX_DIR)/$(TEST).hex ]; then \
		echo "Hex file not found, preparing..."; \
		$(MAKE) $(HEX_DIR)/$(TEST).hex; \
	fi
	@echo "Running test: $(TEST)"
	@cp $(HEX_DIR)/$(TEST).hex firmware.hex
	@bash run_single_test.sh $(TEST)

# Run all RV32UI tests (bypass make recursion)
sim-rv32ui:
	@if [ ! -d $(HEX_DIR) ] || [ -z "$$(ls -A $(HEX_DIR)/rv32ui-*.hex 2>/dev/null)" ]; then \
		echo "Hex files not found. Run 'make prepare-hex-rv32ui' first."; \
		exit 1; \
	fi
	@echo "Running RV32UI simulation tests..."
	bash run_all_tests_simple.sh

# Run all RV32UM tests (bypass make recursion)
sim-rv32um:
	@if [ ! -d $(HEX_DIR) ] || [ -z "$$(ls -A $(HEX_DIR)/rv32um-*.hex 2>/dev/null)" ]; then \
		echo "Hex files not found. Run 'make prepare-hex-rv32um' first."; \
		exit 1; \
	fi
	@echo "Running RV32UM simulation tests..."
	bash run_test_batch.sh rv32um

# Convenience targets (auto-prepare hex)
.PHONY: test
test: prepare-hex-rv32ui sim-rv32ui

.PHONY: test-rv32ui
test-rv32ui: prepare-hex-rv32ui sim-rv32ui

.PHONY: test-rv32um
test-rv32um: prepare-hex-rv32um sim-rv32um

.PHONY: test-single
test-single: sim-single

# Sdtrig (trigger module) tests
.PHONY: test-sdtrig
test-sdtrig:
	@echo "Running Sdtrig (trigger module) tests..."
	@bash run_sdtrig_tests.sh

# Sdext (external debug extension) tests
.PHONY: test-sdext
test-sdext:
	@echo "Running Sdext (external debug extension) tests..."
	MODULE=test_sdext $(MAKE) -f Makefile.clint

# List available tests
.PHONY: list-tests
list-tests:
	@echo "Available RV32UI tests:"
	@ls -1 $(RISCV_TESTS)/rv32ui-p-* 2>/dev/null | grep -v '.dump$$' | xargs -n1 basename || true
	@echo "\nAvailable RV32UM tests:"
	@ls -1 $(RISCV_TESTS)/rv32um-p-* 2>/dev/null | grep -v '.dump$$' | xargs -n1 basename || true

# Clean targets
.PHONY: clean-local
clean-local:
	@echo "Cleaning build artifacts..."
	@rm -rf $(SIM_BUILD) __pycache__ *.vcd *.log results.xml firmware.hex
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	@echo "Clean complete"

.PHONY: clean-hex
clean-hex:
	@echo "Cleaning hex files..."
	@rm -rf $(HEX_DIR)
	@echo "Hex files cleaned"

.PHONY: clean-all
clean-all: clean-local clean-hex

# Help target
.PHONY: help
help:
	@echo "RISC-V Core Test Makefile (Cocotb-based)"
	@echo ""
	@echo "Hex Preparation:"
	@echo "  make prepare-hex           - Prepare all hex files"
	@echo "  make prepare-hex-rv32ui    - Prepare RV32UI hex files"
	@echo "  make prepare-hex-rv32um    - Prepare RV32UM hex files"
	@echo ""
	@echo "Simulation (using Cocotb):"
	@echo "  make sim-single TEST=<name> - Simulate a single test"
	@echo "  make sim-rv32ui            - Simulate all RV32UI tests"
	@echo "  make sim-rv32um            - Simulate all RV32UM tests"
	@echo ""
	@echo "Convenience (Hex + Sim):"
	@echo "  make test                  - Run all RV32UI tests"
	@echo "  make test-single TEST=<name> - Run a single test"
	@echo ""
	@echo "Utilities:"
	@echo "  make list-tests            - List all available tests"
	@echo "  make clean-local           - Clean simulation artifacts"
	@echo "  make clean-hex             - Clean hex files"
	@echo "  make clean-all             - Clean everything"
	@echo "  make help                  - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make prepare-hex-rv32ui"
	@echo "  make sim-single TEST=rv32ui-p-add"
	@echo "  make test-single TEST=rv32ui-p-add"
	@echo "  make sim-rv32ui"


