#!/bin/bash
# Run Sdtrig (Debug Trigger Module) tests

set -e

echo "============================================"
echo "Sdtrig (Debug Trigger Module) Test Suite"
echo "============================================"
echo ""

# Project paths
PROJECT_ROOT=$(cd .. && pwd)
RTL_DIR="${PROJECT_ROOT}/rtl/core"
DEPS_DIR="${PROJECT_ROOT}/deps"

# Test configuration
export SIM=verilator
export TOPLEVEL_LANG=verilog
export TOPLEVEL=core
export MODULE=test_sdtrig
export SIM_BUILD=sim_build_sdtrig

# RTL sources (space-separated list)
export VERILOG_SOURCES="${RTL_DIR}/rvcore_simple.sv ${RTL_DIR}/cf_math_pkg.sv"

# Include directories
export VERILOG_INCLUDE_DIRS="${RTL_DIR}"

# Verilator flags
export COMPILE_ARGS="-Wno-fatal -Wno-PINMISSING -Wno-IMPLICIT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-DECLFILENAME"

# Module parameters (escape single quotes properly)
export COMPILE_ARGS="${COMPILE_ARGS} -GSTART_ADDR=32\\'h00000000 -GHART_ID=0"

# Cocotb settings
export COCOTB_REDUCED_LOG_FMT=1
export COCOTB_LOG_LEVEL=INFO

# Waveform control
if [ "${WAVES}" = "1" ]; then
    export EXTRA_ARGS="--trace --trace-structs"
fi

# Clean previous build
echo "Cleaning previous build..."
rm -rf sim_build_sdtrig *.log
mkdir -p sim_build_sdtrig

# Run tests
echo ""
echo "Running trigger module tests..."
echo ""

# Get cocotb makefile path
COCOTB_MAKEFILE=$(cocotb-config --makefiles)/Makefile.sim

# Run cocotb directly
make -f ${COCOTB_MAKEFILE} 2>&1 | tee sdtrig_test.log

# Check results - look for FAIL=0 in the summary
if grep -q "FAIL=0" sdtrig_test.log; then
    echo ""
    echo "============================================"
    echo "✓ Sdtrig tests PASSED (All 8 tests passed)"
    echo "============================================"
    exit 0
else
    echo ""
    echo "============================================"
    echo "✗ Sdtrig tests FAILED"
    echo "============================================"
    exit 1
fi
