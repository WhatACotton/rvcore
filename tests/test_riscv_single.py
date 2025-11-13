"""
Single RISC-V test execution with cocotb
Loads firmware.hex and monitors test completion via tohost register
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os
from pathlib import Path

# Verbosity control for Python-side logging (0 = minimal, 1 = normal, 2 = debug)
VERBOSE = int(os.getenv('RVCORE_VERBOSE', '0'))


def load_hex_file(filename):
    """Load instructions from a Verilog hex file with address support
    
    Returns a dictionary mapping address to data (32-bit words)
    """
    memory = {}
    current_addr = 0
    
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Skip empty lines and comments
            if not line or line.startswith('//'):
                continue
            
            # Check for address directive (@address)
            if line.startswith('@'):
                try:
                    current_addr = int(line[1:], 16)
                except ValueError:
                    pass
                continue
            
            # Remove inline comments
            if '//' in line:
                line = line.split('//')[0].strip()
            
            # Parse hex bytes (space-separated or continuous)
            hex_bytes = line.split()
            for hex_byte in hex_bytes:
                try:
                    byte_val = int(hex_byte, 16)
                    memory[current_addr] = byte_val
                    current_addr += 1
                except ValueError:
                    pass
    
    return memory


async def initialize_memory(dut, memory_dict):
    """Initialize memory using init interface
    
    Args:
        dut: Device under test
        memory_dict: Dictionary mapping byte address to byte value
    """
    dut.init_wen.value = 1
    await RisingEdge(dut.clk)
    
    # Convert byte-addressed memory to word-addressed (32-bit)
    # Group bytes into 32-bit words (little-endian)
    sorted_addrs = sorted(memory_dict.keys())
    
    if sorted_addrs:
        min_addr = sorted_addrs[0] & ~3  # Align to word boundary
        max_addr = sorted_addrs[-1]
        
        dut._log.info(f"Initializing memory: 0x{min_addr:08x} - 0x{max_addr:08x}")
        
        word_count = 0
        for word_addr in range(min_addr, max_addr + 4, 4):
            # Construct 32-bit word from 4 bytes (little-endian)
            word = 0
            for i in range(4):
                byte_addr = word_addr + i
                if byte_addr in memory_dict:
                    word |= (memory_dict[byte_addr] & 0xFF) << (i * 8)
            
            # Write to memory
            dut.init_addr.value = word_addr
            dut.init_data.value = word
            await RisingEdge(dut.clk)
            
            # Log first few instructions for debugging
            if word_count < 8:
                dut._log.info(f"  [0x{word_addr:08x}] = 0x{word:08x}")
            word_count += 1
        
        dut._log.info(f"Wrote {word_count} words to memory")
    
    dut.init_wen.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)


def find_tohost_address(test_name):
    """Find tohost address from disassembly file"""
    dis_file = Path(__file__).parent / "riscv_test_hex" / f"{test_name}.dis"
    if not dis_file.exists():
        return 0x000006c0  # Default fallback
    
    try:
        with open(dis_file, 'r') as f:
            for line in f:
                # Look for patterns like:
                # "00000480 <tohost>:" or
                # "  3c:   48302023                sw      gp,1152(zero) # 480 <tohost>"
                if '<tohost>' in line:
                    # Try to extract address from comment: "# 480 <tohost>"
                    if '#' in line:
                        parts = line.split('#')[1].strip().split()
                        if len(parts) >= 1:
                            addr_str = parts[0]
                            return int(addr_str, 16)
                    # Try to extract from label: "00000480 <tohost>:"
                    else:
                        addr_str = line.split()[0]
                        return int(addr_str, 16)
    except:
        pass
    
    return 0x000006c0  # Default fallback


def find_fail_pass_addresses(test_name):
    """Find fail and pass routine addresses from disassembly file
    
    Returns:
        tuple: (fail_addr, pass_addr) or (None, None) if not found
    """
    dis_file = Path(__file__).parent / "riscv_test_hex" / f"{test_name}.dis"
    if not dis_file.exists():
        return None, None
    
    fail_addr = None
    pass_addr = None
    
    try:
        with open(dis_file, 'r') as f:
            for line in f:
                # Look for patterns like: "00000444 <fail>:"
                if '<fail>:' in line:
                    addr_str = line.split()[0]
                    fail_addr = int(addr_str, 16)
                elif '<pass>:' in line:
                    addr_str = line.split()[0]
                    pass_addr = int(addr_str, 16)
                
                # Stop if we found both
                if fail_addr is not None and pass_addr is not None:
                    break
    except:
        pass
    
    return fail_addr, pass_addr


@cocotb.test()
async def test_riscv_program(dut):
    """Execute RISC-V test program and monitor tohost for completion"""
    
    test_name = os.getenv('TEST_NAME', 'unknown')
    tohost_addr = find_tohost_address(test_name)
    fail_addr, pass_addr = find_fail_pass_addresses(test_name)
    
    dut._log.info("="*60)
    dut._log.info(f"RISC-V Test: {test_name}")
    dut._log.info(f"tohost address: 0x{tohost_addr:08x} (from {test_name}.dis)")
    if fail_addr is not None and pass_addr is not None:
        dut._log.info(f"fail address: 0x{fail_addr:08x}, pass address: 0x{pass_addr:08x}")
    dut._log.info("="*60)
    
    # Start clock (100MHz)
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    
    # Initialize all signals
    dut.reset_n.value = 0
    dut.i_haltreq.value = 0
    dut.i_resetreq.value = 0
    dut.o_cpu_apb_pready.value = 1  # APB ready by default
    dut.o_cpu_apb_prdata.value = 0
    dut.o_cpu_apb_pslverr.value = 0
    dut.init_wen.value = 0
    dut.init_addr.value = 0
    dut.init_data.value = 0
    
    # Hold reset
    await ClockCycles(dut.clk, 10)
    
    # Load firmware from hex file
    hex_file = "firmware.hex"
    if not os.path.exists(hex_file):
        dut._log.error(f"Hex file not found: {hex_file}")
        assert False, f"Hex file not found: {hex_file}"
    
    dut._log.info(f"Loading firmware from {hex_file}")
    memory = load_hex_file(hex_file)
    dut._log.info(f"Loaded {len(memory)} bytes")
    
    # Initialize memory
    await initialize_memory(dut, memory)
    
    # Debug: Dump first few memory locations and verify key data
    dut._log.info("Memory initialization complete. Checking first instructions...")
    try:
        # Try to read PC value
        pc_val = int(dut.cpu.pc.value) if hasattr(dut, 'cpu') else 0
        dut._log.info(f"CPU PC after init: 0x{pc_val:08x}")
        
        # Check memory content at 0x450 (test data location)
        if hasattr(dut, 'dmem_bram_inst') and hasattr(dut.dmem_bram_inst, 'mem'):
            mem_0x450 = int(dut.dmem_bram_inst.mem[0x114].value)  # 0x450 >> 2 = 0x114
            dut._log.info(f"DMEM[0x114] (addr 0x450) = 0x{mem_0x450:08x} (expected 0x0FF000FF)")
        
        # Also check IMEM for comparison
        if hasattr(dut, 'imem_bram_inst') and hasattr(dut.imem_bram_inst, 'mem'):
            imem_0x450 = int(dut.imem_bram_inst.mem[0x114].value)  # Same address
            dut._log.info(f"IMEM[0x114] (addr 0x450) = 0x{imem_0x450:08x} (should also be 0x0FF000FF)")
    except Exception as e:
        dut._log.warning(f"Could not read memory: {e}")
    
    # Release reset
    dut.reset_n.value = 1
    dut._log.info("Reset released, starting execution...")
    
    # Debug: Monitor PC for first 50 cycles to see execution pattern
    dut._log.info("Monitoring PC progression...")
    for i in range(50):
        await RisingEdge(dut.clk)
        try:
            pc_val = int(dut.cpu.pc.value) if hasattr(dut.cpu, 'pc') else 0
            if i < 10 or i % 5 == 0:  # Log first 10 and every 5th cycle
                dut._log.info(f"  Cycle {i+1}: PC = 0x{pc_val:08x}")
        except:
            pass
    
    # Monitor both gp register (x3) and tohost for test results
    # Primary: gp register (standard RISC-V test method)
    # - gp = 0: test in progress
    # - gp = 1: all tests passed
    # - gp > 1: test failed
    # Fallback: tohost memory location
    # - tohost = 1: pass
    # - tohost > 1: fail
    
    max_cycles = 200000
    prev_gp_val = 0
    tohost_val = 0
    debug_load_count = 0
    first_test_mem_access = False  # Track first memory access in test
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        
        # Monitor gp register (x3) for test completion
        # RISC-V tests use gp register:
        # - gp = 0: test in progress
        # - gp = 1: all tests passed
        # - gp > 1: test failed (gp encodes the failing test case)
        try:
            if hasattr(dut, 'gp'):
                gp_val = int(dut.gp.value)
                
                    # Check if gp changed (test progress or completion)
                if gp_val != prev_gp_val:
                    # Check for completion:
                    # Pass: gp = 1
                    # Fail: gp >= 5 and odd (fail routine: gp = (test_num << 1) | 1)
                    # Test in progress: gp = 2,3,4,... (test number)
                    
                    # Log all gp changes to track test progression
                    pc = int(dut.cpu.pc.value) if hasattr(dut.cpu, 'pc') else 0
                    if gp_val >= 2 and gp_val <= 10:
                        # Log test transitions
                        x14_a4 = int(dut.cpu.register_file[14].value) if hasattr(dut.cpu, 'register_file') else 0
                        x7_t2 = int(dut.cpu.register_file[7].value) if hasattr(dut.cpu, 'register_file') else 0
                    # Check for failure: odd gp value AND PC in fail routine (0x3a8-0x3c4)
                    pc = int(dut.cpu.pc.value) if hasattr(dut.cpu, 'pc') else 0
                    in_fail_routine = (pc >= 0x3a8 and pc < 0x3c4)
                    if (gp_val & 1) == 1 and gp_val > 1 and in_fail_routine:
                        try:
                            pc = int(dut.cpu.pc.value) if hasattr(dut.cpu, 'pc') else 0
                            dmem_addr = int(dut.dmem_addr.value) if hasattr(dut, 'dmem_addr') else 0
                            dmem_rdata = int(dut.dmem_rdata.value) if hasattr(dut, 'dmem_rdata') else 0
                            proc_state = int(dut.cpu.proc_state.value) if hasattr(dut.cpu, 'proc_state') else -1
                            
                            dut._log.info(f"  CPU PC = 0x{pc:08x}, proc_state = {proc_state}")
                            dut._log.info(f"  Last dmem_addr = 0x{dmem_addr:08x}, dmem_rdata = 0x{dmem_rdata:08x}")
                            
                            # Check load instruction processing
                            if hasattr(dut.cpu, 'mem_inst'):
                                mem_inst = int(dut.cpu.mem_inst.value) if hasattr(dut.cpu, 'mem_inst') else 0
                                mem_addr_saved = int(dut.cpu.mem_addr_saved.value) if hasattr(dut.cpu, 'mem_addr_saved') else 0
                                wb_data = int(dut.cpu.wb_data.value) if hasattr(dut.cpu, 'wb_data') else 0
                                dut._log.info(f"  Load processing: mem_inst=0x{mem_inst:08x}, mem_addr_saved=0x{mem_addr_saved:08x}, wb_data=0x{wb_data:08x}")
                            
                            # Check what's actually at address 0x450
                            if hasattr(dut, 'dmem_bram_inst') and hasattr(dut.dmem_bram_inst, 'mem'):
                                word_addr_450 = 0x114  # 0x450 >> 2
                                mem_val_450 = int(dut.dmem_bram_inst.mem[word_addr_450].value)
                                dut._log.info(f"  DMEM[0x{word_addr_450:03x}] (addr 0x450) = 0x{mem_val_450:08x}")
                                
                                if dmem_addr >= 0x000 and dmem_addr < 0x1000:
                                    word_addr = (dmem_addr >> 2) & 0xFFF
                                    mem_val = int(dut.dmem_bram_inst.mem[word_addr].value)
                                    dut._log.info(f"  DMEM[0x{word_addr:03x}] (addr 0x{dmem_addr:08x}) = 0x{mem_val:08x}")
                            
                            # Try to read CPU registers for more context
                            if hasattr(dut.cpu, 'register_file'):
                                x2_sp = int(dut.cpu.register_file[2].value)  # sp
                                x14_a4 = int(dut.cpu.register_file[14].value)  # a4 (result register)
                                x7_t2 = int(dut.cpu.register_file[7].value)  # t2 (expected value)
                                dut._log.info(f"  Registers: sp(x2)=0x{x2_sp:08x}, a4(x14)=0x{x14_a4:08x}, t2(x7)=0x{x7_t2:08x}")
                        except Exception as e:
                            dut._log.warning(f"Could not dump debug info: {e}")
                    elif gp_val == 1:
                        dut._log.info("="*60)
                        dut._log.info(f"RISC-V TEST PASSED after {cycle + 1} cycles")
                        dut._log.info(f"gp (x3) = {gp_val}")
                        dut._log.info("="*60)
                        return  # Test passed!
                    
                    # Check for failure: PC in fail routine
                    # Fail routine address is extracted from disassembly file
                    # Normal test progression sets gp to test numbers (2, 3, 4, ..., 22, 23, ...)
                    # which can be odd, so we can't rely on gp being odd alone
                    test_failed = False
                    test_case = 0
                    pc = 0
                    try:
                        pc = int(dut.cpu.pc.value)
                        
                        # Use dynamically extracted fail address if available
                        if fail_addr is not None and pass_addr is not None:
                            in_fail_routine = (pc >= fail_addr and pc < pass_addr)
                        else:
                            # Fallback to old fixed range (for backward compatibility)
                            in_fail_routine = (pc >= 0x40c and pc < 0x428)
                        
                        if (gp_val & 1) == 1 and gp_val > 1 and in_fail_routine:
                            # Decode test case from gp value
                            # The fail code does: gp = (test_num << 1) | 1
                            # So test_num = gp >> 1
                            test_case = gp_val >> 1
                            test_failed = True
                    except Exception as e:
                        dut._log.warning(f"Could not check PC for failure detection: {e}")
                    
                    if test_failed:
                        dut._log.error("="*60)
                        dut._log.error(f"RISC-V TEST FAILED after {cycle + 1} cycles")
                        dut._log.error(f"gp (x3) = {gp_val} (0x{gp_val:08x}), PC = 0x{pc:08x}")
                        dut._log.error(f"Test case #{test_case} failed")
                        dut._log.error("="*60)
                        assert False, f"Test '{test_name}' failed: test case #{test_case}"
                
                prev_gp_val = gp_val
        except (AttributeError, ValueError) as e:
            pass
        
      
        
        # Progress indicator every 10000 cycles
        if (cycle + 1) % 10000 == 0:
            dut._log.info(f"  ... {cycle + 1} cycles (gp=0x{prev_gp_val:08x})")
    
    # Test timed out - dump diagnostic info
    dut._log.error("="*60)
    dut._log.error(f"Test timeout after {max_cycles} cycles")
    dut._log.error("RISC-V TEST FAILED: TIMEOUT")
    try:
        pc = int(dut.cpu.pc.value) if hasattr(dut.cpu, 'pc') else 0
        state = int(dut.cpu.state.value) if hasattr(dut.cpu, 'state') else 0
        inst = int(dut.cpu.inst.value) if hasattr(dut.cpu, 'inst') else 0
        gp_val = int(dut.gp.value) if hasattr(dut, 'gp') else 0
        dut._log.error(f"Last PC: 0x{pc:08x}, State: {state}, Inst: 0x{inst:08x}, gp: {gp_val}")
    except Exception as e:
        dut._log.error(f"Could not dump state: {e}")
    dut._log.error("="*60)
    assert False, f"Test '{test_name}' timed out after {max_cycles} cycles"


if __name__ == "__main__":
    pass
