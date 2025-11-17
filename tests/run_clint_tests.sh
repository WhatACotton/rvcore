#!/bin/bash
# Run CLINT-specific tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================="
echo "Running CLINT Tests"
echo "================================="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results
PASSED=0
FAILED=0
TOTAL=0

# Function to run a test
run_test() {
    local test_name=$1
    TOTAL=$((TOTAL + 1))
    
    echo -e "${YELLOW}Running: ${test_name}${NC}"
    
    if make MODULE=test_clint -f Makefile.clint TESTCASE="${test_name}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}: ${test_name}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAILED${NC}: ${test_name}"
        FAILED=$((FAILED + 1))
    fi
    echo ""
}

# Clean previous build
echo "Cleaning previous build..."
make clean > /dev/null 2>&1
echo ""

# Run all CLINT tests
echo "Running CLINT hardware tests..."
echo ""

run_test "test_clint_mtime_increments"
run_test "test_clint_mtimecmp_rw"
run_test "test_clint_timer_interrupt"
run_test "test_clint_address_decode"
run_test "test_clint_64bit_access"
run_test "test_clint_apb_interface"
run_test "test_clint_multi_hart"

# Summary
echo "================================="
echo "Test Summary"
echo "================================="
echo -e "Total:  ${TOTAL}"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All CLINT tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed${NC}"
    exit 1
fi
