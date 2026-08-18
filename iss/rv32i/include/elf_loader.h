#pragma once
#include "memory.h"
#include <cstdint>
#include <fstream>
#include <vector>
#include <stdexcept>
#include <cstring>

#pragma pack(push, 1)
struct Elf32_Ehdr {
    uint8_t  e_ident[16];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint32_t e_entry;
    uint32_t e_phoff;
    uint32_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
};

struct Elf32_Phdr {
    uint32_t p_type;
    uint32_t p_offset;
    uint32_t p_vaddr;
    uint32_t p_paddr;
    uint32_t p_filesz;
    uint32_t p_memsz;
    uint32_t p_flags;
    uint32_t p_align;
};
#pragma pack(pop)

class ElfLoader {
public:
    // Loads the ELF file into mem, returns the entry point address
    static uint32_t load(const std::string& path, Memory& mem) {
        std::ifstream file(path, std::ios::binary);
        if (!file) throw std::runtime_error("Cannot open ELF file: " + path);

        std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)),
                                    std::istreambuf_iterator<char>());

        if (data.size() < sizeof(Elf32_Ehdr))
            throw std::runtime_error("File too small to be a valid ELF");

        Elf32_Ehdr ehdr;
        std::memcpy(&ehdr, data.data(), sizeof(Elf32_Ehdr));

        // Verify ELF magic number: 0x7F 'E' 'L' 'F'
        if (ehdr.e_ident[0] != 0x7F || ehdr.e_ident[1] != 'E' ||
            ehdr.e_ident[2] != 'L' || ehdr.e_ident[3] != 'F')
            throw std::runtime_error("Not a valid ELF file (bad magic)");

        if (ehdr.e_ident[4] != 1) // EI_CLASS: 1 = ELFCLASS32
            throw std::runtime_error("Only 32-bit ELF files are supported");

        // Walk program headers, load each PT_LOAD segment into memory
        for (int i = 0; i < ehdr.e_phnum; i++) {
            uint32_t offset = ehdr.e_phoff + i * ehdr.e_phentsize;
            if (offset + sizeof(Elf32_Phdr) > data.size())
                throw std::runtime_error("Program header out of file bounds");

            Elf32_Phdr phdr;
            std::memcpy(&phdr, data.data() + offset, sizeof(Elf32_Phdr));

            const uint32_t PT_LOAD = 1;
            if (phdr.p_type != PT_LOAD) continue;

            // Copy file bytes into memory at p_vaddr
            for (uint32_t b = 0; b < phdr.p_filesz; b++) {
                mem.write_byte(phdr.p_vaddr + b, data[phdr.p_offset + b]);
            }
            // Zero-fill the rest (p_memsz can be larger than p_filesz, e.g. .bss)
            for (uint32_t b = phdr.p_filesz; b < phdr.p_memsz; b++) {
                mem.write_byte(phdr.p_vaddr + b, 0);
            }
        }

        return ehdr.e_entry;
    }
};
