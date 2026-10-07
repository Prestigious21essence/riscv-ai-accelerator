#!/usr/bin/env python3
"""
Generates instr_mem_npu.hex:
RISC-V assembly program that programs NPU registers, loads matrices A & B,
triggers computation, polls NPU_STATUS until done, and reads back matrix C.
"""

def lui(rd, imm20):
    return (imm20 << 12) | (rd << 7) | 0x37

def addi(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13

def andi(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (7 << 12) | (rd << 7) | 0x13

def lw(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (2 << 12) | (rd << 7) | 0x03

def sw(rs2, rs1, imm12):
    imm = imm12 & 0xFFF
    imm_11_5 = (imm >> 5) & 0x7F
    imm_4_0 = imm & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (2 << 12) | (imm_4_0 << 7) | 0x23

def beq(rs1, rs2, offset):
    imm = offset & 0x1FFF
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (b4_1 << 8) | (b11 << 7) | 0x63

def add(rd, rs1, rs2):
    return (0 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x33

instructions = [
    # 0x00: Set x1 = 0x80000000 (NPU Base Address)
    lui(1, 0x80000),

    # 0x04: Write NPU_DIM_M = 2, K = 2, N = 2
    addi(2, 0, 2),
    sw(2, 1, 0x00), # NPU_DIM_M = 2
    sw(2, 1, 0x04), # NPU_DIM_K = 2
    sw(2, 1, 0x08), # NPU_DIM_N = 2

    # 0x14: Load Matrix A (2x2): A[0,0]=3, A[0,1]=4, A[1,0]=5, A[1,1]=6
    # Base A = 0x80000100
    addi(3, 0, 3),
    sw(3, 1, 0x100), # A[0,0] = 3
    addi(3, 0, 4),
    sw(3, 1, 0x104), # A[0,1] = 4

    addi(4, 1, 0x140), # Row 1 offset = 16 words = 64 bytes = 0x40 -> 0x140
    addi(3, 0, 5),
    sw(3, 4, 0x00),  # A[1,0] = 5
    addi(3, 0, 6),
    sw(3, 4, 0x04),  # A[1,1] = 6

    # 0x34: Load Matrix B (2x2): B[0,0]=1, B[0,1]=2, B[1,0]=3, B[1,1]=4
    # Base B = 0x80000500
    addi(5, 1, 0x500),
    addi(3, 0, 1),
    sw(3, 5, 0x00),  # B[0,0] = 1
    addi(3, 0, 2),
    sw(3, 5, 0x04),  # B[0,1] = 2

    addi(6, 5, 0x40), # Row 1 of B = 0x540
    addi(3, 0, 3),
    sw(3, 6, 0x00),  # B[1,0] = 3
    addi(3, 0, 4),
    sw(3, 6, 0x04),  # B[1,1] = 4

    # 0x54: Trigger computation: NPU_TRIGGER = 1 (offset 0x0C)
    addi(7, 0, 1),
    sw(7, 1, 0x0C),

    # Concurrent CPU execution while NPU computes in background:
    # 1. CPU arithmetic operations
    addi(20, 0, 100),  # x20 = 100
    addi(21, 0, 200),  # x21 = 200
    add(22, 20, 21),   # x22 = 300

    # 2. Main RAM write/read (address 0x50) to verify memory isolation from MMIO
    addi(24, 0, 42),   # x24 = 42
    sw(24, 0, 0x50),   # store 42 to RAM[0x50] (rs1=x0)
    lw(23, 0, 0x50),   # load back into x23 (expected 42)

    # Polling loop:
    # lw x8, 24(x1)      (NPU_STATUS at 0x18)
    # andi x9, x8, 1
    # beq x9, x0, -8     (jump back to lw)
    lw(8, 1, 0x18),
    andi(9, 8, 1),
    beq(9, 0, -8),

    # 0x68: Computation finished! Read back Matrix C:
    # 0x900 = 0x480 + 0x480 (both positive 12-bit signed immediates)
    addi(10, 1, 0x480),
    addi(10, 10, 0x480), # x10 = 0x80000900 (Base C)
    lw(11, 10, 0x00),   # x11 = C[0,0] (15)
    lw(12, 10, 0x04),   # x12 = C[0,1] (22)

    addi(13, 10, 0x40), # Row 1 of C = 0x940
    lw(14, 13, 0x00),   # x14 = C[1,0] (23)
    lw(15, 13, 0x04),   # x15 = C[1,1] (34)

    # Read cycle counter at offset 0x20
    lw(16, 1, 0x20),    # x16 = cycle count (8)

    # 0x88: Program termination loop: jal x0, 0
    0x0000006F
]

import os
script_dir = os.path.dirname(os.path.abspath(__file__))
tb_dir = os.path.join(os.path.dirname(script_dir), "tb")
os.makedirs(tb_dir, exist_ok=True)
out_file = os.path.join(tb_dir, "instr_mem_npu.hex")

with open(out_file, "w") as f:
    for instr in instructions:
        f.write(f"{instr:08x}\n")

print(f"Generated {out_file} ({len(instructions)} instructions)")
