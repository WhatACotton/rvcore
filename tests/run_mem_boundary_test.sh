#!/bin/bash
# Run memory boundary auto-halt tests

set -e

echo "============================================"
echo "Memory Boundary Auto-Halt Test Suite"
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
export MODULE=test_mem_boundary
export SIM_BUILD=sim_build_mem_boundary

# RTL sources (space-separated list)
export VERILOG_SOURCES="${RTL_DIR}/rvcore_simple.sv ${RTL_DIR}/cf_math_pkg.sv"

# Include directories
export VERILOG_INCLUDE_DIRS="${RTL_DIR}"

# Verilator flags
export COMPILE_ARGS="-Wno-fatal -Wno-PINMISSING -Wno-IMPLICIT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-DECLFILENAME"

# Module parameters (START_ADDR=0x10000 for BRAM tests)
export COMPILE_ARGS="${COMPILE_ARGS} -GSTART_ADDR=32\\'h00010000 -GHART_ID=0"

# Cocotb settings
export COCOTB_REDUCED_LOG_FMT=1
export COCOTB_LOG_LEVEL=INFO
export RVCORE_VERBOSE=${RVCORE_VERBOSE:-1}

# Waveform control
if [ "${WAVES}" = "1" ]; then
    export EXTRA_ARGS="--trace --trace-structs"
    echo "Waveform generation enabled (dump.vcd)"
fi

# Clean previous build
echo "Cleaning previous build..."
rm -rf sim_build_mem_boundary test_mem_boundary.log
mkdir -p sim_build_mem_boundary

# Run tests
echo ""
echo "Running memory boundary tests..."
echo ""

# Get cocotb makefile path
COCOTB_MAKEFILE=$(cocotb-config --makefiles)/Makefile.sim

# Run cocotb
make -f ${COCOTB_MAKEFILE} 2>&1 | tee test_mem_boundary.log

# Check results
if grep -q "FAIL=0" test_mem_boundary.log; then
    echo ""
    echo "============================================"
    echo "✓ Memory boundary tests PASSED"
    echo "============================================"
    exit 0
else
    echo ""
    echo "============================================"
    echo "✗ Memory boundary tests FAILED"
    echo "============================================"
    exit 1
fi
