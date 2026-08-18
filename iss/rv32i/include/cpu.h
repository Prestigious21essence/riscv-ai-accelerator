#pragma once
#include "memory.h"
#include "regfile.h"
#include <cstdint>
#include <iostream>

struct DecodedInstruction {
    uint32_t opcode;
    uint32_t rd;
    uint32_t rs1;
    uint32_t rs2;
    uint32_t funct3;
    uint32_t funct7;
    int32_t  imm;  // sign-extended immediate, meaning depends on instruction type
};

class CPU {
public:
    CPU(Memory& mem) : mem(mem), pc(0), halted(false), cycle_count(0) {}

    uint32_t pc;
    RegFile  regs;
    bool     halted;
    uint32_t cycle_count;

    void step() {
        if (halted) return;
        fetch();
        if (halted) return;  // fetch() can halt on all-zero instruction
        decode();
        execute();
        cycle_count++;
    }

    void run(uint32_t max_steps = 100000) {
        for (uint32_t i = 0; i < max_steps && !halted; i++) step();
    }

private:
    Memory& mem;

    // --- Pipeline-stage-like state, held between fetch/decode/execute ---
    uint32_t instruction;
    uint32_t next_pc;
    DecodedInstruction dec;

    // Control signals -- mirror what a real datapath would compute in decode
    bool mem_read_enable;
    bool mem_write_enable;
    bool reg_write_enable;
    bool is_branch_taken;
    uint32_t branch_target;

    static int32_t sext(uint32_t val, int bits) {
        int32_t shift = 32 - bits;
        return (static_cast<int32_t>(val << shift)) >> shift;
    }

    // ---------------- FETCH ----------------
    void fetch() {
        instruction = mem.read_word(pc);
        if (instruction == 0) { halted = true; return; }
        next_pc = pc + 4;
        mem_read_enable = false;
        mem_write_enable = false;
        reg_write_enable = false;
        is_branch_taken = false;
    }

    // ---------------- DECODE ----------------
    void decode() {
        dec.opcode = instruction & 0x7F;
        dec.rd     = (instruction >> 7) & 0x1F;
        dec.funct3 = (instruction >> 12) & 0x7;
        dec.rs1    = (instruction >> 15) & 0x1F;
        dec.rs2    = (instruction >> 20) & 0x1F;
        dec.funct7 = (instruction >> 25) & 0x7F;

        // Immediate decoding depends on instruction format -- compute the
        // one relevant to this opcode. (Some opcodes ignore dec.imm entirely.)
        switch (dec.opcode) {
            case 0x13: // I-type ALU
            case 0x03: // Loads
            case 0x67: // JALR
                dec.imm = sext(instruction >> 20, 12);
                break;
            case 0x23: { // S-type (stores)
                uint32_t imm_lo = dec.rd;      // reuses rd field bits
                uint32_t imm_hi = dec.funct7;
                dec.imm = sext((imm_hi << 5) | imm_lo, 12);
                break;
            }
            case 0x63: { // B-type (branches)
                uint32_t imm_11  = (instruction >> 7) & 0x1;
                uint32_t imm_4_1 = (instruction >> 8) & 0xF;
                uint32_t imm_10_5= (instruction >> 25) & 0x3F;
                uint32_t imm_12  = (instruction >> 31) & 0x1;
                uint32_t raw = (imm_12 << 12) | (imm_11 << 11) | (imm_10_5 << 5) | (imm_4_1 << 1);
                dec.imm = sext(raw, 13);
                break;
            }
            case 0x37: // LUI
            case 0x17: // AUIPC
                dec.imm = instruction & 0xFFFFF000;
                break;
            case 0x6F: { // JAL
                uint32_t imm_20   = (instruction >> 31) & 0x1;
                uint32_t imm_10_1 = (instruction >> 21) & 0x3FF;
                uint32_t imm_11   = (instruction >> 20) & 0x1;
                uint32_t imm_19_12= (instruction >> 12) & 0xFF;
                uint32_t raw = (imm_20 << 20) | (imm_19_12 << 12) | (imm_11 << 11) | (imm_10_1 << 1);
                dec.imm = sext(raw, 21);
                break;
            }
            default:
                dec.imm = 0; // R-type and unknown -- immediate unused
        }
    }

