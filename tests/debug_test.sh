#!/bin/bash
# Debug test - shows full output

TEST=${1:-rv32ui-p-add}

echo "=== Debug Test Runner ==="
echo "Test: $TEST"
echo ""

# Prepare firmware
cp "riscv_test_hex/${TEST}.hex" firmware.hex

# Export test name
export TEST_NAME="$TEST"

# Clean old results
rm -f results.xml

# Run with full output visible
echo "Starting simulation with full output..."
echo "========================================"
make results.xml MODULE=test_riscv_single TESTCASE=test_riscv_program WAVES=0 2>&1 | tee test_debug.log

echo "========================================"
echo ""
echo "Log saved to: test_debug.log"
