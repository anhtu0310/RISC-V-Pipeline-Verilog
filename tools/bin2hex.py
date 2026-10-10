#!/usr/bin/env python3
"""Convert a flat little-endian binary into a $readmemh file (one 32-bit word per line)."""
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: bin2hex.py <in.bin> <out.hex>")
    data = open(sys.argv[1], "rb").read()
    data += b"\0" * (-len(data) % 4)
    with open(sys.argv[2], "w") as f:
        for i in range(0, len(data), 4):
            f.write("%08x\n" % int.from_bytes(data[i:i + 4], "little"))


if __name__ == "__main__":
    main()
