#!/bin/bash
# Run a single RISC-V test with cocotb
# Usage: ./run_single_test.sh <test_name>

set -e

rm -f results.xml
if [ $# -ne 1 ]; then
    echo "Usage: $0 <test_name>"
    echo "Example: $0 rv32ui-p-add"
    exit 1
fi

TEST_NAME="$1"

# Export TEST_NAME for cocotb to read
export TEST_NAME

echo "Running test: ${TEST_NAME}"
echo ""


# Copy hex file to firmware.hex for cocotb
cp "$HEX_FILE" firmware.hex

# Clean up old results to force fresh run
rm -f results.xml

# Run make with the simulator (this will trigger cocotb)
# The cocotb Makefile.sim is already included in the main Makefile
# We just need to run the results.xml target which cocotb provides
make -f Makefile results.xml MODULE=test_riscv_single TESTCASE=test_riscv_program

echo ""
echo "Test ${TEST_NAME} completed"
