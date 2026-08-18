#pragma once
#include "memory.h"
#include "regfile.h"
#include <cstdint>
#include <iostream>

class CPU {
public:
    CPU(Memory& mem) : mem(mem), pc(0), halted(false) {}

    uint32_t pc;
    RegFile regs;
    bool halted;

    void step() {
        if (halted) return;
        uint32_t instr = mem.read_word(pc);
        if (instr == 0) { halted = true; return; }  // treat all-zero as end-of-program
        execute(instr);
    }

    void run(uint32_t max_steps = 100000) {
        for (uint32_t i = 0; i < max_steps && !halted; i++) step();
    }

private:
    Memory& mem;

    // Sign-extend a value with 'bits' significant bits
    static int32_t sext(uint32_t val, int bits) {
        int32_t shift = 32 - bits;
        return (static_cast<int32_t>(val << shift)) >> shift;
    }

    void execute(uint32_t instr) {
        uint32_t opcode = instr & 0x7F;
        uint32_t rd     = (instr >> 7) & 0x1F;
        uint32_t funct3 = (instr >> 12) & 0x7;
        uint32_t rs1    = (instr >> 15) & 0x1F;
        uint32_t rs2    = (instr >> 20) & 0x1F;
        uint32_t funct7 = (instr >> 25) & 0x7F;

        uint32_t next_pc = pc + 4;

        switch (opcode) {
            case 0x33: { // R-type: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU
                int32_t a = static_cast<int32_t>(regs.read(rs1));
                int32_t b = static_cast<int32_t>(regs.read(rs2));
                uint32_t result = 0;
                switch (funct3) {
                    case 0x0: result = (funct7 == 0x20) ? (a - b) : (a + b); break; // SUB/ADD
                    case 0x1: result = a << (b & 0x1F); break; // SLL
                    case 0x2: result = (a < b) ? 1 : 0; break; // SLT
                    case 0x3: result = (regs.read(rs1) < regs.read(rs2)) ? 1 : 0; break; // SLTU
                    case 0x4: result = a ^ b; break; // XOR
                    case 0x5: result = (funct7 == 0x20)
                                ? (a >> (b & 0x1F))                          // SRA (arithmetic)
                                : (static_cast<uint32_t>(a) >> (b & 0x1F));  // SRL (logical)
                        break;
                    case 0x6: result = a | b; break; // OR
                    case 0x7: result = a & b; break; // AND
                }
                regs.write(rd, result);
                break;
            }
            case 0x13: { // I-type ALU: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
                int32_t imm = sext(instr >> 20, 12);
                int32_t a = static_cast<int32_t>(regs.read(rs1));
                uint32_t result = 0;
                switch (funct3) {
                    case 0x0: result = a + imm; break; // ADDI
                    case 0x1: result = a << (imm & 0x1F); break; // SLLI
                    case 0x2: result = (a < imm) ? 1 : 0; break; // SLTI
                    case 0x3: result = (regs.read(rs1) < static_cast<uint32_t>(imm)) ? 1 : 0; break; // SLTIU
                    case 0x4: result = a ^ imm; break; // XORI
                    case 0x5: {
                        uint32_t shamt = imm & 0x1F;
                        result = (funct7 == 0x20)
                            ? (a >> shamt)                          // SRAI
                            : (static_cast<uint32_t>(a) >> shamt);  // SRLI
                        break;
                    }
                    case 0x6: result = a | imm; break; // ORI
                    case 0x7: result = a & imm; break; // ANDI
                }
                regs.write(rd, result);
                break;
            }
            case 0x03: { // Loads: LB, LH, LW, LBU, LHU
                int32_t imm = sext(instr >> 20, 12);
                uint32_t addr = regs.read(rs1) + imm;
                uint32_t result = 0;
                switch (funct3) {
                    case 0x0: result = sext(mem.read_byte(addr), 8); break;  // LB
                    case 0x1: result = sext(mem.read_half(addr), 16); break; // LH
                    case 0x2: result = mem.read_word(addr); break;           // LW
                    case 0x4: result = mem.read_byte(addr); break;           // LBU
                    case 0x5: result = mem.read_half(addr); break;           // LHU
                }
                regs.write(rd, result);
                break;
            }
            case 0x23: { // Stores: SB, SH, SW
                uint32_t imm_lo = rd;
                uint32_t imm_hi = funct7;
                int32_t imm = sext((imm_hi << 5) | imm_lo, 12);
                uint32_t addr = regs.read(rs1) + imm;
                uint32_t val = regs.read(rs2);
                switch (funct3) {
                    case 0x0: mem.write_byte(addr, val & 0xFF); break;
                    case 0x1: mem.write_half(addr, val & 0xFFFF); break;
                    case 0x2: mem.write_word(addr, val); break;
                }
                break;
            }
            case 0x63: { // Branches: BEQ, BNE, BLT, BGE, BLTU, BGEU
                uint32_t imm_11 = (instr >> 7) & 0x1;
                uint32_t imm_4_1 = (instr >> 8) & 0xF;
                uint32_t imm_10_5 = (instr >> 25) & 0x3F;
                uint32_t imm_12 = (instr >> 31) & 0x1;
                uint32_t raw = (imm_12 << 12) | (imm_11 << 11) | (imm_10_5 << 5) | (imm_4_1 << 1);
                int32_t imm = sext(raw, 13);

                int32_t a = static_cast<int32_t>(regs.read(rs1));
                int32_t b = static_cast<int32_t>(regs.read(rs2));
                bool taken = false;
                switch (funct3) {
                    case 0x0: taken = (a == b); break; // BEQ
                    case 0x1: taken = (a != b); break; // BNE
                    case 0x4: taken = (a < b); break;  // BLT
                    case 0x5: taken = (a >= b); break; // BGE
                    case 0x6: taken = (regs.read(rs1) < regs.read(rs2)); break;  // BLTU
                    case 0x7: taken = (regs.read(rs1) >= regs.read(rs2)); break; // BGEU
                }
                if (taken) next_pc = pc + imm;
                break;
            }
            case 0x37: { // LUI
                uint32_t imm = instr & 0xFFFFF000;
                regs.write(rd, imm);
                break;
            }
            case 0x17: { // AUIPC
                uint32_t imm = instr & 0xFFFFF000;
                regs.write(rd, pc + imm);
                break;
            }
            case 0x6F: { // JAL
                uint32_t imm_20 = (instr >> 31) & 0x1;
                uint32_t imm_10_1 = (instr >> 21) & 0x3FF;
                uint32_t imm_11 = (instr >> 20) & 0x1;
                uint32_t imm_19_12 = (instr >> 12) & 0xFF;
                uint32_t raw = (imm_20 << 20) | (imm_19_12 << 12) | (imm_11 << 11) | (imm_10_1 << 1);
                int32_t imm = sext(raw, 21);
                regs.write(rd, pc + 4);
                next_pc = pc + imm;
                break;
            }
            case 0x67: { // JALR
                int32_t imm = sext(instr >> 20, 12);
                uint32_t target = (regs.read(rs1) + imm) & ~1u;
                regs.write(rd, pc + 4);
                next_pc = target;
                break;
            }
            default:
                std::cerr << "Unknown opcode 0x" << std::hex << opcode
                          << " at PC=0x" << pc << std::dec << std::endl;
                halted = true;
                return;
        }
        pc = next_pc;
    }
};
