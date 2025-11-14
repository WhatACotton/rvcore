"""Extended Sdtrig tests for newly implemented trigger types and features.

Tests for:
- Type 3 (icount): Instruction count trigger
- Type 4 (itrigger): Interrupt trigger  
- Type 5 (etrigger): Exception trigger
- Type 6 (mcontrol6): Enhanced address/data match
- Action 0: Breakpoint exception
- Action 8/9: External trigger outputs
- tcontrol, tinfo, tdata3, mcontext CSRs
"""
import cocotb
from cocotb.triggers import ClockCycles
from cocotb.clock import Clock

# CSR addresses
CSR_TSELECT = 0x7A0
CSR_TDATA1 = 0x7A1
CSR_TDATA2 = 0x7A2
CSR_TDATA3 = 0x7A3
CSR_TINFO = 0x7A4
CSR_TCONTROL = 0x7A5
CSR_MCONTEXT = 0x7A8

# Trigger types
TRIGGER_TYPE_MCONTROL = 0x2
TRIGGER_TYPE_ICOUNT = 0x3
TRIGGER_TYPE_ITRIGGER = 0x4
TRIGGER_TYPE_ETRIGGER = 0x5
TRIGGER_TYPE_MCONTROL6 = 0x6
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
async def test_tinfo_register(dut):
    """Test tinfo register reports supported trigger types."""
    await init_dut(dut)
    
    dut._log.info("Testing tinfo register")
    
    # Read tinfo - should report types 2,3,4,5,6,7 supported
    tinfo_value = int(dut.cpu.tinfo.value)
    
    dut._log.info(f"tinfo value: 0x{tinfo_value:08x} (binary: 0b{tinfo_value:032b})")
    
    # Check each type bit
    # bit 2 = type 2 (mcontrol)
    # bit 3 = type 3 (icount)
    # bit 4 = type 4 (itrigger)
    # bit 5 = type 5 (etrigger)
    # bit 6 = type 6 (mcontrol6)
    # bit 7 = type 7 (tmexttrigger)
    
    assert (tinfo_value & (1 << 2)) != 0, "Type 2 (mcontrol) should be supported"
    assert (tinfo_value & (1 << 3)) != 0, "Type 3 (icount) should be supported"
    assert (tinfo_value & (1 << 4)) != 0, "Type 4 (itrigger) should be supported"
    assert (tinfo_value & (1 << 5)) != 0, "Type 5 (etrigger) should be supported"
    assert (tinfo_value & (1 << 6)) != 0, "Type 6 (mcontrol6) should be supported"
    assert (tinfo_value & (1 << 7)) != 0, "Type 7 (tmexttrigger) should be supported"
    
    dut._log.info("✓ tinfo correctly reports all supported trigger types")


@cocotb.test()
async def test_tcontrol_register(dut):
    """Test tcontrol register controls M-mode trigger enable."""
    await init_dut(dut)
    
    dut._log.info("Testing tcontrol register")
    
    # Check initial tcontrol value (mte should be 1 by default)
    initial_tcontrol = int(dut.cpu.tcontrol.value)
    mte_bit = (initial_tcontrol >> 3) & 0x1
    
    dut._log.info(f"Initial tcontrol: 0x{initial_tcontrol:08x}, mte={mte_bit}")
    assert mte_bit == 1, "M-mode trigger enable should be 1 by default"
    
    # Write to tcontrol to disable M-mode triggers
    dut.cpu.tcontrol.value = 0x00000000  # mte=0
    await ClockCycles(dut.clk, 2)
    
    new_tcontrol = int(dut.cpu.tcontrol.value)
    new_mte = (new_tcontrol >> 3) & 0x1
    
    dut._log.info(f"After write: tcontrol=0x{new_tcontrol:08x}, mte={new_mte}")
    assert new_mte == 0, "mte should be 0 after write"
    
    # Re-enable for subsequent tests
    dut.cpu.tcontrol.value = 0x00000008  # mte=1
    await ClockCycles(dut.clk, 2)
    
    dut._log.info("✓ tcontrol register access works correctly")


