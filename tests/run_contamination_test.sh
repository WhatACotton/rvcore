#!/bin/bash
# Run memory contamination test

cd "$(dirname "$0")"

export RTL_DIR="../rtl/core"

# Set test parameters
export MODULE=test_memory_contamination
export TESTCASE=test_direct_bram_access
export TOPLEVEL=top_with_ram_sim
export TOPLEVEL_LANG=verilog

# Verilator settings
export SIM=verilator
export EXTRA_ARGS="--trace --trace-structs"

# Clean previous build
make clean

# Run test
make \
    VERILOG_SOURCES="\
        $RTL_DIR/apb_arbiter.sv \
        $RTL_DIR/cf_math_pkg.sv \
        $RTL_DIR/clint.sv \
        $RTL_DIR/decoder_module.sv \
        $RTL_DIR/rvcore_simple.sv \
        $RTL_DIR/top_with_ram_sim.sv \
        $RTL_DIR/trigger_module_comb.sv \
        $RTL_DIR/trigger_module.sv \
        $RTL_DIR/*.vh \
        $RTL_DIR/*.svh \
        $RTL_DIR/../deps/apb/src/apb_pkg.sv \
        $RTL_DIR/../deps/apb/src/apb_intf.sv \
        $RTL_DIR/../deps/apb_uart_sv/apb_uart.sv \
        $RTL_DIR/../deps/apb_uart_sv/uart_tx.sv \
        $RTL_DIR/../deps/apb_uart_sv/uart_rx.sv \
        $RTL_DIR/../deps/apb_uart_sv/uart_interrupt.sv \
        $RTL_DIR/../deps/apb_uart_sv/io_generic_fifo.sv \
    " \
    COMPILE_ARGS="\
        -Wno-fatal \
        -Wno-PINMISSING \
        -Wno-IMPLICIT \
        -Wno-WIDTHEXPAND \
        -Wno-WIDTHTRUNC \
        -Wno-DECLFILENAME \
        -DCLINT_BASE=32'h02000000 \
        -DCLINT_END=32'h0200FFFF \
        -DDEBUG_AREA_START=32'h00000000 \
        -DDEBUG_AREA_END=32'h00001000 \
        -GSTART_ADDR=32'h00000000 \
        -GTOHOST_ADDR=32'h000006C0 \
        -GUART_BASE_ADDR=32'h00000100 \
        -GUART_ADDR_MASK=32'h00000FF0 \
        --timescale 1ns/1ps \
    "

echo ""
echo "============================================"
echo "Test complete. Check sim_build/dump.vcd for waveforms"
echo "Look for [DMEM_WRITE] and [DMEM_READ] diagnostic messages"
echo "============================================"
