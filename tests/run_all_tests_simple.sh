#!/bin/bash
# Simple test runner for RISC-V tests
# Note: Don't use 'set -e' because we want to continue even if tests fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default pattern
PATTERN="${1:-rv32ui-p-*.hex}"

echo "========================================="
echo "  RISC-V Test Suite Runner"
echo "========================================="
echo ""


# Find all matching tests
TESTS=($(ls riscv_test_hex/${PATTERN} 2>/dev/null | sort))
TOTAL=${#TESTS[@]}

if [ $TOTAL -eq 0 ]; then
    echo -e "${RED}No tests found matching pattern: ${PATTERN}${NC}"
    exit 1
fi

echo -e "${BLUE}Found ${#TESTS[@]} tests${NC}"
echo "Pattern: ${PATTERN}"
echo ""

# Build Verilator model once (if not already built)
echo -e "${BLUE}Checking Verilator build...${NC}"
if ! make -s sim_build 2>&1 | grep -q "Nothing to be done\|up to date"; then
    echo -e "${BLUE}Building Verilator model...${NC}"
fi
echo ""

echo "----------------------------------------"

# Run each test sequentially
PASSED=0
FAILED=0
FAILED_TESTS=()
START_TIME=$(date +%s)

for test_hex in "${TESTS[@]}"; do
    test_name=$(basename "$test_hex" .hex)
    
    # Show progress counter
    CURRENT=$((PASSED + FAILED + 1))
    echo ""
    echo -e "${BLUE}[${CURRENT}/${TOTAL}]${NC} Testing: ${test_name}"
    
    # Copy hex file to firmware.hex
    cp "$test_hex" firmware.hex
    
    # Export TEST_NAME for cocotb
    export TEST_NAME="$test_name"
    
    # Clean up old results to force re-run (but not rebuild)
    rm -f results.xml
    
    # Run test via make with some output visible
    TEST_START=$(date +%s)
    echo -n "  Running simulation... "
    
    # Run and capture output
    make -s results.xml MODULE=test_riscv_single TESTCASE=test_riscv_program WAVES=0 > /tmp/test_${test_name}.log 2>&1
    MAKE_EXIT=$?
    
    TEST_END=$(date +%s)
    TEST_TIME=$((TEST_END - TEST_START))
    
    # Check if test actually passed by examining the log
    # Look for "RISC-V TEST PASSED" message
    if grep -q "RISC-V TEST PASSED" /tmp/test_${test_name}.log; then
        # Extract cycle count from pass message
        CYCLES=$(grep "RISC-V TEST PASSED" /tmp/test_${test_name}.log | grep -o "after [0-9]* cycles" | grep -o "[0-9]*" || echo "?")
        
        echo -e "${GREEN}✓ PASSED${NC}"
        echo -e "  Time: ${TEST_TIME}s | Cycles: ${CYCLES}"
        ((PASSED++))
    else
        # Test failed - determine reason
        echo -e "${RED}✗ FAILED${NC}"
        echo -e "  Time: ${TEST_TIME}s"
        
        # Show error details
        if grep -q "timeout\|TIMEOUT" /tmp/test_${test_name}.log; then
            CYCLES=$(grep -o "after [0-9]* cycles" /tmp/test_${test_name}.log | tail -1 | grep -o "[0-9]*" || echo "?")
            echo -e "  ${RED}Reason: Timeout after ${CYCLES} cycles${NC}"
        elif grep -q "test case #" /tmp/test_${test_name}.log; then
            FAIL_CASE=$(grep -o "test case #[0-9]*" /tmp/test_${test_name}.log | tail -1)
            CYCLES=$(grep "test case #" /tmp/test_${test_name}.log | grep -o "after [0-9]* cycles" | grep -o "[0-9]*" || echo "?")
            echo -e "  ${RED}Reason: Failed ${FAIL_CASE} at cycle ${CYCLES}${NC}"
        elif grep -q "Error reading tohost" /tmp/test_${test_name}.log; then
            echo -e "  ${RED}Reason: Cannot read tohost register${NC}"
        else
            echo -e "  ${YELLOW}Reason: Unknown - check /tmp/test_${test_name}.log${NC}"
        fi
        
        ((FAILED++))
        FAILED_TESTS+=("$test_name")
    fi
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

echo "----------------------------------------"
echo ""
echo "========================================="
echo "  Test Results Summary"
echo "========================================="
echo -e "Total:    ${TOTAL}"
echo -e "Passed:   ${GREEN}${PASSED}${NC}"
echo -e "Failed:   ${RED}${FAILED}${NC}"
echo -e "Duration: ${TOTAL_TIME}s"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${RED}Failed tests:${NC}"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ${RED}✗${NC} $test"
    done
    echo ""
    echo "View logs: /tmp/test_<testname>.log"
else
    echo ""
    echo -e "${GREEN}All tests passed! 🎉${NC}"
fi

echo "========================================="
echo ""

# Exit with error if any test failed
exit $FAILED
