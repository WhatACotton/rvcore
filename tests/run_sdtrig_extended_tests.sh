#!/bin/bash
# Run extended Sdtrig tests for newly implemented features

set -e

echo "========================================"
echo "Running Extended Sdtrig Tests"
echo "========================================"
echo ""

cd "$(dirname "$0")"

# Activate virtual environment if available
if [ -f ../../../.venv/bin/activate ]; then
    source ../../../.venv/bin/activate
fi

# Run the extended tests with proper module specification
make clean-local > /dev/null 2>&1 || true
rm -f results.xml

# Run with explicit module and avoid default targets
MODULE=test_sdtrig_extended TESTCASE="" make -f Makefile results.xml

# Check results
echo ""
if [ -f results.xml ]; then
    # Check if there are any failures or errors
    FAILURES=$(grep -oP 'failures="\K[0-9]+' results.xml 2>/dev/null || echo "0")
    ERRORS=$(grep -oP 'errors="\K[0-9]+' results.xml 2>/dev/null || echo "0")
    
    # Count test cases
    TESTCASES=$(grep -c "<testcase" results.xml 2>/dev/null || echo "0")
    
    if [ "$FAILURES" = "0" ] && [ "$ERRORS" = "0" ] && [ "$TESTCASES" -gt "0" ]; then
        echo "============================================"
        echo "✓ Extended Sdtrig tests PASSED ($TESTCASES tests)"
        echo "============================================"
        exit 0
    else
        echo "============================================"
        echo "✗ Extended Sdtrig tests FAILED"
        echo "  Tests: $TESTCASES, Failures: $FAILURES, Errors: $ERRORS"
        echo "============================================"
        exit 1
    fi
else
    echo "============================================"
    echo "✗ Extended Sdtrig tests FAILED"
    echo "  (results.xml not found)"
    echo "============================================"
    exit 1
fi
