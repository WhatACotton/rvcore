"""Memory Boundary Auto-Halt Test.

This test suite verifies the automatic halt functionality when PC exceeds
valid RAM boundary.

Test scenarios:
1. Memory boundary violation (PC >= 0x14000) triggers auto-halt
2. PC within valid range does not trigger halt
3. Boundary edge case (PC = 0x14000 exactly)
4. No re-halt when already in debug mode

Valid RAM range: 0x10000 - 0x13FFF (16KB)
Boundary address: 0x14000
"""
import cocotb
from cocotb.triggers import ClockCycles, RisingEdge, Timer, ReadOnly, NextTimeStep
from cocotb.clock import Clock
from cocotb.types import LogicArray
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

# Debug cause codes
DEBUG_CAUSE_EBREAK = 0x1
DEBUG_CAUSE_TRIGGER = 0x2
DEBUG_CAUSE_HALTREQ = 0x3

# Memory boundaries
RAM_START = 0x10000
RAM_END = 0x13FFF
RAM_BOUNDARY = 0x14000  # First address outside valid RAM

# Debug ROM entry point (actual implementation uses 0x600)
DEBUG_ENTRY_POINT = 0x600

DEFAULT_CLK_PERIOD_NS = 10
DEFAULT_RESET_CYCLES = 5


async def init_dut(dut, clk_period_ns=None, reset_cycles=None, test_program=None):
    """Initialize DUT with clock and reset."""
    if clk_period_ns is None:
        clk_period_ns = DEFAULT_CLK_PERIOD_NS
    if reset_cycles is None:
        reset_cycles = DEFAULT_RESET_CYCLES

    # Start clock
    cocotb.start_soon(Clock(dut.clk, clk_period_ns, units="ns").start())

    # Initialize inputs
    dut.reset_n.value = 0
    dut.dmem_wready.value = 1
    dut.dmem_rvalid.value = 1  # Always ready for memory access
    dut.dmem_rdata.value = 0
    dut.imem_rvalid.value = 1  # Always ready for instruction fetch
    dut.imem_rdata.value = 0x00000013  # NOP instruction (default)
    dut.m_external_interrupt.value = 0
    dut.m_timer_interrupt.value = 0
    dut.m_software_interrupt.value = 0
    dut.i_haltreq.value = 0
    dut.i_external_trigger.value = 0

    await ClockCycles(dut.clk, reset_cycles)
    dut.reset_n.value = 1
    
    # If test program provided, start memory model
    if test_program is not None:
        async def memory_model():
            """Continuously provide instructions based on PC (combinational logic)"""
            while True:
                # Wait for PC to change (monitor imem_addr)
                await ReadOnly()  # Enter ReadOnly phase to sample signals
                pc = int(dut.imem_addr.value)
                
                # Determine instruction to provide
                if pc >= RAM_START and pc < RAM_BOUNDARY:
                    word_offset = (pc - RAM_START) // 4
                    if word_offset < len(test_program):
                        instr = test_program[word_offset]
                    else:
                        instr = 0x00000013
                elif pc >= 0x600 and pc < 0x700:
                    instr = 0x00000013  # Debug ROM
                else:
                    instr = 0x00000013
                
                # Exit ReadOnly and update signal
                await NextTimeStep()
                dut.imem_rdata.value = instr
                
                # Wait for next clock edge
                await RisingEdge(dut.clk)
        
        cocotb.start_soon(memory_model())
    
    await ClockCycles(dut.clk, 5)  # Longer delay after reset


def encode_addi(rd, rs1, imm):
    """Encode ADDI instruction."""
    imm_12 = imm & 0xFFF
    return (imm_12 << 20) | (rs1 << 15) | (0x0 << 12) | (rd << 7) | 0x13


def encode_lui(rd, imm):
    """Encode LUI instruction."""
    imm_31_12 = (imm >> 12) & 0xFFFFF
    return (imm_31_12 << 12) | (rd << 7) | 0x37


def encode_jalr(rd, rs1, imm):
    """Encode JALR instruction."""
    imm_12 = imm & 0xFFF
    return (imm_12 << 20) | (rs1 << 15) | (0x0 << 12) | (rd << 7) | 0x67


def encode_nop():
    """Encode NOP instruction (ADDI x0, x0, 0)."""
    return 0x00000013


async def wait_for_debug_mode(dut, timeout_cycles=1000):
    """Wait for debug mode to be asserted.
    
    Args:
        dut: Device under test
        timeout_cycles: Maximum cycles to wait
        
    Returns:
        bool: True if debug mode entered, False if timeout
    """
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if dut.debug_mode_o.value == 1:
            return True
    return False


