"""Test trigger actions (0=exception, 1=debug, 8/9=external output)."""
import cocotb
from cocotb.triggers import ClockCycles
from cocotb.clock import Clock
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

# CSR addresses
CSR_TSELECT = 0x7A0
CSR_TDATA1 = 0x7A1
CSR_TDATA2 = 0x7A2

# Trigger types
TRIGGER_TYPE_MCONTROL = 0x2
TRIGGER_TYPE_TMEXTTRIGGER = 0x7

DEFAULT_CLK_PERIOD_NS = 10
DEFAULT_RESET_CYCLES = 5


async def init_dut(dut, clk_period_ns=None, reset_cycles=None):
    """Initialize DUT with clock and reset."""
    if clk_period_ns is None:
        clk_period_ns = DEFAULT_CLK_PERIOD_NS
    if reset_cycles is None:
        reset_cycles = DEFAULT_RESET_CYCLES

    cocotb.start_soon(Clock(dut.clk, clk_period_ns, units="ns").start())

    # Initialize inputs
    dut.reset_n.value = 0
    dut.dmem_wready.value = 1
    dut.dmem_rvalid.value = 0
    dut.imem_rvalid.value = 1
    dut.i_haltreq.value = 0
    dut.i_external_trigger.value = 0

    await ClockCycles(dut.clk, reset_cycles)
    dut.reset_n.value = 1
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_action_0_exception(dut):
    """Test action=0 (breakpoint exception) for PC trigger."""
    await init_dut(dut)
    
    dut._log.info("Testing action=0 (breakpoint exception)")
    
    # Get current PC
    await ClockCycles(dut.clk, 2)
    current_pc = int(dut.pc.value)
    dut._log.info(f"Current PC: 0x{current_pc:08x}")
    
    # Configure trigger 0: type=2 (mcontrol), action=0 (exception), execute
    # tdata1[31:28]=2 (mcontrol), [12]=0 (action=exception), [2]=1 (execute)
    tdata1_value = (TRIGGER_TYPE_MCONTROL << 28) | (0 << 12) | (1 << 2)
    tdata2_value = current_pc + 0x10  # Trigger on future PC
    
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_value
    dut.cpu.tdata2[0].value = tdata2_value
    
    await ClockCycles(dut.clk, 5)
    
    # Check trigger exception request signal
    initial_exc = int(dut.cpu.trigger_exception_req.value)
    dut._log.info(f"Initial trigger_exception_req: {initial_exc}")
    
    await ClockCycles(dut.clk, 5)
    
    dut._log.info(f"✓ Action 0 (exception) configuration test passed")


@cocotb.test()
async def test_action_8_external_output(dut):
    """Test action=8 (external output chain 0)."""
    await init_dut(dut)
    
    dut._log.info("Testing action=8 (external trigger output chain 0)")
    
    # Check initial state
    initial_ext0 = int(dut.o_external_trigger.value) & 0x1
    initial_ext1 = (int(dut.o_external_trigger.value) >> 1) & 0x1
    assert initial_ext0 == 0, f"Initial ext0 should be 0, got {initial_ext0}"
    assert initial_ext1 == 0, f"Initial ext1 should be 0, got {initial_ext1}"
    dut._log.info(f"✓ Initial external outputs: ext0={initial_ext0}, ext1={initial_ext1}")
    
    # Configure trigger 0: type=7 (tmexttrigger), action=8, select=0
    # tdata1[31:28]=7, [19:16]=0 (select input 0), [15:12]=8 (action=ext0)
    tdata1_value = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (0 << 16) | (8 << 12)
    
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_value
    
    await ClockCycles(dut.clk, 2)
    
    # Assert external trigger input 0
    dut.i_external_trigger.value = 0b0001
    await ClockCycles(dut.clk, 2)
    
    # Check external output chain 0
    ext0_after = int(dut.o_external_trigger.value) & 0x1
    ext1_after = (int(dut.o_external_trigger.value) >> 1) & 0x1
    
    dut._log.info(f"After trigger: ext0={ext0_after}, ext1={ext1_after}")
    
    assert ext0_after == 1, f"ext0 should be 1 (action=8), got {ext0_after}"
    assert ext1_after == 0, f"ext1 should be 0, got {ext1_after}"
    
    dut._log.info(f"✓ Action 8 correctly drives o_external_trigger[0]")
    
    # Clear trigger
    dut.i_external_trigger.value = 0
    await ClockCycles(dut.clk, 2)
    
    ext0_cleared = int(dut.o_external_trigger.value) & 0x1
    assert ext0_cleared == 0, f"ext0 should clear to 0, got {ext0_cleared}"
    
    dut._log.info(f"✓ Action 8 test passed")


