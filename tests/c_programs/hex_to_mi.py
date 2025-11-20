#!/usr/bin/env python3
"""
Generate `.mi` meminit file from compiled `.hex` file produced by compile.sh

Usage: python3 hex_to_mi.py <input.hex> <output.mi>
"""
import sys

if len(sys.argv) < 3:
    print("Usage: hex_to_mi.py <input.hex> <output.mi>")
    sys.exit(2)

infile = sys.argv[1]
outfile = sys.argv[2]
ADDR_DEPTH = 4096

with open(infile, 'r') as f:
    lines = [l.strip() for l in f if l.strip()]

with open(outfile, 'w') as out:
    out.write("#File_format=Hex\n")
    out.write(f"#Address_depth={ADDR_DEPTH}\n")
    out.write("#Data_width=32\n")
    # write existing hex lines
    for l in lines:
        out.write(l + "\n")

    # pad with zeros to reach the required depth
    pad = ADDR_DEPTH - len(lines)
    if pad < 0:
        sys.stderr.write("Warning: hex file has more entries than address depth; truncating.\n")
        pad = 0
    for _ in range(pad):
        out.write("00000000\n")

print(f"{outfile} created from {infile} with {len(lines)} entries and {pad} padding lines")
