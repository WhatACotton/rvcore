# Makefile for compiling and testing C programs on RISC-V CPU

# Toolchain configuration
TOOLCHAIN_PREFIX = riscv64-unknown-elf-
CC = $(TOOLCHAIN_PREFIX)gcc
OBJCOPY = $(TOOLCHAIN_PREFIX)objcopy
OBJDUMP = $(TOOLCHAIN_PREFIX)objdump

# Architecture and ABI
ARCH = rv32i_zicsr
ABI = ilp32

# Compiler flags
CFLAGS = -march=$(ARCH) -mabi=$(ABI)
CFLAGS += -nostdlib -nostartfiles -ffreestanding
CFLAGS += -O1 -fno-inline -fno-builtin
CFLAGS += -Wall -Wextra

# Linker flags
LDFLAGS = -march=$(ARCH) -mabi=$(ABI)
LDFLAGS += -nostdlib -nostartfiles
LDFLAGS += -Tlinker.ld

# Source files
STARTUP = startup.S
SRCS = $(wildcard *.c)
PROGS = $(SRCS:.c=)

# Build all programs
all: $(PROGS)
	@echo ""
	@echo "====================================="
	@echo "All programs compiled successfully!"
	@echo "====================================="
	@echo "Programs: $(PROGS)"
	@echo ""
	@echo "To run in simulation:"
	@echo "  cd .."
	@echo "  cp c_programs/<program>.hex ."
	@echo "  Edit test_rvcore.py to load '<program>.hex'"
	@echo "  make"

# Pattern rule to build each program
%: %.c $(STARTUP) linker.ld
	@echo "Building $@..."
	@echo "  [1/5] Compiling startup..."
	@$(CC) $(CFLAGS) -c $(STARTUP) -o startup.o
	@echo "  [2/5] Compiling $<..."
	@$(CC) $(CFLAGS) -c $< -o $@.o
	@echo "  [3/5] Linking..."
	@$(CC) $(LDFLAGS) startup.o $@.o -o $@.elf
	@echo "  [4/5] Creating hex file..."
	@$(OBJCOPY) -O binary $@.elf $@.bin
	@hexdump -v -e '/4 "%08x\n"' $@.bin > $@.hex
	@echo "  [5/5] Creating disassembly..."
	@$(OBJDUMP) -d -M no-aliases $@.elf > $@.dis
	@echo "  Done: $@.hex ($(shell wc -l < $@.hex) instructions)"
	@echo ""

# Run a specific program in simulation
run-%: %
	@echo "Running $< in simulation..."
	@cp $<.hex ../
	@cd .. && sed -i 's/hex_file = Path.*\.hex/hex_file = Path(__file__).parent \/ "$<.hex"/' test_rvcore.py
	@cd .. && make
	@echo ""
	@echo "Check the output above for results"

# Clean build artifacts
clean:
	rm -f *.o *.elf *.bin *.hex *.dis
	@echo "Cleaned build artifacts"

# Help
help:
	@echo "RISC-V C Program Build System"
	@echo "=============================="
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build all C programs"
	@echo "  <program>    - Build specific program (e.g., 'make test_add')"
	@echo "  run-<prog>   - Build and run in simulation (e.g., 'make run-test_add')"
	@echo "  clean        - Remove build artifacts"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Available programs:"
	@for prog in $(PROGS); do echo "  - $$prog"; done
	@echo ""
	@echo "Example workflow:"
	@echo "  1. Write your C program (e.g., mytest.c)"
	@echo "  2. make mytest"
	@echo "  3. make run-mytest"

.PHONY: all clean help run-%
