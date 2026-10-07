#!/usr/bin/env python3
"""
gen_npu_benchmark32.py

Generates:
1. instr_mem_benchmark32.hex: RISC-V assembly executing 32x32 tiled GEMM using NPU MMIO
2. golden_c.hex: Golden 1024-word result matrix C from matmul_32_t2_s32_O2.c
3. data_a_b.hex: Input matrices A and B for testbench preload
"""

import re
import os

# RISC-V RV32I Instruction Encoders
def lui(rd, imm20):
    return (imm20 << 12) | (rd << 7) | 0x37

def addi(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13

def add(rd, rs1, rs2):
    return (0 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x33

def sub(rd, rs1, rs2):
    return (0x20 << 25) | (rs2 << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x33

def slli(rd, rs1, shamt):
    return (shamt << 20) | (rs1 << 15) | (1 << 12) | (rd << 7) | 0x13

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

def bne(rs1, rs2, offset):
    imm = offset & 0x1FFF
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (1 << 12) | (b4_1 << 8) | (b11 << 7) | 0x63

def blt(rs1, rs2, offset):
    imm = offset & 0x1FFF
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (4 << 12) | (b4_1 << 8) | (b11 << 7) | 0x63

def jal(rd, offset):
    imm = offset & 0x1FFFFF
    j20 = (imm >> 20) & 1
    j10_1 = (imm >> 1) & 0x3FF
    j11 = (imm >> 11) & 1
    j19_12 = (imm >> 12) & 0xFF
    return (j20 << 31) | (j10_1 << 21) | (j11 << 20) | (j19_12 << 12) | (rd << 7) | 0x6F

# 1. Parse A and B from matmul_32_t2_s32_O2.c
root_dir = "/home/enovo/riscv-ai-accelerator"
c_file = os.path.join(root_dir, "matmul_32_t2_s32_O2.c")
tb_dir = os.path.join(root_dir, "converting_into_NPU/tb")
os.makedirs(tb_dir, exist_ok=True)

with open(c_file, "r") as f:
    content = f.read()

a_match = re.search(r"static const int32_t A\[BIG_DIM \* BIG_DIM\] = \{(.*?)\};", content, re.DOTALL)
b_match = re.search(r"static const int32_t B\[BIG_DIM \* BIG_DIM\] = \{(.*?)\};", content, re.DOTALL)

a_vals = [int(x.strip()) for x in a_match.group(1).replace("\n", "").split(",") if x.strip()]
b_vals = [int(x.strip()) for x in b_match.group(1).replace("\n", "").split(",") if x.strip()]

assert len(a_vals) == 1024
assert len(b_vals) == 1024

# Calculate Golden C
golden_c = [0] * (32 * 32)
for i in range(32):
    for j in range(32):
        s = 0
        for k in range(32):
            s += a_vals[i * 32 + k] * b_vals[k * 32 + j]
        golden_c[i * 32 + j] = s

# Write golden_c.hex

with open(os.path.join(tb_dir, "golden_c.hex"), "w") as f:
    for val in golden_c:
        f.write(f"{(val & 0xFFFFFFFF):08x}\n")

with open(os.path.join(tb_dir, "data_a.hex"), "w") as f:
    for val in a_vals:
        f.write(f"{(val & 0xFFFFFFFF):08x}\n")

with open(os.path.join(tb_dir, "data_b.hex"), "w") as f:
    for val in b_vals:
        f.write(f"{(val & 0xFFFFFFFF):08x}\n")

print("Generated golden_c.hex, data_a.hex, data_b.hex successfully.")

# 2. Build RISC-V Machine Code to run Tiled 32x32 GEMM
# Memory Layout:
#   Matrix A: byte 0x0000_0000 (1024 words = 4096 bytes)
#   Matrix B: byte 0x0000_1000 (1024 words = 4096 bytes)
#   Matrix C: byte 0x000C_8000 (1024 words = 4096 bytes)
#
# Register Map:
#   x1  = NPU Base (0x8000_0000)
#   x2  = Base A   (0x0000_0000)
#   x3  = Base B   (0x0000_1000)
#   x4  = Base C   (0x000C_8000)
#   x5  = ti (0..1)
#   x6  = tj (0..1)
#   x7  = tk (0..1)
#   x8  = i  (0..15)
#   x9  = j/k (0..15)
#   ... temp registers

code = []

# Label helper
def emit(instr):
    code.append(instr)

# Entry: PC = 0x00000000
# Jump over the finish vector 0x0000000C
emit(jal(0, 16)) # Jump to 0x10

# 0x04: NOP
emit(addi(0, 0, 0))

# 0x08: NOP
emit(addi(0, 0, 0))

# 0x0C: Completion Vector (Infinite loop)
emit(jal(0, 0)) # j 0x0C

# 0x10: Program Start
# Setup Pointers:
emit(lui(1, 0x80000))  # x1 = 0x8000_0000 (NPU Base)
emit(addi(2, 0, 0))    # x2 = 0 (Base A)
emit(lui(3, 1))        # x3 = 0x1000 (Base B = 4096 bytes)
emit(lui(4, 0xC8))     # x4 = 0x000C_8000 (Base C)

# Set NPU Dimensions M=16, K=16, N=16
emit(addi(10, 0, 16))
emit(sw(10, 1, 0x00))  # DIM_M = 16
emit(sw(10, 1, 0x04))  # DIM_K = 16
emit(sw(10, 1, 0x08))  # DIM_N = 16

# Clear Matrix C in memory (1024 words)
# x11 = ptr C, x12 = count (1024)
emit(addi(11, 4, 0))
emit(addi(12, 0, 0))
emit(lui(13, 1))       # 1024 words: 0x400
# Loop zero C:
# L_ZERO_C:
zero_c_pc = len(code)
emit(sw(0, 11, 0))
emit(addi(11, 11, 4))
emit(addi(12, 12, 1))
emit(blt(12, 13, (zero_c_pc - len(code)) * 4))

# Nested Tiling Loops:
# ti: x5 in {0, 1}
# tj: x6 in {0, 1}
# tk: x7 in {0, 1}

emit(addi(5, 0, 0)) # ti = 0

L_TI = len(code)
emit(addi(6, 0, 0)) # tj = 0

L_TJ = len(code)
emit(addi(7, 0, 0)) # tk = 0

L_TK = len(code)

# -----------------------------------------------------------------------------
# Stream Tile A[ti, tk] into NPU SRAM A (0x8000_0100)
# A tile has 16 rows, 16 cols.
# Global row = ti * 16 + i, global col = tk * 16 + k
# Address in A = (global row * 32 + global col) * 4
# NPU SRAM A address = 0x8000_0100 + (i * 16 + k) * 4
# -----------------------------------------------------------------------------
# x8 = i (0..15)
emit(addi(8, 0, 0))
L_STREAM_A_I = len(code)
emit(addi(9, 0, 0)) # k = 0
L_STREAM_A_K = len(code)

# calc src_addr = ((ti*16 + i)*32 + (tk*16 + k)) * 4
# ti*16 + i -> slli x14, x5, 4; add x14, x14, x8
emit(slli(14, 5, 4))
emit(add(14, 14, 8))
# * 32 -> slli x14, x14, 5
emit(slli(14, 14, 5))
# + (tk*16 + k)
emit(slli(15, 7, 4))
emit(add(15, 15, 9))
emit(add(14, 14, 15))
# * 4
emit(slli(14, 14, 2))
# + Base A (x2)
emit(add(14, 14, 2))
emit(lw(16, 14, 0)) # x16 = word from Matrix A

# calc dst_addr in NPU SRAM A: 0x8000_0100 + (i*16 + k)*4
emit(slli(17, 8, 4))
emit(add(17, 17, 9))
emit(slli(17, 17, 2))
emit(addi(17, 17, 0x100))
emit(add(17, 17, 1))
emit(sw(16, 17, 0))

# k loop
emit(addi(9, 9, 1))
emit(blt(9, 10, (L_STREAM_A_K - len(code)) * 4)) # x10 is 16
# i loop
emit(addi(8, 8, 1))
emit(blt(8, 10, (L_STREAM_A_I - len(code)) * 4))

# -----------------------------------------------------------------------------
# Stream Tile B[tk, tj] into NPU SRAM B (0x8000_0500)
# Global row = tk * 16 + k, global col = tj * 16 + j
# -----------------------------------------------------------------------------
emit(addi(8, 0, 0)) # k = 0
L_STREAM_B_K = len(code)
emit(addi(9, 0, 0)) # j = 0
L_STREAM_B_J = len(code)

# calc src_addr in B: ((tk*16 + k)*32 + (tj*16 + j))*4 + Base B (x3)
emit(slli(14, 7, 4))
emit(add(14, 14, 8))
emit(slli(14, 14, 5))
emit(slli(15, 6, 4))
emit(add(15, 15, 9))
emit(add(14, 14, 15))
emit(slli(14, 14, 2))
emit(add(14, 14, 3)) # + Base B
emit(lw(16, 14, 0))

# calc dst_addr in NPU SRAM B: 0x8000_0500 + (k*16 + j)*4
emit(slli(17, 8, 4))
emit(add(17, 17, 9))
emit(slli(17, 17, 2))
# 0x500 = 0x280 + 0x280
emit(addi(17, 17, 0x280))
emit(addi(17, 17, 0x280))
emit(add(17, 17, 1))
emit(sw(16, 17, 0))

emit(addi(9, 9, 1))
emit(blt(9, 10, (L_STREAM_B_J - len(code)) * 4))
emit(addi(8, 8, 1))
emit(blt(8, 10, (L_STREAM_B_K - len(code)) * 4))

# -----------------------------------------------------------------------------
# Trigger NPU Compute (0x8000_000C = 1)
# -----------------------------------------------------------------------------
emit(addi(18, 0, 1))
emit(sw(18, 1, 0x0C))

# Polling loop: while(!(*NPU_STATUS & 1))
L_POLL = len(code)
emit(lw(19, 1, 0x18))
emit(addi(20, 0, 1))
# and x19, x19, x20
emit((0 << 25) | (20 << 20) | (19 << 15) | (7 << 12) | (19 << 7) | 0x33)
emit(beq(19, 0, (L_POLL - len(code)) * 4))

# -----------------------------------------------------------------------------
# Read back NPU SRAM C (0x8000_0900) and accumulate into Matrix C in memory
# -----------------------------------------------------------------------------
emit(addi(8, 0, 0)) # i = 0
L_READ_C_I = len(code)
emit(addi(9, 0, 0)) # j = 0
L_READ_C_J = len(code)

# NPU SRAM C addr: 0x8000_0900 + (i*16 + j)*4
# 0x900 = 0x480 + 0x480
emit(slli(17, 8, 4))
emit(add(17, 17, 9))
emit(slli(17, 17, 2))
emit(addi(17, 17, 0x480))
emit(addi(17, 17, 0x480))
emit(add(17, 17, 1))
emit(lw(16, 17, 0)) # x16 = computed partial C[i, j] from NPU

# Destination addr in RAM C: ((ti*16 + i)*32 + (tj*16 + j))*4 + Base C (x4)
emit(slli(14, 5, 4))
emit(add(14, 14, 8))
emit(slli(14, 14, 5))
emit(slli(15, 6, 4))
emit(add(15, 15, 9))
emit(add(14, 14, 15))
emit(slli(14, 14, 2))
emit(add(14, 14, 4)) # + Base C

# Accumulate: C_mem[addr] = C_mem[addr] + x16
emit(lw(21, 14, 0))
emit(add(21, 21, 16))
emit(sw(21, 14, 0))

emit(addi(9, 9, 1))
emit(blt(9, 10, (L_READ_C_J - len(code)) * 4))
emit(addi(8, 8, 1))
emit(blt(8, 10, (L_READ_C_I - len(code)) * 4))

# tk loop: tk in 0..1
emit(addi(7, 7, 1))
emit(addi(22, 0, 2))
emit(blt(7, 22, (L_TK - len(code)) * 4))

# tj loop: tj in 0..1
emit(addi(6, 6, 1))
emit(blt(6, 22, (L_TJ - len(code)) * 4))

# ti loop: ti in 0..1
emit(addi(5, 5, 1))
emit(blt(5, 22, (L_TI - len(code)) * 4))

# Finished! Jump to completion vector at 0x0000000C
# Offset from current PC to 0x0000000C:
current_pc = len(code) * 4
target_pc = 0x0000000C
offset = target_pc - current_pc
emit(jal(0, offset))

# Write instr_mem_benchmark32.hex
with open(os.path.join(tb_dir, "instr_mem_benchmark32.hex"), "w") as f:
    for instr in code:
        f.write(f"{instr:08x}\n")

print(f"Generated instr_mem_benchmark32.hex ({len(code)} instructions, {len(code)*4} bytes).")
