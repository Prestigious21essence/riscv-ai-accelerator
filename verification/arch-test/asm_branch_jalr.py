#!/usr/bin/env python3
"""Hand-assemble a short RV32I program exercising every branch (BEQ/BNE/
BLT/BGE/BLTU/BGEU, both a taken and a not-taken case each) plus JAL and
JALR, and emit instr_mem.hex for tb_branch_jalr.sv.

Layout is address-explicit (not label-based) on purpose: every branch/jump
offset below is hand-verified against the addresses it's written next to,
so the encoding can be sanity-checked by inspection rather than trusting a
linker/assembler we don't have in this sandbox (no riscv32-unknown-elf-as).
"""

def itype(imm, rs1, funct3, rd, opcode):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def btype(imm, rs2, rs1, funct3, opcode):
    imm12   = (imm >> 12) & 1
    imm11   = (imm >> 11) & 1
    imm10_5 = (imm >> 5) & 0x3F
    imm4_1  = (imm >> 1) & 0xF
    return (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_1 << 8) | (imm11 << 7) | opcode

def jtype(imm, rd, opcode):
    imm20    = (imm >> 20) & 1
    imm10_1  = (imm >> 1) & 0x3FF
    imm11    = (imm >> 11) & 1
    imm19_12 = (imm >> 12) & 0xFF
    return (imm20 << 31) | (imm10_1 << 21) | (imm11 << 20) | (imm19_12 << 12) | (rd << 7) | opcode

OPIMM = 0b0010011
BRANCH = 0b1100011
JAL = 0b1101111
JALR = 0b1100111

BEQ, BNE, BLT, BGE, BLTU, BGEU = 0b000, 0b001, 0b100, 0b101, 0b110, 0b111

prog = []
prog.append(("addi x1,x0,5",        itype(5, 0, 0b000, 1, OPIMM)))                 # 0x00
prog.append(("addi x2,x0,5",        itype(5, 0, 0b000, 2, OPIMM)))                 # 0x04
prog.append(("beq  x1,x2,+8",       btype(8, 2, 1, BEQ, BRANCH)))                  # 0x08 taken -> 0x10
prog.append(("addi x3,x0,999 [skip]", itype(999, 0, 0b000, 3, OPIMM)))             # 0x0C
prog.append(("addi x3,x0,111",      itype(111, 0, 0b000, 3, OPIMM)))               # 0x10
prog.append(("bne  x1,x2,+8",       btype(8, 2, 1, BNE, BRANCH)))                  # 0x14 not taken -> falls to 0x18
prog.append(("addi x4,x0,222",      itype(222, 0, 0b000, 4, OPIMM)))               # 0x18
prog.append(("addi x5,x0,-1",       itype(-1 & 0xFFF, 0, 0b000, 5, OPIMM)))        # 0x1C
prog.append(("addi x6,x0,1",        itype(1, 0, 0b000, 6, OPIMM)))                 # 0x20
prog.append(("blt  x5,x6,+8",       btype(8, 6, 5, BLT, BRANCH)))                  # 0x24 taken (-1<1) -> 0x2C
prog.append(("addi x7,x0,999 [skip]", itype(999, 0, 0b000, 7, OPIMM)))             # 0x28
prog.append(("addi x7,x0,333",      itype(333, 0, 0b000, 7, OPIMM)))               # 0x2C
prog.append(("bltu x5,x6,+8",       btype(8, 6, 5, BLTU, BRANCH)))                 # 0x30 not taken (0xFFFFFFFF !<u 1) -> falls to 0x34
prog.append(("addi x8,x0,444",      itype(444, 0, 0b000, 8, OPIMM)))               # 0x34
prog.append(("bge  x6,x5,+8",       btype(8, 5, 6, BGE, BRANCH)))                  # 0x38 taken (1>=-1) -> 0x40
prog.append(("addi x9,x0,999 [skip]", itype(999, 0, 0b000, 9, OPIMM)))             # 0x3C
prog.append(("addi x9,x0,555",      itype(555, 0, 0b000, 9, OPIMM)))               # 0x40
prog.append(("bgeu x6,x5,+8",       btype(8, 5, 6, BGEU, BRANCH)))                 # 0x44 not taken (1 !>=u 0xFFFFFFFF) -> falls to 0x48
prog.append(("addi x10,x0,666",     itype(666, 0, 0b000, 10, OPIMM)))              # 0x48
prog.append(("jal  x11,+8",         jtype(8, 11, JAL)))                            # 0x4C x11=0x50, -> 0x54
prog.append(("addi x12,x0,999 [skip]", itype(999, 0, 0b000, 12, OPIMM)))           # 0x50
prog.append(("addi x13,x0,777",     itype(777, 0, 0b000, 13, OPIMM)))              # 0x54
prog.append(("addi x14,x0,0x64",    itype(0x64, 0, 0b000, 14, OPIMM)))             # 0x58
prog.append(("jalr x15,8(x14)",     itype(8, 14, 0b000, 15, JALR)))                # 0x5C x15=0x60, -> (0x64+8)=0x6C
prog.append(("addi x16,x0,999 [skip]", itype(999, 0, 0b000, 16, OPIMM)))           # 0x60
prog.append(("addi x17,x0,999 [skip]", itype(999, 0, 0b000, 17, OPIMM)))           # 0x64
prog.append(("addi x18,x0,999 [skip]", itype(999, 0, 0b000, 18, OPIMM)))           # 0x68
prog.append(("addi x19,x0,888",     itype(888, 0, 0b000, 19, OPIMM)))              # 0x6C
prog.append(("jal  x0,0  (halt self-loop)", jtype(0, 0, JAL)))                     # 0x70

with open("/tmp/work/riscv-ai-accelerator/tb/rv32i/instr_mem_branch_jalr.hex", "w") as f:
    for i, (name, code) in enumerate(prog):
        f.write(f"{code & 0xFFFFFFFF:08x}\n")
        print(f"{i*4:#04x}: {code & 0xFFFFFFFF:08x}  {name}")
