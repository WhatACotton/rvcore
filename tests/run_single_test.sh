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
HEX_DIR="riscv_test_hex"
HEX_FILE="${HEX_DIR}/${TEST_NAME}.hex"

# Export TEST_NAME for cocotb to read
export TEST_NAME

echo "Running test: ${TEST_NAME}"
echo ""

# Convert hex file to word format for $readmemh
# The RISC-V test hex files are byte-oriented, but $readmemh expects 32-bit words
echo "Converting ${HEX_FILE} to firmware.hex (word format)"
python3 convert_hex_to_words.py "$HEX_FILE" firmware.hex

# Clean up old results to force fresh run
rm -f results.xml

# Run make with the simulator (this will trigger cocotb)
# The cocotb Makefile.sim is already included in the main Makefile
# We just need to run the results.xml target which cocotb provides
make -f Makefile results.xml MODULE=test_riscv_single TESTCASE=test_riscv_program

echo ""
echo "Test ${TEST_NAME} completed"
