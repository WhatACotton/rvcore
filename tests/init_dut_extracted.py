"""Extracted `init_dut` and direct dependencies for tests.

This module contains a minimal, standalone extraction of `init_dut`
from `tests/top_helpers.py` along with the helper `load_simple_program`
and the required imports/constants so it can be reused independently.
"""
import os
import sys
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

# Ensure the repository `common` helper dir is importable (same logic as original)
COMMON_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'common'))
if COMMON_DIR not in sys.path:
    sys.path.insert(0, COMMON_DIR)
from apb_driver import APBMaster  # pyright: ignore[reportMissingImports]

# Default test parameters (same names as in original file)
DEFAULT_CLK_PERIOD_NS = int(os.environ.get('CLK_PERIOD_NS', '10'))
DEFAULT_RESET_CYCLES = int(os.environ.get('RESET_CYCLES', '5'))


async def load_simple_program(dut):
    """Load a minimal infinite-loop program into both harts.

    This mirrors the helper in `top_helpers.py` and writes a single
    instruction (jal x0,0) into the `init_addr`/`init_data` interface
    used by the test bench.
    """
    dut._log.info("Loading simple program into cores...")

    # Single-instruction infinite loop: jal x0, 0
    program = [
        0x0000006f,  # 0x00: jal x0, 0 (infinite loop)
    ]

    # Helper to set init signals handling scalar or packed-array ports
    def set_init_signals(addr_val, data_val, wen_val):
        try:
            # Scalar ports (top_with_ram_sim)
            getattr(dut, 'init_addr').value = addr_val
            getattr(dut, 'init_data').value = data_val
            # Scalar init_wen is 1-bit; write 1 if any hart enabled
            try:
                scalar_wen = 1 if (wen_val & 0x1 or wen_val & 0x2) else 0
                getattr(dut, 'init_wen').value = scalar_wen
            except Exception:
                # ignore and fall back
                pass
            return
        except AttributeError:
            pass

        # Packed-array fallback (pack hart0 lower, hart1 upper)
        lower_addr = (addr_val & 0xFFFFFFFF) if (wen_val & 0x1) else 0
        upper_addr = ((addr_val & 0xFFFFFFFF) << 32) if (wen_val & 0x2) else 0
        packed_addr = lower_addr | upper_addr

        lower_data = (data_val & 0xFFFFFFFF) if (wen_val & 0x1) else 0
        upper_data = ((data_val & 0xFFFFFFFF) << 32) if (wen_val & 0x2) else 0
        packed_data = lower_data | upper_data

        try:
            getattr(dut, 'init_addr').value = packed_addr
            getattr(dut, 'init_data').value = packed_data
            getattr(dut, 'init_wen').value = (wen_val & 0x3)
            return
        except AttributeError:
            return

    for addr_offset, instr in enumerate(program):
        addr = addr_offset * 4
        set_init_signals(addr, instr, 0x3)
        await ClockCycles(dut.clk, 1)

    # Clear init signals
    set_init_signals(0, 0, 0)

    await ClockCycles(dut.clk, 2)
    dut._log.info("✓ Program loaded into cores")


async def init_dut(dut, clk_period_ns=None, reset_cycles=None, load_program=False):
    """Initialize DUT with clock and reset and return APB master.

    Args:
        dut: The DUT instance provided by cocotb
        clk_period_ns: Clock period in ns (defaults to `DEFAULT_CLK_PERIOD_NS`)
        reset_cycles: Number of cycles to hold reset asserted
        load_program: If True, load a simple program into cores

    Returns:
        APBMaster instance for DTM interface
    """
    if clk_period_ns is None:
        clk_period_ns = DEFAULT_CLK_PERIOD_NS
    if reset_cycles is None:
        reset_cycles = DEFAULT_RESET_CYCLES

    # Start clock
    cocotb.start_soon(Clock(dut.clk, clk_period_ns, units="ns").start())
    # Helper to set DUT signals only if they exist
    def write_if_exists(name, value):
        try:
            setattr(getattr(dut, name), 'value', value)
        except AttributeError:
            return

    # Initialize inputs (be tolerant of different wrapper ports)
    write_if_exists('i_nextdm', 0)
    write_if_exists('i_ndmreset_ack', 0)
    write_if_exists('i_ext_halt_trigger', 0)
    write_if_exists('i_ext_resume_trigger', 0)
    write_if_exists('i_dtm_apb_access_disable', 0)
    write_if_exists('i_cpu_apb_access_disable', 0)
    write_if_exists('init_addr', 0)
    write_if_exists('init_data', 0)
    write_if_exists('init_wen', 0)

    # Assert reset (prefer `reset_n` used by top_with_ram_sim)
    if hasattr(dut, 'reset_n'):
        write_if_exists('reset_n', 0)
        reset_signal = 'reset_n'
    elif hasattr(dut, 'rst_n'):
        write_if_exists('rst_n', 0)
        reset_signal = 'rst_n'
    else:
        reset_signal = None
    await ClockCycles(dut.clk, reset_cycles)

    # Optionally load a simple program into cores
    if load_program:
        await load_simple_program(dut)

    # Deassert reset and wait a couple cycles
    write_if_exists(reset_signal, 1)
    await ClockCycles(dut.clk, 2)

    # Choose APB prefix: prefer CPU APB (`i_cpu_apb_*`) used by top_with_ram_sim
    if hasattr(dut, 'i_cpu_apb_paddr'):
        apb_prefix = 'i_cpu_apb'
    elif hasattr(dut, 'dtm_apb_paddr'):
        apb_prefix = 'dtm_apb'
    else:
        apb_prefix = 'i_cpu_apb'

    dtm_master = APBMaster(dut, apb_prefix, dut.clk)

    dut._log.info("DUT initialized")
    return dtm_master
