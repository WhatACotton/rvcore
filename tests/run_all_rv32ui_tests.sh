#!/bin/bash
# Run all RV32UI tests with proper hex format

set -e

# Activate virtual environment
source ../../../.venv/bin/activate

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "  RISC-V RV32UI Test Suite Runner"
echo "========================================="
echo ""

# Find all hex files
HEX_FILES=(riscv_tests_bram/rv32ui-p-*.hex)
TOTAL_TESTS=${#HEX_FILES[@]}

if [ $TOTAL_TESTS -eq 0 ]; then
    echo "ERROR: No test hex files found in riscv_tests_bram/"
    echo "Please run: make -f Makefile.bram rv32ui"
    exit 1
fi

echo "Found $TOTAL_TESTS tests"
echo ""

# Results tracking
PASSED=0
FAILED=0
FAILED_TESTS=()

# Run each test
for hex_file in "${HEX_FILES[@]}"; do
    # Extract test name (e.g., rv32ui-p-add from riscv_tests_bram/rv32ui-p-add.hex)
    test_name=$(basename "$hex_file" .hex)
    test_num=$((PASSED + FAILED + 1))
    
    echo "----------------------------------------"
    echo "[$test_num/$TOTAL_TESTS] Testing: $test_name"
    
    # Clean previous results
    rm -f results.xml firmware.hex
    
    # Copy hex file to firmware.hex
    cp "$hex_file" firmware.hex
    
    # Set test name for cocotb
    export TEST_NAME="$test_name"
    
    # Run test with timeout
    if timeout 60 make -f Makefile results.xml MODULE=test_riscv_single TESTCASE=test_riscv_program > test_output.tmp 2>&1; then
        # Check if it actually passed
        if grep -q "TESTS=1 PASS=1 FAIL=0" test_output.tmp; then
            echo -e "${GREEN}  ✓ PASS${NC}"
            PASSED=$((PASSED + 1))
            # Extract cycle count
            CYCLES=$(grep "RISC-V TEST PASSED after" test_output.tmp | grep -oP '\d+(?= cycles)' || echo "N/A")
            if [ "$CYCLES" != "N/A" ]; then
                echo "    Cycles: $CYCLES"
            fi
        else
            echo -e "${RED}  ✗ FAIL${NC}"
            FAILED=$((FAILED + 1))
            FAILED_TESTS+=("$test_name")
            # Show error if available
            if grep -q "TIMEOUT" test_output.tmp; then
                echo "    Reason: TIMEOUT (>200k cycles)"
            elif grep -q "ERROR" test_output.tmp; then
                grep "ERROR" test_output.tmp | head -1 | sed 's/^/    /'
            fi
        fi
    else
        echo -e "${RED}  ✗ FAIL (timeout or error)${NC}"
        FAILED=$((FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
    
    # Save detailed log for failed tests
    if [ $FAILED -gt $((PASSED + FAILED - 1)) ]; then
        mv test_output.tmp "logs/${test_name}_fail.log" 2>/dev/null || rm -f test_output.tmp
    else
        rm -f test_output.tmp
    fi
done

echo ""
echo "========================================="
echo "  Test Results Summary"
echo "========================================="
echo -e "Total:  $TOTAL_TESTS"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -gt 0 ]; then
    echo "Failed tests:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - $test"
    done
    echo ""
    exit 1
else
    echo -e "${GREEN}All tests passed! 🎉${NC}"
    exit 0
fi
