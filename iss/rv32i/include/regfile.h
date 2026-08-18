#pragma once
#include <cstdint>
#include <array>

class RegFile {
public:
    RegFile() { regs.fill(0); }

    uint32_t read(uint32_t idx) const {
        return (idx == 0) ? 0 : regs[idx];
    }

    void write(uint32_t idx, uint32_t val) {
        if (idx != 0) regs[idx] = val;
    }

private:
    std::array<uint32_t, 32> regs;
};
