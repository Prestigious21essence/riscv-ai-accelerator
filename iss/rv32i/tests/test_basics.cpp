#include "../include/memory.h"
#include "../include/regfile.h"
#include <iostream>
#include <cassert>

int main() {
    int errors = 0;

    // --- RegFile tests ---
    RegFile rf;
    rf.write(5, 0x12345678);
    if (rf.read(5) != 0x12345678) { std::cout << "FAIL: regfile write/read x5\n"; errors++; }
    else std::cout << "PASS: regfile write/read x5\n";

    rf.write(0, 0xDEADBEEF);
    if (rf.read(0) != 0) { std::cout << "FAIL: x0 stays zero\n"; errors++; }
    else std::cout << "PASS: x0 stays zero\n";

    // --- Memory tests ---
    Memory mem(1024);
    mem.write_word(0x100, 0xAABBCCDD);
    if (mem.read_word(0x100) != 0xAABBCCDD) { std::cout << "FAIL: word write/read\n"; errors++; }
    else std::cout << "PASS: word write/read\n";

    if (mem.read_byte(0x100) != 0xDD) { std::cout << "FAIL: byte 0 of word (little-endian)\n"; errors++; }
    else std::cout << "PASS: byte 0 of word (little-endian)\n";

    if (mem.read_byte(0x103) != 0xAA) { std::cout << "FAIL: byte 3 of word (little-endian)\n"; errors++; }
    else std::cout << "PASS: byte 3 of word (little-endian)\n";

    mem.write_half(0x200, 0x1234);
    if (mem.read_half(0x200) != 0x1234) { std::cout << "FAIL: halfword write/read\n"; errors++; }
    else std::cout << "PASS: halfword write/read\n";

    if (errors == 0) std::cout << "\nALL TESTS PASSED\n";
    else std::cout << "\n" << errors << " TEST(S) FAILED\n";

    return errors;
}