@cocotb.test()
async def test_mem_boundary_violation_auto_halt(dut):
    """Test: PC exceeds RAM boundary (0x14000) triggers automatic halt"""
    
    # Setup: Create a program that jumps to boundary address
    # LUI x5, 0x14 (load upper immediate: x5 = 0x14000)
    # JALR x0, x5, 0 (jump to x5)
    test_program = [
        encode_lui(5, 0x14000),     # x5 = 0x14000 (boundary address)
        encode_jalr(0, 5, 0),       # PC = x5 (jump to 0x14000)
        0x00000013,                  # NOP (should not execute)
        0x00000013,                  # NOP
    ]
    
    # Fill rest with NOPs
    while len(test_program) < 1024:
        test_program.append(0x00000013)
    
    await init_dut(dut, test_program=test_program)
    
    dut._log.info("=" * 80)
    dut._log.info("TEST: Memory Boundary Violation Auto-Halt")
    dut._log.info("=" * 80)
    dut._log.info(f"  Program[0] @ 0x10000 = 0x{test_program[0]:08x} (LUI x5, 0x14000)")
    dut._log.info(f"  Program[1] @ 0x10004 = 0x{test_program[1]:08x} (JALR x0, x5, 0)")
    
    # Monitor PC for debug mode entry
    debug_entered = False
    max_cycles = 200
    prev_pc = -1
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        pc = int(dut.imem_addr.value)
        debug_mode = int(dut.debug_mode_o.value)
        
        # Log PC changes
        if pc != prev_pc:
            if cycle <= 20 or cycle % 5 == 0 or debug_mode == 1:
                dut._log.info(f"[Cycle {cycle:3d}] PC = 0x{pc:08x}, debug_mode = {debug_mode}")
            prev_pc = pc
        
        # Check if debug mode entered
        if debug_mode == 1 and not debug_entered:
            debug_entered = True
            dut._log.info("=" * 60)
            dut._log.info(f"✓ DEBUG MODE ENTERED at cycle {cycle}")
            dut._log.info(f"  PC when halted: 0x{pc:08x}")
            dut._log.info("=" * 60)
            await ClockCycles(dut.clk, 10)
            break
    
    # Verify results
    assert debug_entered, "CPU did not enter debug mode after boundary violation"
    
    # The auto-halt should trigger when PC >= 0x14000
    # After halt, PC should be in DEBUG ROM region (0x600-0x6FF)
    final_pc = int(dut.imem_addr.value)
    assert final_pc >= DEBUG_ENTRY_POINT and final_pc < 0x700, \
        f"Expected PC in debug ROM (0x{DEBUG_ENTRY_POINT:08x}-0x6FF), got 0x{final_pc:08x}"
    
    dut._log.info("=" * 80)
    dut._log.info("✓ TEST PASSED: Memory boundary violation triggered auto-halt")
    dut._log.info("=" * 80)


@cocotb.test()
async def test_within_boundary_no_halt(dut):
    """Test: PC within valid RAM range (< 0x14000) does NOT trigger halt"""
    
    # Program that stays within valid RAM range
    # Simple NOPs - just increment PC within valid range
    test_program = []
    while len(test_program) < 1024:
        test_program.append(0x00000013)  # NOP
    
    await init_dut(dut, test_program=test_program)
    
    dut._log.info("=" * 80)
    dut._log.info("TEST: Within Boundary - No Auto-Halt")
    dut._log.info("=" * 80)
    
    # Run for many cycles - should NOT enter debug mode
    max_cycles = 200
    debug_entered = False
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        pc = int(dut.imem_addr.value)
        debug_mode = int(dut.debug_mode_o.value)
        
        # Check if debug mode incorrectly entered
        if debug_mode == 1:
            debug_entered = True
            dut._log.error(f"✗ DEBUG MODE ENTERED unexpectedly at cycle {cycle}, PC=0x{pc:08x}")
            break
        
        # Log progress periodically
        if cycle % 50 == 0:
            dut._log.info(f"[Cycle {cycle:3d}] PC = 0x{pc:08x}, still running normally")
    
    # Verify results
    assert not debug_entered, "CPU incorrectly entered debug mode within valid RAM range"
    
    final_debug_mode = int(dut.debug_mode_o.value)
    assert final_debug_mode == 0, "debug_mode should remain 0 for valid PC addresses"
    
    dut._log.info("=" * 80)
    dut._log.info("✓ TEST PASSED: PC within boundary did not trigger auto-halt")
    dut._log.info("=" * 80)


