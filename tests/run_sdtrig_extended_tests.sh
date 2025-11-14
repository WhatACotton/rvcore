#!/bin/bash
# Run extended Sdtrig tests for newly implemented features

set -e

echo "========================================"
echo "Running Extended Sdtrig Tests"
echo "========================================"
echo ""

cd "$(dirname "$0")"

# Run the extended tests
make clean > /dev/null 2>&1
MODULE=test_sdtrig_extended TESTCASE="" make

# Check results
if grep -q "FAIL=0" results.xml 2>/dev/null || tail -20 sim_build/sim.log 2>/dev/null | grep -q "FAIL=0"; then
    echo ""
    echo "============================================"
    echo "✓ Extended Sdtrig tests PASSED"
    echo "============================================"
    exit 0
else
    echo ""
    echo "============================================"
    echo "✗ Extended Sdtrig tests FAILED"
    echo "============================================"
    exit 1
fi
