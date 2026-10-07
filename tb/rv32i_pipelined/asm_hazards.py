#!/usr/bin/env python3
"""Generate hex for tb_pipeline_hazards.sv to test all forwarding,
load-use stalls, store forwarding, and write-through cases."""
import os

def itype(imm, rs1, funct3, rd, opcode):
    imm &= 0xFFF
    return (imm << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def rtype(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def stype(imm, rs2, rs1, funct3, opcode):
    imm11_5 = (imm >> 5) & 0x7F
    imm4_0 = imm & 0x1F
    return (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (imm4_0 << 7) | opcode

OPIMM  = 0b0010011
OP     = 0b0110011
LOAD   = 0b0000011
STORE  = 0b0100011
JAL    = 0b1101111

prog = [
    # 1. EX-to-EX RAW forwarding on rs1 and rs2
    ("addi x1, x0, 10",         itype(10, 0, 0, 1, OPIMM)),       # x1 = 10
    ("addi x2, x1, 20",         itype(20, 1, 0, 2, OPIMM)),       # x2 = 10 + 20 = 30 (EX hazard rs1)
    ("add  x3, x1, x2",         rtype(0, 2, 1, 0, 3, OP)),        # x3 = 10 + 30 = 40 (MEM hazard rs1, EX hazard rs2)

    # 2. MEM-to-EX RAW forwarding
    ("addi x4, x0, 100",        itype(100, 0, 0, 4, OPIMM)),      # x4 = 100
    ("addi x0, x0, 0",          itype(0, 0, 0, 0, OPIMM)),        # NOP
    ("addi x5, x4, 50",         itype(50, 4, 0, 5, OPIMM)),       # x5 = 100 + 50 = 150 (MEM hazard rs1)

    # 3. Load-use hazard stall
    ("sw   x1, 0(x0)",          stype(0, 1, 0, 2, STORE)),        # mem[0] = 10
    ("lw   x6, 0(x0)",          itype(0, 0, 2, 6, LOAD)),         # x6 = 10
    ("addi x7, x6, 5",          itype(5, 6, 0, 7, OPIMM)),        # x7 = 10 + 5 = 15 (load-use stall on x6)

    # 4. Store data forwarding
    ("addi x8, x0, 77",         itype(77, 0, 0, 8, OPIMM)),       # x8 = 77
    ("sw   x8, 4(x0)",          stype(4, 8, 0, 2, STORE)),        # mem[4] = 77 (forwarded to store data)
    ("lw   x9, 4(x0)",          itype(4, 0, 2, 9, LOAD)),         # x9 = 77

    # 5. Register file write-through (WB-to-ID simultaneous write/read)
    ("addi x10, x0, 99",        itype(99, 0, 0, 10, OPIMM)),      # x10 = 99
    ("addi x0, x0, 0",          itype(0, 0, 0, 0, OPIMM)),        # NOP
    ("addi x0, x0, 0",          itype(0, 0, 0, 0, OPIMM)),        # NOP
    ("addi x11, x10, 1",        itype(1, 10, 0, 11, OPIMM)),      # x11 = 99 + 1 = 100 (WB-to-ID simultaneous)

    # Halt
    ("jal  x0, 0",              0x0000006f)
]

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "instr_mem_hazards.hex")

with open(OUT, "w") as f:
    for name, code in prog:
        f.write(f"{code & 0xFFFFFFFF:08x}\n")

print(f"Wrote {len(prog)} instructions to {OUT}")