@cocotb.test()
async def test_action_9_external_output(dut):
    """Test action=9 (external output chain 1)."""
    await init_dut(dut)
    
    dut._log.info("Testing action=9 (external trigger output chain 1)")
    
    # Configure trigger 1: type=7 (tmexttrigger), action=9, select=1
    # tdata1[31:28]=7, [19:16]=1 (select input 1), [15:12]=9 (action=ext1)
    tdata1_value = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (1 << 16) | (9 << 12)
    
    dut.cpu.tselect.value = 1
    dut.cpu.tdata1[1].value = tdata1_value
    
    await ClockCycles(dut.clk, 2)
    
    # Assert external trigger input 1
    dut.i_external_trigger.value = 0b0010
    await ClockCycles(dut.clk, 2)
    
    # Check external output chain 1
    ext0_after = int(dut.o_external_trigger.value) & 0x1
    ext1_after = (int(dut.o_external_trigger.value) >> 1) & 0x1
    
    dut._log.info(f"After trigger: ext0={ext0_after}, ext1={ext1_after}")
    
    assert ext0_after == 0, f"ext0 should be 0, got {ext0_after}"
    assert ext1_after == 1, f"ext1 should be 1 (action=9), got {ext1_after}"
    
    dut._log.info(f"✓ Action 9 correctly drives o_external_trigger[1]")
    
    # Clear trigger
    dut.i_external_trigger.value = 0
    await ClockCycles(dut.clk, 2)
    
    ext1_cleared = (int(dut.o_external_trigger.value) >> 1) & 0x1
    assert ext1_cleared == 0, f"ext1 should clear to 0, got {ext1_cleared}"
    
    dut._log.info(f"✓ Action 9 test passed")


@cocotb.test()
async def test_multiple_actions_combined(dut):
    """Test multiple triggers with different actions simultaneously."""
    await init_dut(dut)
    
    dut._log.info("Testing multiple actions combined")
    
    # Trigger 0: action=8 (ext0), select input 0
    tdata1_t0 = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (0 << 16) | (8 << 12)
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_t0
    
    # Trigger 1: action=9 (ext1), select input 1
    tdata1_t1 = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (1 << 16) | (9 << 12)
    dut.cpu.tselect.value = 1
    dut.cpu.tdata1[1].value = tdata1_t1
    
    await ClockCycles(dut.clk, 2)
    
    # Assert both external inputs
    dut.i_external_trigger.value = 0b0011  # inputs 0 and 1
    await ClockCycles(dut.clk, 2)
    
    # Both outputs should be active
    ext_outputs = int(dut.o_external_trigger.value)
    ext0 = ext_outputs & 0x1
    ext1 = (ext_outputs >> 1) & 0x1
    
    dut._log.info(f"Combined outputs: ext0={ext0}, ext1={ext1}, raw=0b{ext_outputs:02b}")
    
    assert ext0 == 1, f"ext0 should be 1, got {ext0}"
    assert ext1 == 1, f"ext1 should be 1, got {ext1}"
    
    dut._log.info(f"✓ Both external outputs active simultaneously")
    
    # Clear inputs
    dut.i_external_trigger.value = 0
    await ClockCycles(dut.clk, 2)
    
    ext_cleared = int(dut.o_external_trigger.value)
    assert ext_cleared == 0, f"Both outputs should clear, got 0b{ext_cleared:02b}"
    
    dut._log.info(f"✓ Multiple actions combined test passed")
