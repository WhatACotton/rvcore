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
    """Find tohost address from hex file
    
    The tohost address is typically in the second section of the hex file.
    We scan the hex file for @address directives.
    """
    hex_file = Path(__file__).parent / "firmware.hex"
    
    # Try to find tohost from firmware.hex (the actual loaded file)
    if hex_file.exists():
        try:
            addresses = []
            with open(hex_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('@'):
                        addr = int(line[1:], 16)
                        addresses.append(addr)
            
            # Second section is typically tohost/fromhost data section
            if len(addresses) >= 2:
                tohost_addr = addresses[1]
                return tohost_addr
        except Exception as e:
            pass
    
    # Fallback: try disassembly file
    dis_file = Path(__file__).parent / "riscv_test_hex" / f"{test_name}.dis"
    if dis_file.exists():
        try:
            with open(dis_file, 'r') as f:
                for line in f:
                    if '<tohost>' in line:
                        if '#' in line:
                            parts = line.split('#')[1].strip().split()
                            if len(parts) >= 1:
                                addr_str = parts[0]
                                return int(addr_str, 16)
                        else:
                            addr_str = line.split()[0]
                            return int(addr_str, 16)
        except:
            pass
    
    return 0x00000480  # Common RISC-V test default


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
    
    # Debug: Check what's actually in firmware.hex
    hex_file = Path(__file__).parent / "firmware.hex"
    if hex_file.exists():
        with open(hex_file, 'r') as f:
            sections = [line.strip() for line in f if line.strip().startswith('@')]
        dut._log.info(f"firmware.hex sections: {sections}")
    
    dut._log.info("="*60)
    dut._log.info(f"RISC-V Test: {test_name}")
    dut._log.info(f"tohost address: 0x{tohost_addr:08x} (detected from firmware.hex)")
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
    
    # Debug: Monitor PC and memory writes for first 100 cycles to see execution pattern
    dut._log.info("Monitoring PC progression and memory writes...")
    for i in range(100):
        await RisingEdge(dut.clk)
        try:
            pc_val = int(dut.cpu.pc.value) if hasattr(dut.cpu, 'pc') else 0
            if i < 10 or i % 5 == 0:  # Log first 10 and every 5th cycle
                dut._log.info(f"  Cycle {i+1}: PC = 0x{pc_val:08x}")
            
            # Monitor ALL memory writes during startup
            if hasattr(dut, 'dmem_wvalid') and hasattr(dut, 'dmem_addr') and hasattr(dut, 'dmem_wdata'):
                dmem_wvalid = int(dut.dmem_wvalid.value)
                if dmem_wvalid != 0:
                    dmem_addr = int(dut.dmem_addr.value)
                    dmem_wdata = int(dut.dmem_wdata.value)
                    dut._log.info(f"  Cycle {i+1}: MEM WRITE addr=0x{dmem_addr:08x}, data=0x{dmem_wdata:08x}, wvalid={dmem_wvalid}")
        except:
            pass
    
    # Monitor tohost register for test completion
    # RISC-V test standard:
    # - tohost = 0: test in progress
    # - tohost = 1: test passed
    # - tohost > 1: test failed (value encodes failure info)
    
    dut._log.info(f"Primary tohost address: 0x{tohost_addr:08x}")
    dut._log.info("Also monitoring RTL tohost output register")
    
    max_cycles = 200000
    prev_tohost = 0
    prev_gp_val = 0
    tohost_write_detected = False
    prev_pc = 0
    same_pc_count = 0
    
    # Alternative: also check memory at tohost address
    # Calculate word address for memory access
    tohost_word_addr = tohost_addr >> 2
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        # Detect infinite loops (PC stuck at same location)
        try:
            if hasattr(dut.cpu, 'pc'):
                current_pc = int(dut.cpu.pc.value)
                if current_pc == prev_pc:
                    same_pc_count += 1
                    if same_pc_count == 1000:
                        inst = int(dut.cpu.inst.value) if hasattr(dut.cpu, 'inst') else 0
                        tohost_val = int(dut.tohost.value) if hasattr(dut, 'tohost') else -1
                        gp_val = int(dut.gp.value) if hasattr(dut, 'gp') else 0
                        dut._log.warning(f"PC stuck at 0x{current_pc:08x} for 1000 cycles")
                        dut._log.warning(f"  inst=0x{inst:08x}, tohost=0x{tohost_val:08x}, gp=0x{gp_val:08x}")
                        # Check if we're waiting for something
                        proc_state = int(dut.cpu.proc_state.value) if hasattr(dut.cpu, 'proc_state') else -1
                        dut._log.warning(f"  proc_state = {proc_state}")
                        
                        # This might be the self-loop after test completion
                        # Check if tohost has a value indicating completion
                        if tohost_val == 1:
                            dut._log.info("="*60)
                            dut._log.info(f"RISC-V TEST PASSED (detected via infinite loop with tohost=1)")
                            dut._log.info(f"Completed at cycle {cycle + 1}, PC stuck at 0x{current_pc:08x}")
                            dut._log.info("="*60)
                            return  # Test passed!
                        elif tohost_val > 1:
                            test_case = tohost_val >> 1
                            dut._log.error("="*60)
                            dut._log.error(f"RISC-V TEST FAILED (detected via infinite loop with tohost={tohost_val})")
                            dut._log.error(f"Test case #{test_case} failed")
                            dut._log.error("="*60)
                            assert False, f"Test '{test_name}' failed: test case #{test_case}"
                else:
                    same_pc_count = 0
                prev_pc = current_pc
        except (AttributeError, ValueError) as e:
            pass
        
        # Check tohost register for test completion
        # Method 1: Check RTL's tohost output register
        tohost_val = 0
        try:
            if hasattr(dut, 'tohost'):
                tohost_val = int(dut.tohost.value)
                
                # Log any change in tohost value
                if tohost_val != prev_tohost:
                    dut._log.info(f"RTL tohost register changed at cycle {cycle + 1}: 0x{prev_tohost:08x} -> 0x{tohost_val:08x}")
        except (AttributeError, ValueError) as e:
            pass
        
        # Method 2: If RTL tohost is still 0, try reading directly from memory
        if tohost_val == 0:
            try:
                if hasattr(dut, 'dmem_bram_inst') and hasattr(dut.dmem_bram_inst, 'mem'):
                    if tohost_word_addr < 4096:  # Within DMEM range
                        mem_tohost = int(dut.dmem_bram_inst.mem[tohost_word_addr].value)
                        if mem_tohost != 0:
                            tohost_val = mem_tohost
                            if tohost_val != prev_tohost:
                                dut._log.info(f"Memory tohost[0x{tohost_addr:08x}] changed at cycle {cycle + 1}: 0x{prev_tohost:08x} -> 0x{tohost_val:08x}")
            except (AttributeError, ValueError, IndexError) as e:
                pass
        
        # Check if test completed
        try:
            if tohost_val != prev_tohost and tohost_val != 0:
                if not tohost_write_detected:
                    dut._log.info(f"tohost write detected at cycle {cycle + 1}: tohost = {tohost_val} (0x{tohost_val:08x})")
                    tohost_write_detected = True
                if tohost_val == 1:
                        # Test passed
                        dut._log.info("="*60)
                        dut._log.info(f"RISC-V TEST PASSED after {cycle + 1} cycles")
                        dut._log.info(f"tohost = {tohost_val}")
                        dut._log.info("="*60)
                        return  # Test passed!
                else:
                    # Test failed - tohost encodes failure info
                    # Typically: tohost = (test_num << 1) | 1
                    test_case = tohost_val >> 1
                    gp_val = int(dut.gp.value) if hasattr(dut, 'gp') else 0
                    pc = int(dut.cpu.pc.value) if hasattr(dut.cpu, 'pc') else 0
                    
                    # Read CSR values for debugging
                    try:
                        mtvec = int(dut.cpu.mtvec.value) if hasattr(dut.cpu, 'mtvec') else 0
                        mcause = int(dut.cpu.mcause.value) if hasattr(dut.cpu, 'mcause') else 0
                        mepc = int(dut.cpu.mepc.value) if hasattr(dut.cpu, 'mepc') else 0
                        mstatus = int(dut.cpu.mstatus.value) if hasattr(dut.cpu, 'mstatus') else 0
                    except:
                        mtvec = mcause = mepc = mstatus = 0
                    
                    dut._log.error("="*60)
                    dut._log.error(f"RISC-V TEST FAILED after {cycle + 1} cycles")
                    dut._log.error(f"tohost = {tohost_val} (0x{tohost_val:08x})")
                    dut._log.error(f"gp (x3) = {gp_val}, PC = 0x{pc:08x}")
                    dut._log.error(f"Test case #{test_case} failed")
                    dut._log.error(f"CSR state: mtvec=0x{mtvec:08x}, mcause=0x{mcause:08x}, mepc=0x{mepc:08x}, mstatus=0x{mstatus:08x}")
                    dut._log.error("="*60)
                    assert False, f"Test '{test_name}' failed: test case #{test_case}"
                
                    prev_tohost = tohost_val
        except (AttributeError, ValueError) as e:
            pass
        
        # Also track gp for debugging
        try:
            if hasattr(dut, 'gp'):
                gp_val = int(dut.gp.value)
                if gp_val != prev_gp_val:
                    prev_gp_val = gp_val
        except (AttributeError, ValueError) as e:
            pass
        
        # Monitor memory writes to detect tohost stores (debug)
        try:
            if hasattr(dut, 'dmem_wvalid') and hasattr(dut, 'dmem_addr') and hasattr(dut, 'dmem_wdata'):
                dmem_wvalid = int(dut.dmem_wvalid.value)
                if dmem_wvalid != 0:
                    dmem_addr = int(dut.dmem_addr.value)
                    dmem_wdata = int(dut.dmem_wdata.value)
                    # Log writes to tohost area
                    if dmem_addr >= 0x6c0 and dmem_addr < 0x700:
                        dut._log.info(f"Memory write at cycle {cycle + 1}: addr=0x{dmem_addr:08x}, data=0x{dmem_wdata:08x}")
        except (AttributeError, ValueError) as e:
            pass
        
      
        
        # Progress indicator every 10000 cycles
        if (cycle + 1) % 10000 == 0:
            dut._log.info(f"  ... {cycle + 1} cycles (tohost=0x{prev_tohost:08x}, gp=0x{prev_gp_val:08x})")
    
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