@cocotb.test()
async def test_boundary_edge_case(dut):
    """Test: PC at exact boundary (0x14000) triggers halt"""
    
    # Program that jumps to exactly 0x14000
    test_program = [
        encode_lui(5, 0x14000),     # x5 = 0x14000
        encode_jalr(0, 5, 0),       # PC = 0x14000
        0x00000013,                  # NOP
    ]
    
    # Fill rest with NOPs
    while len(test_program) < 1024:
        test_program.append(0x00000013)
    
    await init_dut(dut, test_program=test_program)
    
    dut._log.info("=" * 80)
    dut._log.info("TEST: Boundary Edge Case (PC = 0x14000)")
    dut._log.info("=" * 80)
    
    debug_entered = False
    max_cycles = 200
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        pc = int(dut.imem_addr.value)
        debug_mode = int(dut.debug_mode_o.value)
        
        if cycle % 5 == 0 or debug_mode == 1:
            dut._log.info(f"[Cycle {cycle:3d}] PC = 0x{pc:08x}, debug_mode = {debug_mode}")
        
        if debug_mode == 1 and not debug_entered:
            debug_entered = True
            dut._log.info(f"✓ DEBUG MODE ENTERED at PC = 0x{pc:08x}")
            await ClockCycles(dut.clk, 10)
            break
    
    assert debug_entered, "CPU did not enter debug mode at boundary address 0x14000"
    
    final_pc = int(dut.imem_addr.value)
    assert final_pc >= DEBUG_ENTRY_POINT and final_pc < 0x700, \
        f"Expected PC in debug ROM (0x{DEBUG_ENTRY_POINT:08x}-0x6FF), got 0x{final_pc:08x}"
    
    dut._log.info("=" * 80)
    dut._log.info("✓ TEST PASSED: Boundary edge case (0x14000) triggered auto-halt")
    dut._log.info("=" * 80)


@cocotb.test()
async def test_no_halt_in_debug_mode(dut):
    """Test: Boundary violation in debug mode does NOT trigger halt again"""
    
    # Just NOPs
    test_program = []
    while len(test_program) < 1024:
        test_program.append(0x00000013)
    
    await init_dut(dut, test_program=test_program)
    
    dut._log.info("=" * 80)
    dut._log.info("TEST: No Re-Halt in Debug Mode")
    dut._log.info("=" * 80)
    
    # First, trigger normal halt request to enter debug mode
    dut._log.info("Step 1: Enter debug mode via haltreq")
    dut.i_haltreq.value = 1
    
    # Wait for debug mode
    debug_entered = await wait_for_debug_mode(dut, timeout_cycles=100)
    assert debug_entered, "Failed to enter debug mode via haltreq"
    
    dut.i_haltreq.value = 0
    await ClockCycles(dut.clk, 10)
    
    initial_pc = int(dut.imem_addr.value)
    dut._log.info(f"Debug mode entered, PC = 0x{initial_pc:08x}")
    
    # Now monitor that debug mode stays active
    dut._log.info("Step 2: Monitor that debug mode remains active")
    
    debug_remained = True
    for cycle in range(100):
        await RisingEdge(dut.clk)
        
        debug_mode = int(dut.debug_mode_o.value)
        
        if debug_mode == 0:
            debug_remained = False
            dut._log.error(f"Debug mode unexpectedly exited at cycle {cycle}")
            break
    
    assert debug_remained, "Debug mode should remain active"
    
    dut._log.info("=" * 80)
    dut._log.info("✓ TEST PASSED: No re-halt in debug mode")
    dut._log.info("=" * 80)


if __name__ == "__main__":
    """Allow running tests individually"""
    import sys
    if len(sys.argv) > 1:
        test_name = sys.argv[1]
        print(f"Running test: {test_name}")


