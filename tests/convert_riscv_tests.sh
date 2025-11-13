#!/bin/bash
# Convert RISC-V ELF test binaries to hex format for memory initialization
# Usage: ./convert_riscv_tests.sh [pattern]
# Example: ./convert_riscv_tests.sh 'rv32ui-p-*'

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RISCV_TESTS_DIR="$SCRIPT_DIR/../deps/riscv-tests/isa"
OUTPUT_DIR="$SCRIPT_DIR/riscv_test_hex"

# Default pattern
PATTERN="${1:-rv32ui-p-*}"

# Check if riscv-tests directory exists
if [ ! -d "$RISCV_TESTS_DIR" ]; then
    echo "Error: RISC-V tests directory not found: $RISCV_TESTS_DIR"
    echo "Please run: git submodule update --init --recursive"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "Converting RISC-V tests matching: $PATTERN"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Find matching test binaries
TESTS=($(find "$RISCV_TESTS_DIR" -name "$PATTERN" -type f ! -name "*.dump" | sort))

if [ ${#TESTS[@]} -eq 0 ]; then
    echo "No tests found matching pattern: $PATTERN"
    exit 1
fi

echo "Found ${#TESTS[@]} test(s)"
echo ""

CONVERTED=0
FAILED=0

for test_file in "${TESTS[@]}"; do
    test_name=$(basename "$test_file")
    output_hex="$OUTPUT_DIR/${test_name}.hex"
    output_dis="$OUTPUT_DIR/${test_name}.dis"
    
    echo "Converting: $test_name"
    
    # Generate disassembly
    if riscv64-unknown-elf-objdump -d "$test_file" > "$output_dis" 2>/dev/null; then
        echo "  ✓ Generated disassembly"
    else
        echo "  ✗ Failed to generate disassembly"
        ((FAILED++))
        continue
    fi
    
    # Convert to Verilog hex format (for $readmemh)
    if riscv64-unknown-elf-objcopy -O verilog "$test_file" "$output_hex" 2>/dev/null; then
        LINE_COUNT=$(wc -l < "$output_hex")
        echo "  ✓ Generated hex file ($LINE_COUNT lines)"
        ((CONVERTED++))
    else
        echo "  ✗ Failed to convert to hex"
        ((FAILED++))
        continue
    fi
done

echo ""
echo "========================================"
echo "Conversion complete!"
echo "========================================"
echo "Converted: $CONVERTED"
echo "Failed: $FAILED"
echo "Output: $OUTPUT_DIR"
