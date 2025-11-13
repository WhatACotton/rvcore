#!/bin/bash

# Batch test runner for RISC-V tests
# Usage: run_test_batch.sh <test_suite>
#   test_suite: rv32ui, rv32um, etc.

SUITE=$1
if [ -z "$SUITE" ]; then
    echo "Usage: $0 <test_suite>"
    echo "  test_suite: rv32ui, rv32um, etc."
    exit 1
fi

# Call the simple test runner with the pattern for this suite
./run_all_tests_simple.sh "${SUITE}-p-*.hex"
