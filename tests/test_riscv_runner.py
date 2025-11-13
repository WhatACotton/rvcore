"""
Single RISC-V test execution with cocotb
Loads firmware.hex and monitors test completion via tohost register
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles
import os
from pathlib import Path


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


@cocotb.test()
async def test_riscv_program(dut):
    """Execute RISC-V test program and monitor tohost for completion"""
    
    test_name = os.getenv('TEST_NAME', 'unknown')
    tohost_addr = find_tohost_address(test_name)
    
    dut._log.info("="*60)
    dut._log.info(f"RISC-V Test: {test_name}")
    dut._log.info(f"tohost address: 0x{tohost_addr:08x} (from {test_name}.dis)")
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
    
    # Debug: Dump first few memory locations
    dut._log.info("Memory initialization complete. Checking first instructions...")
    try:
        # Try to read PC value
        pc_val = int(dut.cpu.pc.value) if hasattr(dut, 'cpu') else 0
        dut._log.info(f"CPU PC after init: 0x{pc_val:08x}")
    except:
        pass
    
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
    
    # Monitor memory writes to tohost address directly
    # tohost = 1: pass, tohost > 1: fail (indicates failing test case number)
    
    max_cycles = 200000
    tohost_seen_nonzero = False
    tohost_val = 0
    
    for cycle in range(max_cycles):
        await RisingEdge(dut.clk)
        
        # Monitor memory writes to detect tohost writes
        try:
            if hasattr(dut, 'cpu_dmem_wvalid') and int(dut.cpu_dmem_wvalid.value) != 0:
                dmem_addr = int(dut.dmem_addr.value) if hasattr(dut, 'dmem_addr') else 0
                dmem_wdata = int(dut.dmem_wdata.value) if hasattr(dut, 'dmem_wdata') else 0
                
                # Check if writing to tohost
                if dmem_addr == tohost_addr:
                    tohost_val = dmem_wdata
                    if not tohost_seen_nonzero:
                        dut._log.info(f"  [Cycle {cycle+1}] tohost write: addr=0x{dmem_addr:08x}, data=0x{dmem_wdata:08x}")
                        tohost_seen_nonzero = True
                    
                    # Check test result
                    if tohost_val == 1:
                        dut._log.info("="*60)
                        dut._log.info(f"RISC-V TEST PASSED after {cycle + 1} cycles")
                        dut._log.info(f"tohost = {tohost_val}")
                        dut._log.info("="*60)
                        return  # Test passed!
                    elif tohost_val > 1:
                        test_case = tohost_val >> 1
                        dut._log.error("="*60)
                        dut._log.error(f"RISC-V TEST FAILED after {cycle + 1} cycles")
                        dut._log.error(f"tohost = {tohost_val} (0x{tohost_val:08x})")
                        dut._log.error(f"Test case #{test_case} failed")
                        dut._log.error("="*60)
                        assert False, f"Test '{test_name}' failed: test case #{test_case}"
        except (AttributeError, ValueError) as e:
            pass
        
        # Progress indicator every 10000 cycles
        if (cycle + 1) % 10000 == 0:
            dut._log.info(f"  ... {cycle + 1} cycles (tohost=0x{tohost_val:08x})")
    
    # Test timed out
    dut._log.error("="*60)
    dut._log.error(f"Test timeout after {max_cycles} cycles")
    dut._log.error("RISC-V TEST FAILED: TIMEOUT")
    dut._log.error("="*60)
    assert False, f"Test '{test_name}' timed out after {max_cycles} cycles"


if __name__ == "__main__":
    pass
