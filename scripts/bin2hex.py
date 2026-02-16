#!/usr/bin/env python3
# ============================================================================
# bin2hex.py — Convert a flat binary to a 32-bit word hex file
# ============================================================================
# Produces output suitable for $readmemh with a 32-bit-wide memory array.
# Each output line is one 8-hex-digit (little-endian) word.
#
# Usage:
#   python3 bin2hex.py <input.bin> <output.hex>
# ============================================================================

import sys
import struct


def bin2hex(bin_path: str, hex_path: str):
    with open(bin_path, "rb") as f:
        data = f.read()

    # Pad to 4-byte boundary
    while len(data) % 4 != 0:
        data += b"\x00"

    with open(hex_path, "w") as f:
        for i in range(0, len(data), 4):
            word = struct.unpack("<I", data[i : i + 4])[0]
            f.write(f"{word:08x}\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.hex>", file=sys.stderr)
        sys.exit(1)
    bin2hex(sys.argv[1], sys.argv[2])
