#include "../include/memory.h"
#include "../include/regfile.h"
#include "../include/cpu.h"
#include <iostream>

uint32_t encode_r(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode) {
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}
uint32_t encode_i(int32_t imm, uint32_t rs1, uint32_t funct3, uint32_t rd, uint32_t opcode) {
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode;
}
uint32_t encode_b(int32_t imm, uint32_t rs2, uint32_t rs1, uint32_t funct3, uint32_t opcode) {
    uint32_t imm_12 = (imm >> 12) & 0x1;
    uint32_t imm_10_5 = (imm >> 5) & 0x3F;
    uint32_t imm_4_1 = (imm >> 1) & 0xF;
    uint32_t imm_11 = (imm >> 11) & 0x1;
    return (imm_12 << 31) | (imm_10_5 << 25) | (rs2 << 20) | (rs1 << 15) |
           (funct3 << 12) | (imm_4_1 << 8) | (imm_11 << 7) | opcode;
}

int main() {
    Memory mem(4096);
    CPU cpu(mem);

    mem.write_word(0,  encode_i(0, 0, 0x0, 1, 0x13));
    mem.write_word(4,  encode_i(1, 0, 0x0, 2, 0x13));
    mem.write_word(8,  encode_i(6, 0, 0x0, 3, 0x13));
    mem.write_word(12, encode_r(0x00, 2, 1, 0x0, 1, 0x33));
    mem.write_word(16, encode_i(1, 2, 0x0, 2, 0x13));
    mem.write_word(20, encode_b(-8, 3, 2, 0x1, 0x63));
    mem.write_word(24, 0);

    cpu.run();

    int errors = 0;
    if (cpu.regs.read(1) != 15) {
        std::cout << "FAIL: expected sum=15, got " << cpu.regs.read(1) << "\n";
        errors++;
    } else {
        std::cout << "PASS: sum of 1..5 = " << cpu.regs.read(1) << "\n";
    }

    if (cpu.regs.read(2) != 6) {
        std::cout << "FAIL: expected i=6, got " << cpu.regs.read(2) << "\n";
        errors++;
    } else {
        std::cout << "PASS: final i = " << cpu.regs.read(2) << "\n";
    }

    std::cout << (errors == 0 ? "\nALL TESTS PASSED\n" : "\nTEST(S) FAILED\n");
    return errors;
}
