#!/usr/bin/env python3
"""Convert Verilog hex file from byte-level to 32-bit word-level format.

objcopy -O verilog produces byte-addressed hex, but $readmemh with a
32-bit-wide memory array expects 32-bit words.  This script packs
consecutive little-endian bytes into 32-bit words.

Usage:
    python3 verilog_byte2word.py input.hex output.hex
"""

import sys

def convert(in_path, out_path):
    with open(in_path, "r") as f:
        content = f.read()

    out_lines = []
    byte_addr = 0
    byte_buf = []

    def flush(buf, start_addr):
        # Pad to 4-byte alignment
        while len(buf) % 4 != 0:
            buf.append(0)
        word_addr = start_addr // 4
        out_lines.append("@{:08x}".format(word_addr))
        for i in range(0, len(buf), 4):
            word = buf[i] | (buf[i+1] << 8) | (buf[i+2] << 16) | (buf[i+3] << 24)
            out_lines.append("{:08x}".format(word))

    for line in content.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        if line.startswith("@"):
            if byte_buf:
                flush(byte_buf, byte_addr)
                byte_buf = []
            byte_addr = int(line[1:], 16)
        else:
            for tok in line.split():
                byte_buf.append(int(tok, 16))

    if byte_buf:
        flush(byte_buf, byte_addr)

    with open(out_path, "w") as f:
        f.write("\n".join(out_lines) + "\n")

    n_words = len([l for l in out_lines if not l.startswith("@")])
    print("Converted {} bytes -> {} words".format(
        sum(1 for l in content.strip().split("\n") if not l.startswith("@") and l.strip()),
        n_words))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: {} input.hex output.hex".format(sys.argv[0]))
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
