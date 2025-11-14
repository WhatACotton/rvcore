#!/bin/bash
# Run Sdext extension tests

cd "$(dirname "$0")"

echo "======================================"
echo "Running Sdext Extension Tests"
echo "======================================"

# Use make to run the tests via cocotb
make test-sdext

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "======================================"
    echo "✓ All Sdext tests PASSED"
    echo "======================================"
else
    echo ""
    echo "======================================"
    echo "✗ Some Sdext tests FAILED"
    echo "======================================"
fi

exit $EXIT_CODE
