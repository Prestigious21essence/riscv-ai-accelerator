#include "../include/memory.h"
#include "../include/regfile.h"
#include "../include/cpu.h"

#include "../include/elf_loader.h"
#include <iostream>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <elf_binary>\n";
        return 1;
    }

    Memory mem(1 << 20); // 1 MB of simulated memory
    uint32_t entry = ElfLoader::load(argv[1], mem);

    CPU cpu(mem);
    cpu.pc = entry;
    cpu.regs.write(2, mem.size() - 64); // x2 = sp, point near top of memory


    std::cout << "Loaded " << argv[1] << ", entry point = 0x"
               << std::hex << entry << std::dec << "\n";

    cpu.run(10000); // step limit to avoid infinite loop hangs

    std::cout << "\nFinal register state:\n";
    for (int i = 0; i < 32; i++) {
        std::cout << "x" << i << " = " << cpu.regs.read(i) << "\n";
    }

    std::cout << "\nMemory at 0x1000 (result location) = "
               << mem.read_word(0x1000) << "\n";

    return 0;
}


