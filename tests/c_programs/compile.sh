#!/bin/bash
# Compile C program to RISC-V hex file for CPU testing

set -e  # Exit on error

# Configuration
TOOLCHAIN_PREFIX="riscv64-unknown-elf-"
ARCH="rv32i_zicsr"
ABI="ilp32"

# Check if toolchain is available
if ! command -v ${TOOLCHAIN_PREFIX}gcc &> /dev/null; then
    echo "Error: RISC-V toolchain not found!"
    echo "Please install riscv64-unknown-elf-gcc"
    echo ""
    echo "On Ubuntu/Debian:"
    echo "  sudo apt-get install gcc-riscv64-unknown-elf"
    echo ""
    echo "Or build from source:"
    echo "  https://github.com/riscv-collab/riscv-gnu-toolchain"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <source.c> [output_name]"
    echo ""
    echo "Example:"
    echo "  $0 simple_add.c"
    echo "  $0 fibonacci.c fib"
    exit 1
fi

SOURCE_FILE="$1"
if [ ! -f "$SOURCE_FILE" ]; then
    echo "Error: Source file '$SOURCE_FILE' not found!"
    exit 1
fi

# Determine output name
if [ $# -ge 2 ]; then
    OUTPUT_NAME="$2"
else
    OUTPUT_NAME=$(basename "$SOURCE_FILE" .c)
fi

echo "========================================="
echo "RISC-V C to Hex Compiler"
echo "========================================="
echo "Source:  $SOURCE_FILE"
echo "Output:  $OUTPUT_NAME.hex"
echo "Arch:    $ARCH"
echo "ABI:     $ABI"
echo "========================================="
echo ""

# Compile C to object file
echo "[1/6] Compiling C source..."
${TOOLCHAIN_PREFIX}gcc \
    -march=$ARCH \
    -mabi=$ABI \
    -nostdlib \
    -nostartfiles \
    -ffreestanding \
    -O1 \
    -fno-inline \
    -fno-builtin \
    -Wall \
    -Wextra \
    -c "$SOURCE_FILE" \
    -o "${OUTPUT_NAME}.o"

# Compile startup code
if [ -f "$SCRIPT_DIR/startup.S" ]; then
    echo "[2/6] Compiling startup code..."
    ${TOOLCHAIN_PREFIX}gcc \
        -march=$ARCH \
        -mabi=$ABI \
        -nostdlib \
        -c "$SCRIPT_DIR/startup.S" \
        -o startup.o
    STARTUP_OBJ="startup.o"
else
    echo "[2/6] No startup code found, skipping..."
    STARTUP_OBJ=""
fi

# Link
echo "[3/6] Linking..."
if [ -f "$SCRIPT_DIR/linker.ld" ]; then
    LINKER_SCRIPT="-T$SCRIPT_DIR/linker.ld"
else
    LINKER_SCRIPT=""
fi

${TOOLCHAIN_PREFIX}gcc \
    -march=$ARCH \
    -mabi=$ABI \
    -nostdlib \
    -nostartfiles \
    $LINKER_SCRIPT \
    $STARTUP_OBJ "${OUTPUT_NAME}.o" \
    -o "${OUTPUT_NAME}.elf"

# Convert to binary
echo "[4/6] Creating binary..."
${TOOLCHAIN_PREFIX}objcopy \
    -O binary \
    "${OUTPUT_NAME}.elf" \
    "${OUTPUT_NAME}.bin"

# Create hex file (32-bit words)
echo "[5/6] Creating hex file..."
hexdump -v -e '/4 "%08x\n"' "${OUTPUT_NAME}.bin" > "${OUTPUT_NAME}.hex"

# Create disassembly
echo "[6/6] Creating disassembly..."
${TOOLCHAIN_PREFIX}objdump \
    -d \
    -M no-aliases \
    "${OUTPUT_NAME}.elf" \
    > "${OUTPUT_NAME}.dis"

echo ""
echo "========================================="
echo "Compilation successful!"
echo "========================================="
echo "Output files:"
echo "  ${OUTPUT_NAME}.hex     - Hex file for simulation"
echo "  ${OUTPUT_NAME}.elf     - ELF executable"
echo "  ${OUTPUT_NAME}.bin     - Raw binary"
echo "  ${OUTPUT_NAME}.dis     - Disassembly"
echo ""
echo "Program size: $(wc -l < "${OUTPUT_NAME}.hex") instructions ($(stat -f%z "${OUTPUT_NAME}.bin" 2>/dev/null || stat -c%s "${OUTPUT_NAME}.bin") bytes)"
echo ""
echo "To run in cocotb simulation:"
echo "  1. Copy ${OUTPUT_NAME}.hex to the test directory"
echo "  2. Update test_rvcore.py to load '${OUTPUT_NAME}.hex'"
echo "  3. Run: make"
echo "========================================="

# Show first few instructions
echo ""
echo "First few instructions:"
head -n 10 "${OUTPUT_NAME}.hex"

# Cleanup intermediate files
rm -f startup.o "${OUTPUT_NAME}.o"

echo ""
echo "Done!"
