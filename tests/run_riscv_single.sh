#!/usr/bin/env bash
set -euo pipefail

# tests/run_riscv_single.sh
# Copy of repo-root helper placed under tests/ so it can be run from tests directory
# Usage:
#   ./tests/run_riscv_single.sh <test>
# See repo-root `run_riscv_single.sh` for details.

rm -f results.xml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ $# -ne 1 ]; then
    echo "Usage: $0 <c-file|test-name|hex-file>"
    exit 1
fi

ARG="$1"
HEX_PATH=""
TEST_NAME=""

# If argument is a path to an existing .hex file
if [[ "$ARG" == *.hex ]] && [ -f "$ARG" ]; then
    HEX_PATH="$ARG"
    TEST_NAME="$(basename "$HEX_PATH" .hex)"
fi

# If argument matches hex under tests/riscv_test_hex
if [ -z "$HEX_PATH" ] && [ -f "$REPO_ROOT/tests/riscv_test_hex/${ARG}.hex" ]; then
    HEX_PATH="$REPO_ROOT/tests/riscv_test_hex/${ARG}.hex"
    TEST_NAME="$ARG"
fi

# Do NOT compile here — only copy an existing .hex.
# Search common locations for an existing .hex (explicit path, riscv_test_hex, c_programs)
if [ -z "$HEX_PATH" ]; then
    # Try inside tests/riscv_test_hex by name
    if [ -f "$REPO_ROOT/tests/riscv_test_hex/${ARG}.hex" ]; then
        HEX_PATH="$REPO_ROOT/tests/riscv_test_hex/${ARG}.hex"
        TEST_NAME="$ARG"
    # Try inside tests/c_programs for a prebuilt hex
    elif [ -f "$REPO_ROOT/tests/c_programs/${ARG}.hex" ]; then
        HEX_PATH="$REPO_ROOT/tests/c_programs/${ARG}.hex"
        TEST_NAME="$ARG"
    fi
fi

if [ -z "$HEX_PATH" ]; then
    echo "Could not locate or build hex for '$ARG'"
    exit 1
fi

echo "Using hex: $HEX_PATH"
echo "TEST_NAME: ${TEST_NAME}"

# Copy hex to repo-root firmware.hex
cp "$HEX_PATH" "$REPO_ROOT/firmware.hex"

# Export TEST_NAME for cocotb tests
export TEST_NAME="$TEST_NAME"

echo "Running single RISC-V test via Makefile (in tests/)..."

# NOTE: Do not override simulator or GPI log levels here; prefer controlling
# Python-side verbosity via RVCORE_VERBOSE. Users can still set
# COCOTB_LOG_LEVEL/GPI_LOG_LEVEL in the environment if desired.

pushd "$REPO_ROOT/tests" > /dev/null
make results.xml MODULE=test_riscv_single TESTCASE=test_riscv_program
popd > /dev/null

echo "Done. Check results.xml and sim_build/ for outputs."