    // ---------------- EXECUTE ----------------
    void execute() {
        int32_t a = static_cast<int32_t>(regs.read(dec.rs1));
        int32_t b = static_cast<int32_t>(regs.read(dec.rs2));
        uint32_t result = 0;

        switch (dec.opcode) {
            case 0x33: { // R-type
                switch (dec.funct3) {
                    case 0x0: result = (dec.funct7 == 0x20) ? (a - b) : (a + b); break;
                    case 0x1: result = a << (b & 0x1F); break;
                    case 0x2: result = (a < b) ? 1 : 0; break;
                    case 0x3: result = (regs.read(dec.rs1) < regs.read(dec.rs2)) ? 1 : 0; break;
                    case 0x4: result = a ^ b; break;
                    case 0x5: result = (dec.funct7 == 0x20)
                                ? (a >> (b & 0x1F))
                                : (static_cast<uint32_t>(a) >> (b & 0x1F));
                        break;
                    case 0x6: result = a | b; break;
                    case 0x7: result = a & b; break;
                }
                reg_write_enable = true;
                break;
            }
            case 0x13: { // I-type ALU
                switch (dec.funct3) {
                    case 0x0: result = a + dec.imm; break;
                    case 0x1: result = a << (dec.imm & 0x1F); break;
                    case 0x2: result = (a < dec.imm) ? 1 : 0; break;
                    case 0x3: result = (regs.read(dec.rs1) < static_cast<uint32_t>(dec.imm)) ? 1 : 0; break;
                    case 0x4: result = a ^ dec.imm; break;
                    case 0x5: {
                        uint32_t shamt = dec.imm & 0x1F;
                        result = (dec.funct7 == 0x20)
                            ? (a >> shamt)
                            : (static_cast<uint32_t>(a) >> shamt);
                        break;
                    }
                    case 0x6: result = a | dec.imm; break;
                    case 0x7: result = a & dec.imm; break;
                }
                reg_write_enable = true;
                break;
            }
            case 0x03: { // Loads
                mem_read_enable = true;
                uint32_t addr = regs.read(dec.rs1) + dec.imm;
                switch (dec.funct3) {
                    case 0x0: result = sext(mem.read_byte(addr), 8); break;
                    case 0x1: result = sext(mem.read_half(addr), 16); break;
                    case 0x2: result = mem.read_word(addr); break;
                    case 0x4: result = mem.read_byte(addr); break;
                    case 0x5: result = mem.read_half(addr); break;
                }
                reg_write_enable = true;
                break;
            }
            case 0x23: { // Stores
                mem_write_enable = true;
                uint32_t addr = regs.read(dec.rs1) + dec.imm;
                uint32_t val = regs.read(dec.rs2);
                switch (dec.funct3) {
                    case 0x0: mem.write_byte(addr, val & 0xFF); break;
                    case 0x1: mem.write_half(addr, val & 0xFFFF); break;
                    case 0x2: mem.write_word(addr, val); break;
                }
                break;
            }
            case 0x63: { // Branches
                bool taken = false;
                switch (dec.funct3) {
                    case 0x0: taken = (a == b); break;
                    case 0x1: taken = (a != b); break;
                    case 0x4: taken = (a < b); break;
                    case 0x5: taken = (a >= b); break;
                    case 0x6: taken = (regs.read(dec.rs1) < regs.read(dec.rs2)); break;
                    case 0x7: taken = (regs.read(dec.rs1) >= regs.read(dec.rs2)); break;
                }
                if (taken) {
                    is_branch_taken = true;
                    branch_target = pc + dec.imm;
                }
                break;
            }
            case 0x37: // LUI
                result = dec.imm;
                reg_write_enable = true;
                break;
            case 0x17: // AUIPC
                result = pc + dec.imm;
                reg_write_enable = true;
                break;
            case 0x6F: // JAL
                result = pc + 4;
                reg_write_enable = true;
                is_branch_taken = true;
                branch_target = pc + dec.imm;
                break;
            case 0x67: // JALR
                result = pc + 4;
                reg_write_enable = true;
                is_branch_taken = true;
                branch_target = (regs.read(dec.rs1) + dec.imm) & ~1u;
                break;
            default:
                std::cerr << "Unknown opcode 0x" << std::hex << dec.opcode
                          << " at PC=0x" << pc << std::dec << std::endl;
                halted = true;
                return;
        }

        if (reg_write_enable) regs.write(dec.rd, result);
        pc = is_branch_taken ? branch_target : next_pc;
    }
};
