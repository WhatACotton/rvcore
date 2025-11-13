#!/usr/bin/env python3
"""
RISC-V Test Suite Runner
Runs all RISC-V tests and reports results
"""

import os
import sys
import subprocess
import glob
from pathlib import Path

def run_single_test(test_name, hex_file):
    """Run a single RISC-V test using cocotb"""
    
    # Set environment variables
    env = os.environ.copy()
    env['TEST_NAME'] = test_name
    env['HEX_FILE'] = hex_file
    env['MODULE'] = 'test_rvcore'
    env['TESTCASE'] = 'test_riscv_official'
    env['COCOTB_REDUCED_LOG_FMT'] = '1'
    env['COCOTB_LOG_LEVEL'] = 'ERROR'
    env['SIM'] = 'verilator'
    env['WAVES'] = '0'
    
    try:
        # Run cocotb test
        result = subprocess.run(
            ['make', '-s'],
            env=env,
            capture_output=True,
            text=True,
            timeout=30  # 30 second timeout per test
        )
        
        # Check if test passed
        output = result.stdout + result.stderr
        if 'test_riscv_official passed' in output or 'PASSED' in output:
            return True, None
        else:
            # Extract error message if available
            lines = output.split('\n')
            error_lines = [l for l in lines if 'FAIL' in l or 'Error' in l or 'assert' in l.lower()]
            error_msg = '\n'.join(error_lines[:3]) if error_lines else 'Test failed'
            return False, error_msg
            
    except subprocess.TimeoutExpired:
        return False, 'Timeout'
    except Exception as e:
        return False, str(e)


def main():
    """Main test runner"""
    
    # Find all test hex files
    pattern = sys.argv[1] if len(sys.argv) > 1 else 'rv32ui-p-*.hex'
    hex_dir = Path('riscv_test_hex')
    
    if not hex_dir.exists():
        print("Error: riscv_test_hex directory not found")
        print("Run './convert_riscv_tests.sh' first")
        sys.exit(1)
    
    test_files = sorted(glob.glob(str(hex_dir / pattern)))
    
    if not test_files:
        print(f"No tests found matching pattern: {pattern}")
        sys.exit(1)
    
    print("="*60)
    print(f"RISC-V Test Suite Runner")
    print(f"Found {len(test_files)} tests")
    print("="*60)
    print()
    
    passed = []
    failed = []
    
    for hex_file in test_files:
        test_name = Path(hex_file).stem
        print(f"Running {test_name}... ", end='', flush=True)
        
        success, error = run_single_test(test_name, hex_file)
        
        if success:
            print("✓ PASSED")
            passed.append(test_name)
        else:
            print(f"✗ FAILED")
            if error and len(error) < 100:
                print(f"  Error: {error}")
            failed.append(test_name)
    
    # Summary
    print()
    print("="*60)
    print(f"Test Results")
    print("="*60)
    print(f"Total:  {len(test_files)}")
    print(f"Passed: {len(passed)} ({100*len(passed)//len(test_files)}%)")
    print(f"Failed: {len(failed)}")
    
    if failed:
        print()
        print("Failed tests:")
        for name in failed:
            print(f"  - {name}")
    
    print("="*60)
    
    # Exit with error if any test failed
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