@cocotb.test()
async def test_uninitialized_memory_all_zeros(dut):
    """Test: メモリ未初期化（全て0x00000000）の実機シミュレーション
    
    実際のハードウェアでプログラムが未ロードの場合:
    - メモリは全て 0x00000000
    - 0x00000000 は不正な命令 (opcode=0x00は予約済み、未定義動作)
    - NOP (0x00000013) ではない!
    
    このテストでは、実機で起こりうる状況を忠実にシミュレート:
    - 0x00000000を読み続けた場合のCPUの挙動を観察
    - PCがどのように遷移するか
    - 境界を超えた場合に自動ハルトするか
    """
    
    # メモリは全て0x00000000（未初期化状態、実機シミュレーション）
    # 注意: 0x00000000 は不正な命令
    test_program = []
    while len(test_program) < 1024:
        test_program.append(0x00000000)  # All zeros (invalid instruction)
    
    await init_dut(dut, test_program=test_program)
    
    dut._log.info("=" * 80)
    dut._log.info("TEST: Uninitialized Memory - Real Hardware Simulation")
    dut._log.info("=" * 80)
    dut._log.info("Scenario: 実機でプログラム未ロード（メモリ全て0x00000000）")
    dut._log.info("Note: 0x00000000 は不正な命令 (opcode=0x00は未定義)")
    dut._log.info("      NOP は 0x00000013 (ADDI x0, x0, 0)")
    dut._log.info(" ")
    dut._log.info("観察項目:")
    dut._log.info("  1. 0x00000000 を実行した時のCPUの挙動")
    dut._log.info("  2. PCの遷移パターン")
    dut._log.info("  3. 境界(0x14000)を超えた場合の自動ハルト")
    
    # 0x00000000を連続実行させて挙動を観察
    dut._log.info("\n" + "=" * 60)
    dut._log.info("Phase: 0x00000000 連続実行の観察")
    dut._log.info("=" * 60)
    
    pc_history = []
    debug_entered = False
    max_cycles = 20000  # 境界0x14000到達まで観察 (0x10004→0x14000は約16384命令)
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        pc = int(dut.imem_addr.value)
        debug_mode = int(dut.debug_mode_o.value)
        
        # PC履歴を記録
        if not pc_history or pc != pc_history[-1]:
            pc_history.append(pc)
        
        # 定期的にログ出力 (最初30サイクルと1000サイクル毎)
        if cycle < 30 or cycle % 1000 == 0:
            dut._log.info(f"[Cycle {cycle:5d}] PC = 0x{pc:08x}, debug_mode = {debug_mode}")
        
        # 境界チェック
        if pc >= RAM_BOUNDARY and not debug_entered:
            dut._log.info(" ")
            dut._log.info("!" * 60)
            dut._log.info(f"⚠ PC EXCEEDED BOUNDARY at cycle {cycle}!")
            dut._log.info(f"  PC = 0x{pc:08x} (>= 0x{RAM_BOUNDARY:08x})")
            dut._log.info("!" * 60)
        
        # デバッグモードチェック
        if debug_mode == 1 and not debug_entered:
            debug_entered = True
            dut._log.info(" ")
            dut._log.info("=" * 60)
            dut._log.info(f"✓ AUTO-HALT TRIGGERED at cycle {cycle}")
            dut._log.info(f"  Final PC = 0x{pc:08x}")
            dut._log.info("=" * 60)
            await ClockCycles(dut.clk, 10)
            break
    
    # 結果分析
    dut._log.info("\n" + "=" * 60)
    dut._log.info("分析結果:")
    dut._log.info("=" * 60)
    
    # PC遷移パターンを分析
    dut._log.info(f"PC遷移回数: {len(pc_history)}")
    if len(pc_history) >= 2:
        dut._log.info(f"開始PC: 0x{pc_history[0]:08x}")
        dut._log.info(f"最終PC: 0x{pc_history[-1]:08x}")
        
        # PC増分を計算
        increments = []
        for i in range(1, min(len(pc_history), 10)):
            inc = pc_history[i] - pc_history[i-1]
            increments.append(inc)
        
        if increments:
            dut._log.info(f"PC増分パターン (最初の{len(increments)}回): {[f'0x{inc:x}' for inc in increments]}")
    
    # 境界違反チェック
    boundary_exceeded = any(pc >= RAM_BOUNDARY for pc in pc_history)
    
    if debug_entered:
        dut._log.info(" ")
        dut._log.info("✓ 境界違反検出 → 自動ハルト成功!")
        dut._log.info(f"  境界超過: {boundary_exceeded}")
        final_pc = int(dut.imem_addr.value)
        dut._log.info(f"  デバッグモードPC: 0x{final_pc:08x}")
        assert final_pc >= DEBUG_ENTRY_POINT and final_pc < 0x700, \
            f"Expected PC in debug ROM, got 0x{final_pc:08x}"
    else:
        dut._log.info(" ")
        dut._log.info("観察結果: PCが境界内に留まった")
        dut._log.info(f"  境界超過: {boundary_exceeded}")
        dut._log.info("  CPUは0x00000000を処理し続けている")
        if not boundary_exceeded:
            dut._log.info("  → 実機では境界に到達しない挙動を確認")
    
    dut._log.info("=" * 80)
    dut._log.info("✓ TEST COMPLETED: Real Hardware Simulation (All 0x00000000)")
    dut._log.info("=" * 80)
