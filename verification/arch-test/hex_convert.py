#!/usr/bin/env python3
import struct
import sys

def to_hex(in_path, out_path):
    with open(in_path, "rb") as f:
        data = f.read()
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)
    n = len(data) // 4
    words = struct.unpack("<%dI" % n, data)
    with open(out_path, "w") as f:
        for w in words:
            f.write("%08x\n" % w)
    return n

if __name__ == "__main__":
    n = to_hex(sys.argv[1], sys.argv[2])
    print(f"{sys.argv[2]}: {n} words ({n*4} bytes)")
