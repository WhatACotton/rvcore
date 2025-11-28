#!/usr/bin/env python3
"""
Convert byte-oriented hex file to 32-bit word format for $readmemh

Input: Verilog hex file with byte data and @ directives (e.g., @00000000)
Output: Verilog hex file with 32-bit words in little-endian format

Usage: python3 convert_hex_to_words.py input.hex output.hex
"""

import sys
import re

def convert_hex_to_words(input_file, output_file, base_addr=0x10000):
    """Convert byte-oriented hex to 32-bit word hex"""
    
    # Read all bytes with their addresses
    memory = {}
    current_addr = 0
    
    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            
            # Skip empty lines and comments
            if not line or line.startswith('//'):
                continue
            
            # Handle address directive @XXXXXXXX
            if line.startswith('@'):
                addr_str = line[1:].strip()
                current_addr = int(addr_str, 16)
                continue
            
            # Parse hex bytes (space or no space separated)
            # Remove any non-hex characters except whitespace
            hex_data = re.findall(r'[0-9a-fA-F]{2}', line)
            
            for byte_str in hex_data:
                byte_val = int(byte_str, 16)
                memory[current_addr] = byte_val
                current_addr += 1
    
    if not memory:
        print(f"Warning: No data found in {input_file}", file=sys.stderr)
        # Create empty output file
        with open(output_file, 'w') as f:
            pass
        return
    
    # Convert bytes to 32-bit words (little-endian)
    min_addr = min(memory.keys())
    max_addr = max(memory.keys())
    
    # Align to word boundary
    word_start = (min_addr // 4) * 4
    word_end = ((max_addr + 3) // 4) * 4
    
    words = {}
    for word_addr in range(word_start, word_end, 4):
        # Collect 4 bytes (little-endian: byte0=LSB, byte3=MSB)
        b0 = memory.get(word_addr + 0, 0)
        b1 = memory.get(word_addr + 1, 0)
        b2 = memory.get(word_addr + 2, 0)
        b3 = memory.get(word_addr + 3, 0)
        
        # Form 32-bit word: {b3, b2, b1, b0}
        word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
        words[word_addr] = word
    
    # Write output in Verilog hex format
    with open(output_file, 'w') as f:
        f.write("// 32-bit word hex file for $readmemh\n")
        f.write(f"// Converted from: {input_file}\n")
        f.write("// Format: one 32-bit word per line (little-endian)\n")
        f.write("\n")
        
        # Group contiguous addresses
        sorted_addrs = sorted(words.keys())
        
        if not sorted_addrs:
            return
        
        # Start from first word address
        # Convert all addresses to word indices relative to base_addr
        # BRAM $readmemh expects continuous word indices starting from 0
        # without @ directives
        
        # Calculate word index range
        min_word_addr = sorted_addrs[0]
        max_word_addr = sorted_addrs[-1]
        
        # Convert byte addresses to word indices (relative to base_addr)
        min_word_index = (min_word_addr - base_addr) // 4 if min_word_addr >= base_addr else min_word_addr // 4
        max_word_index = (max_word_addr - base_addr) // 4 if max_word_addr >= base_addr else max_word_addr // 4
        
        # Write all words, filling gaps with zeros
        # Start from min_word_index, not 0, to avoid unnecessary padding
        for word_index in range(min_word_index, max_word_index + 1):
            # Convert word index back to byte address
            byte_addr = base_addr + (word_index * 4)
            
            if byte_addr in words:
                f.write(f"{words[byte_addr]:08x}\n")
            else:
                # Fill gap with zero
                f.write(f"00000000\n")
    
    print(f"Converted {len(memory)} bytes to {len(words)} words")
    print(f"Address range: 0x{min_addr:08x} - 0x{max_addr:08x}")
    print(f"Output: {output_file}")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.hex output.hex", file=sys.stderr)
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    try:
        convert_hex_to_words(input_file, output_file)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