@cocotb.test()
async def test_type3_icount_trigger(dut):
    """Test type 3 (icount) instruction count trigger."""
    await init_dut(dut)
    
    dut._log.info("Testing type 3 (icount) instruction count trigger")
    
    # Configure trigger 0: type=3 (icount), count=5, m=1, action=1
    # tdata1[31:28]=3 (icount), [23:10]=5 (count), [9]=1 (m-mode), [6:5]=1 (action)
    count_value = 5
    tdata1_value = (TRIGGER_TYPE_ICOUNT << 28) | (count_value << 10) | (1 << 9) | (1 << 5)
    
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_value
    
    await ClockCycles(dut.clk, 3)
    
    # Check icount counter initialized (after tdata1 write takes effect)
    counter_value = int(dut.cpu.icount_counter[0].value) & 0x3FFF
    dut._log.info(f"Initial icount counter: {counter_value}")
    
    # Note: Counter initialization happens on tdata1 write in proc_state==IMEM_DONE
    # In simulation without real instructions, counter may not update as expected
    # This test verifies the configuration is accepted and counter exists
    
    trigger_type = (int(dut.cpu.tdata1[0].value) >> 28) & 0xF
    assert trigger_type == TRIGGER_TYPE_ICOUNT, f"Type should be 3, got {trigger_type}"
    
    dut._log.info(f"✓ icount trigger configured correctly (type={trigger_type}, counter={counter_value})")


@cocotb.test()
async def test_type4_itrigger(dut):
    """Test type 4 (itrigger) interrupt trigger."""
    await init_dut(dut)
    
    dut._log.info("Testing type 4 (itrigger) interrupt trigger")
    
    # Configure trigger 0: type=4 (itrigger), m=1, action=1
    # tdata1[31:28]=4, [9]=1 (m-mode), [7:6]=1 (action=debug)
    tdata1_value = (TRIGGER_TYPE_ITRIGGER << 28) | (1 << 9) | (1 << 6)
    
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_value
    
    await ClockCycles(dut.clk, 2)
    
    # Verify configuration
    actual_tdata1 = int(dut.cpu.tdata1[0].value)
    trigger_type = (actual_tdata1 >> 28) & 0xF
    
    dut._log.info(f"Configured itrigger: tdata1=0x{actual_tdata1:08x}, type={trigger_type}")
    assert trigger_type == TRIGGER_TYPE_ITRIGGER, f"Type should be 4, got {trigger_type}"
    
    # Note: Full interrupt trigger testing requires interrupt mechanism
    # This test verifies configuration is accepted
    
    dut._log.info("✓ itrigger configuration works correctly")


@cocotb.test()
async def test_type5_etrigger(dut):
    """Test type 5 (etrigger) exception trigger."""
    await init_dut(dut)
    
    dut._log.info("Testing type 5 (etrigger) exception trigger")
    
    # Configure trigger 0: type=5 (etrigger), m=1, action=1
    # tdata1[31:28]=5, [9]=1 (m-mode), [7:6]=1 (action=debug)
    tdata1_value = (TRIGGER_TYPE_ETRIGGER << 28) | (1 << 9) | (1 << 6)
    
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_value
    
    await ClockCycles(dut.clk, 2)
    
    # Verify configuration
    actual_tdata1 = int(dut.cpu.tdata1[0].value)
    trigger_type = (actual_tdata1 >> 28) & 0xF
    
    dut._log.info(f"Configured etrigger: tdata1=0x{actual_tdata1:08x}, type={trigger_type}")
    assert trigger_type == TRIGGER_TYPE_ETRIGGER, f"Type should be 5, got {trigger_type}"
    
    # Note: Full exception trigger testing requires exception mechanism
    # This test verifies configuration is accepted
    
    dut._log.info("✓ etrigger configuration works correctly")


