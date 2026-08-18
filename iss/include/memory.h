#pragma once
#include <cstdint>
#include <vector>
#include <stdexcept>

class Memory {
public:
    explicit Memory(size_t size_bytes) : mem(size_bytes, 0) {}

    uint8_t read_byte(uint32_t addr) const {
        check(addr, 1);
        return mem[addr];
    }

    uint16_t read_half(uint32_t addr) const {
        check(addr, 2);
        return static_cast<uint16_t>(mem[addr]) |
               (static_cast<uint16_t>(mem[addr + 1]) << 8);
    }

    uint32_t read_word(uint32_t addr) const {
        check(addr, 4);
        return static_cast<uint32_t>(mem[addr]) |
               (static_cast<uint32_t>(mem[addr + 1]) << 8) |
               (static_cast<uint32_t>(mem[addr + 2]) << 16) |
               (static_cast<uint32_t>(mem[addr + 3]) << 24);
    }

    void write_byte(uint32_t addr, uint8_t val) {
        check(addr, 1);
        mem[addr] = val;
    }

    void write_half(uint32_t addr, uint16_t val) {
        check(addr, 2);
        mem[addr]     = val & 0xFF;
        mem[addr + 1] = (val >> 8) & 0xFF;
    }

    void write_word(uint32_t addr, uint32_t val) {
        check(addr, 4);
        mem[addr]     = val & 0xFF;
        mem[addr + 1] = (val >> 8) & 0xFF;
        mem[addr + 2] = (val >> 16) & 0xFF;
        mem[addr + 3] = (val >> 24) & 0xFF;
    }

    size_t size() const { return mem.size(); }

private:
    std::vector<uint8_t> mem;

    void check(uint32_t addr, size_t bytes) const {
        if (static_cast<size_t>(addr) + bytes > mem.size())
            throw std::out_of_range("Memory access out of range at addr 0x" +
                                     std::to_string(addr));
    }
};
