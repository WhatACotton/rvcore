"""
Test to reproduce memory contamination issue (0x2 garbage in memory reads).
This simulates GDB reading CPU memory through Debug Module.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.binary import BinaryValue
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tb_coco', 'common'))

async def reset_dut(dut):
    """Reset the DUT"""
    dut.reset_n.value = 0
    await Timer(100, units='ns')
    dut.reset_n.value = 1
    await Timer(100, units='ns')

async def write_csr(dut, csr_addr, value):
    """Write to CSR via debug APB interface"""
    # This is a simplified version - actual implementation depends on APB interface
    pass

async def read_memory_via_progbuf(dut, addr):
    """
    Read memory via Program Buffer (simulating GDB memory read).
    Returns the value read from memory.
    """
    # 1. Halt the CPU (set dmcontrol.haltreq)
    # 2. Wait for CPU to be halted
    # 3. Write address to x9 (GPR) via abstract command
    # 4. Write "lw x8, 0(x9)" to progbuf[0]
    # 5. Execute progbuf
    # 6. Read x8 via abstract command to data0
    # 7. Read data0
    
    # For this test, we'll directly access CPU memory interface
    # to see if contamination occurs
    return 0  # Placeholder

@cocotb.test()
async def test_memory_read_contamination(dut):
    """
    Test memory reads at various addresses to detect contamination pattern.
    Reproduces the GDB memory dump issue where:
    - Address mod 4 = 0: returns 0x00000000 (correct)
    - Address mod 4 = 1: returns 0x00000002 (contaminated)
    - Address mod 4 = 2: returns 0x00000002 (contaminated)
    - Address mod 4 = 3: returns 0x000008c8 or other values (contaminated)
    """
    
    # Start clock
    clock = Clock(dut.clk, 10, units='ns')  # 100 MHz
    cocotb.start_soon(clock.start())
    
    # Reset DUT
    await reset_dut(dut)
    
    dut._log.info("=" * 60)
    dut._log.info("Memory Contamination Test - Reproducing GDB Issue")
    dut._log.info("=" * 60)
    
    # Test addresses (uninitialized memory region)
    test_addresses = [
        0x1000, 0x1004, 0x1008, 0x100C,
        0x1010, 0x1014, 0x1018, 0x101C,
        0x2000, 0x2004, 0x2008, 0x200C,
    ]
    
    contamination_detected = []
    
    for addr in test_addresses:
        mod4 = addr % 4
        
        # TODO: Implement actual memory read via debug module
        # For now, just log the pattern we're looking for
        
        dut._log.info(f"Testing address 0x{addr:08X} (mod 4 = {mod4})")
        
        # Expected pattern based on GDB dump:
        if mod4 == 0:
            expected = "0x00000000 or valid data"
        elif mod4 == 1 or mod4 == 2:
            expected = "Should be clean, but GDB shows 0x00000002"
        else:  # mod4 == 3
            expected = "Should be clean, but GDB shows 0x000008c8 or similar"
        
        dut._log.info(f"  Expected pattern: {expected}")
    
    # Wait some time
    await Timer(1000, units='ns')
    
    dut._log.info("=" * 60)
    dut._log.info("Test complete - check diagnostic output from RTL")
    dut._log.info("Look for [DMEM_WRITE] and [DMEM_READ] messages")
    dut._log.info("=" * 60)


@cocotb.test()
async def test_direct_bram_access(dut):
    """
    Direct test of BRAM to check if contamination is in BRAM itself
    or in the read/write path.
    """
    
    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut._log.info("=" * 60)
    dut._log.info("Direct BRAM Access Test")
    dut._log.info("=" * 60)
    
    # Try to access BRAM signals if available
    try:
        # Check if we can read unified_bram_dout
        if hasattr(dut, 'unified_bram_dout'):
            dut._log.info("BRAM output accessible: unified_bram_dout")
            
            # Monitor BRAM for several cycles
            for i in range(20):
                await RisingEdge(dut.clk)
                
                if hasattr(dut, 'unified_bram_addr'):
                    addr = dut.unified_bram_addr.value
                    dout = dut.unified_bram_dout.value
                    
                    dut._log.info(f"Cycle {i}: BRAM[0x{addr:03X}] = 0x{dout:08X}")
                    
                    # Check for contamination pattern
                    if int(dout) & 0x3 == (int(addr) & 0x3):
                        dut._log.warning(f"  CONTAMINATION: Lower 2 bits match!")
        else:
            dut._log.warning("Cannot access BRAM signals - may need to add to hierarchy")
            
    except Exception as e:
        dut._log.error(f"Error accessing BRAM: {e}")
    
    await Timer(1000, units='ns')


@cocotb.test()
async def test_cpu_memory_pattern(dut):
    """
    Test CPU memory access pattern to see if byte/halfword access
    causes contamination through RMW (Read-Modify-Write) cycles.
    """
    
    clock = Clock(dut.clk, 10, units='ns')
    cocotb.start_soon(clock.start())
    
    await reset_dut(dut)
    
    dut._log.info("=" * 60)
    dut._log.info("CPU Memory Access Pattern Test")
    dut._log.info("Checking for RMW contamination in byte/halfword stores")
    dut._log.info("=" * 60)
    
    # Monitor dmem interface
    if hasattr(dut, 'dmem_addr') and hasattr(dut, 'dmem_wdata'):
        dut._log.info("Monitoring dmem_addr and dmem_wdata...")
        
        for i in range(100):
            await RisingEdge(dut.clk)
            
            # Check if there's a memory write
            if hasattr(dut, 'cpu_dmem_wvalid'):
                wvalid = dut.cpu_dmem_wvalid.value
                if int(wvalid) != 0:
                    addr = int(dut.dmem_addr.value)
                    wdata = int(dut.dmem_wdata.value)
                    
                    dut._log.info(f"DMEM Write: addr=0x{addr:08X} data=0x{wdata:08X}")
                    
                    # Check for suspicious pattern
                    if (wdata & 0x3) == (addr & 0x3) and (wdata & 0x3) != 0:
                        dut._log.error(f"  CONTAMINATION DETECTED: wdata[1:0]={wdata&0x3} == addr[1:0]={addr&0x3}")
    
    await Timer(5000, units='ns')
    
    dut._log.info("=" * 60)
    dut._log.info("Monitor complete")
    dut._log.info("=" * 60)