@cocotb.test()
async def test_type6_mcontrol6(dut):
    """Test type 6 (mcontrol6) enhanced address/data match trigger."""
    await init_dut(dut)
    
    dut._log.info("Testing type 6 (mcontrol6) enhanced trigger")
    
    # Get current PC
    await ClockCycles(dut.clk, 2)
    current_pc = int(dut.cpu.pc.value)
    target_pc = current_pc + 0x20
    
    # Configure trigger 0: type=6 (mcontrol6), select=0 (execute), m=1, action=1
    # tdata1[31:28]=6, [16:12]=0 (execute), [6:5]=1 (action), [2]=1 (m-mode)
    tdata1_value = (TRIGGER_TYPE_MCONTROL6 << 28) | (0 << 12) | (1 << 5) | (1 << 2)
    
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_value
    dut.cpu.tdata2[0].value = target_pc
    
    await ClockCycles(dut.clk, 2)
    
    # Verify configuration
    actual_tdata1 = int(dut.cpu.tdata1[0].value)
    actual_tdata2 = int(dut.cpu.tdata2[0].value)
    trigger_type = (actual_tdata1 >> 28) & 0xF
    
    dut._log.info(f"Configured mcontrol6: type={trigger_type}, tdata2=0x{actual_tdata2:08x}")
    assert trigger_type == TRIGGER_TYPE_MCONTROL6, f"Type should be 6, got {trigger_type}"
    assert actual_tdata2 == target_pc, f"tdata2 should be 0x{target_pc:08x}, got 0x{actual_tdata2:08x}"
    
    dut._log.info("✓ mcontrol6 configuration works correctly")


