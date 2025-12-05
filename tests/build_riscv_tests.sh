#!/bin/bash
# Script to build RISC-V compliance tests for BRAM
# This script builds the RV32UI test suite from riscv-tests submodule

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Building RISC-V Compliance Tests for BRAM"
echo "=========================================="

# Check if riscv-tests submodule exists
if [ ! -d "../deps/riscv-tests/isa/rv32ui" ]; then
    echo "Error: riscv-tests submodule not found!"
    echo "Please run: git submodule update --init --recursive"
    exit 1
fi

# Check if RISC-V toolchain is available
if ! command -v riscv64-unknown-elf-gcc &> /dev/null; then
    echo "Error: RISC-V toolchain not found!"
    echo "Please install riscv64-unknown-elf-gcc"
    exit 1
fi

# Check if linker script template exists
if [ ! -f "link_bram.ld" ]; then
    echo "Error: Custom linker script template not found!"
    echo "Expected: link_bram.ld in current directory"
    exit 1
fi

# Copy linker script to riscv-tests env directory
echo "Installing custom linker script..."
cp link_bram.ld ../deps/riscv-tests/env/p/link_bram.ld

echo ""
echo "Prerequisites check passed:"
echo "  - riscv-tests submodule: OK"
echo "  - RISC-V toolchain: $(riscv64-unknown-elf-gcc --version | head -1)"
echo "  - Linker script: OK"
echo ""

# Clean old builds
echo "Cleaning old builds..."
make -f Makefile.bram clean

# Build RV32UI tests
echo ""
echo "Building RV32UI tests..."
make -f Makefile.bram rv32ui

echo ""
echo "=========================================="
echo "Build completed successfully!"
echo "=========================================="
echo ""
echo "Built files are in: $(pwd)/riscv_tests_bram/"
echo ""
echo "To run tests:"
echo "  ./run_all_rv32ui_tests.sh"