@cocotb.test()
async def test_action_8_external_output(dut):
    """Test action=8 drives external trigger output chain 0."""
    await init_dut(dut)
    
    dut._log.info("Testing action=8 (external output chain 0)")
    
    # Check initial state
    initial_ext = int(dut.o_trigger_external.value)
    ext0_init = initial_ext & 0x1
    ext1_init = (initial_ext >> 1) & 0x1
    
    assert ext0_init == 0, f"Initial ext0 should be 0, got {ext0_init}"
    assert ext1_init == 0, f"Initial ext1 should be 0, got {ext1_init}"
    
    dut._log.info(f"✓ Initial external outputs: 0b{initial_ext:02b}")
    
    # Configure trigger 0: type=7, select=0, action=8
    tdata1_value = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (0 << 16) | (8 << 12)
    
    dut.cpu.tselect.value = 0
    dut.cpu.tdata1[0].value = tdata1_value
    
    await ClockCycles(dut.clk, 2)
    
    # Assert external trigger input
    dut.i_external_trigger.value = 0b0001
    await ClockCycles(dut.clk, 2)
    
    # Check output
    ext_after = int(dut.o_trigger_external.value)
    ext0_after = ext_after & 0x1
    ext1_after = (ext_after >> 1) & 0x1
    
    dut._log.info(f"After trigger: o_trigger_external=0b{ext_after:02b} (ext0={ext0_after}, ext1={ext1_after})")
    
    assert ext0_after == 1, f"ext0 should be 1 (action=8), got {ext0_after}"
    assert ext1_after == 0, f"ext1 should be 0, got {ext1_after}"
    
    dut._log.info("✓ Action 8 correctly drives o_trigger_external[0]")
    
    # Clear
    dut.i_external_trigger.value = 0
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_action_9_external_output(dut):
    """Test action=9 drives external trigger output chain 1."""
    await init_dut(dut)
    
    dut._log.info("Testing action=9 (external output chain 1)")
    
    # Configure trigger 1: type=7, select=1, action=9
    tdata1_value = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (1 << 16) | (9 << 12)
    
    dut.cpu.tselect.value = 1
    dut.cpu.tdata1[1].value = tdata1_value
    
    await ClockCycles(dut.clk, 2)
    
    # Assert external trigger input
    dut.i_external_trigger.value = 0b0010
    await ClockCycles(dut.clk, 2)
    
    # Check output
    ext_after = int(dut.o_trigger_external.value)
    ext0_after = ext_after & 0x1
    ext1_after = (ext_after >> 1) & 0x1
    
    dut._log.info(f"After trigger: o_trigger_external=0b{ext_after:02b} (ext0={ext0_after}, ext1={ext1_after})")
    
    assert ext0_after == 0, f"ext0 should be 0, got {ext0_after}"
    assert ext1_after == 1, f"ext1 should be 1 (action=9), got {ext1_after}"
    
    dut._log.info("✓ Action 9 correctly drives o_trigger_external[1]")
    
    # Clear
    dut.i_external_trigger.value = 0
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_both_external_outputs_simultaneous(dut):
    """Test both external outputs can be active simultaneously."""
    await init_dut(dut)
    
    dut._log.info("Testing both external outputs simultaneously")
    
    # Configure trigger 0: action=8, select=0
    dut.cpu.tselect.value = 0
    tdata1_t0 = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (0 << 16) | (8 << 12)
    dut.cpu.tdata1[0].value = tdata1_t0
    
    # Configure trigger 1: action=9, select=1
    dut.cpu.tselect.value = 1
    tdata1_t1 = (TRIGGER_TYPE_TMEXTTRIGGER << 28) | (1 << 16) | (9 << 12)
    dut.cpu.tdata1[1].value = tdata1_t1
    
    await ClockCycles(dut.clk, 2)
    
    # Assert both external inputs
    dut.i_external_trigger.value = 0b0011
    await ClockCycles(dut.clk, 2)
    
    # Both outputs should be active
    ext_value = int(dut.o_trigger_external.value)
    ext0 = ext_value & 0x1
    ext1 = (ext_value >> 1) & 0x1
    
    dut._log.info(f"Both triggers: o_trigger_external=0b{ext_value:02b}")
    
    assert ext0 == 1, f"ext0 should be 1, got {ext0}"
    assert ext1 == 1, f"ext1 should be 1, got {ext1}"
    assert ext_value == 0b11, f"Both bits should be set, got 0b{ext_value:02b}"
    
    dut._log.info("✓ Both external outputs can be active simultaneously")
    
    # Clear
    dut.i_external_trigger.value = 0
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_tdata3_register(dut):
    """Test tdata3 register read/write access."""
    await init_dut(dut)
    
    dut._log.info("Testing tdata3 register")
    
    # Select trigger 0
    dut.cpu.tselect.value = 0
    await ClockCycles(dut.clk, 1)
    
    # Write to tdata3
    test_value = 0xDEADBEEF
    dut.cpu.tdata3[0].value = test_value
    await ClockCycles(dut.clk, 2)
    
    # Read back
    read_value = int(dut.cpu.tdata3[0].value)
    
    dut._log.info(f"tdata3 write: 0x{test_value:08x}, read: 0x{read_value:08x}")
    assert read_value == test_value, f"tdata3 should be 0x{test_value:08x}, got 0x{read_value:08x}"
    
    dut._log.info("✓ tdata3 register access works correctly")


@cocotb.test()
async def test_mcontext_register(dut):
    """Test mcontext register read/write access."""
    await init_dut(dut)
    
    dut._log.info("Testing mcontext register")
    
    # Write to mcontext
    test_value = 0x12345678
    dut.cpu.mcontext.value = test_value
    await ClockCycles(dut.clk, 2)
    
    # Read back
    read_value = int(dut.cpu.mcontext.value)
    
    dut._log.info(f"mcontext write: 0x{test_value:08x}, read: 0x{read_value:08x}")
    assert read_value == test_value, f"mcontext should be 0x{test_value:08x}, got 0x{read_value:08x}"
    
    dut._log.info("✓ mcontext register access works correctly")
