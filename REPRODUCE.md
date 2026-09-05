# Reproducing the verification results

This document lets anyone with no prior context on this project — a
professor, a grader, a collaborator — independently rebuild the core and
re-run every check that was used to claim it is correct, and get the same
pass/fail results.

There are two tiers of check, with different setup costs:

1. **Self-contained regressions** — no dependency beyond Verilator.
   `tb_rv32i_core.sv`, `tb_sltu_bytemem.sv`, `tb_branch_jalr.sv`. Clone the
   repo, install Verilator, run three commands.
2. **Full ISA compliance sweep** — every instruction in RV32I checked
   bit-exact against `spike` (the reference RISC-V ISA simulator) using the
   official `riscv-arch-test` suite. This needs three external pieces of
   software that are not vendored into this repo (see "One-time
   environment setup" below), because they are large, third-party projects
   with their own licenses and build systems. Once set up, this check is
   fully automated by one script and gives a deterministic pass count.

## 1. Self-contained regressions (no external setup)

Requires only [Verilator](https://verilator.org/) (`sudo apt install
verilator` on Debian/Ubuntu, or build from source — any reasonably recent
version works, this was developed against 5.020).

```bash
git clone <repo-url> && cd riscv-ai-accelerator

verilator --binary --timing tb/rv32i/tb_rv32i_core.sv rtl/rv32i/*.sv \
  --top-module tb_rv32i_core -Mdir /tmp/obj_core
/tmp/obj_core/Vtb_rv32i_core
# Expect: ALL TESTS PASSED (7/7)

verilator --binary --timing tb/rv32i/tb_sltu_bytemem.sv rtl/rv32i/*.sv \
  --top-module tb_sltu_bytemem -Mdir /tmp/obj_sltu
/tmp/obj_sltu/Vtb_sltu_bytemem
# Expect: ALL SLTU/BYTEMEM TESTS PASSED (9/9)

python3 verification/arch-test/asm_branch_jalr.py   # (re)generates tb/rv32i/instr_mem_branch_jalr.hex
cd /tmp && mkdir -p bj_check && cd bj_check
cp <repo>/tb/rv32i/instr_mem_branch_jalr.hex instr_mem.hex
verilator --binary --timing <repo>/tb/rv32i/tb_branch_jalr.sv <repo>/rtl/rv32i/*.sv \
  --top-module tb_branch_jalr -Mdir obj_dir
./obj_dir/Vtb_branch_jalr
# Expect: ALL BRANCH/JALR TESTS PASSED (19/19)
```

(`tb_branch_jalr` and `tb_sltu_bytemem` must be run from a directory
containing their own `instr_mem.hex`, because `instruction_memory.sv`
reads that literal filename relative to the current directory, not a
path baked into the testbench. Regenerate the right hex file for whichever
testbench you're about to run — a stale `instr_mem.hex` left over from a
different test will silently produce garbage results that look like a
real failure.)

`tb_pc_instr_mem.sv` also exists but has one known, pre-existing,
unrelated failing check (3/4 pass) — a stale expected-value in the
testbench itself, not an RTL bug. Documented so it isn't mistaken for a
new regression.

## 2. Full ISA compliance sweep (needs one-time setup)

### What you need and why

| Tool | Why | How to get it |
|---|---|---|
| `riscv32-unknown-elf-gcc` (+ `objcopy`, `nm`) | Compiles the official arch-test `.S` sources into ELF binaries for both the DUT and spike | `sudo apt install gcc-riscv64-unknown-elf` provides a multilib toolchain that covers rv32 (Ubuntu/Debian), or build the SiFive/`riscv-gnu-toolchain` bare-metal toolchain from source |
| `spike` | The golden-reference RV32I simulator every result is diffed against | Build from source: `git clone https://github.com/riscv-software-src/riscv-isa-sim && cd riscv-isa-sim && mkdir build && cd build && ../configure --prefix=$HOME/.local && make -j$(nproc)` |
| `riscv-arch-test` | The actual test sources (`rv32i_m/I/src/*.S`) and the environment headers both the DUT and spike builds need | `git clone https://github.com/riscv-non-isa/riscv-arch-test && cd riscv-arch-test && git checkout old-framework-3.x` (the `old-framework-3.x` branch — not `main`/`act4`, which is a different, heavier RISCOF/Sail-based framework this project doesn't use) |
| Verilator | Simulates the DUT | as above |

Record the exact versions you used (`riscv32-unknown-elf-gcc --version`,
`spike --help` first line or `git -C riscv-isa-sim rev-parse HEAD`,
`git -C riscv-arch-test rev-parse HEAD`, `verilator --version`) alongside
your results — that's what makes a re-run by someone else, or by you on a
different machine, a real apples-to-apples comparison rather than a
coincidence.

### Running it

```bash
cd riscv-ai-accelerator
export ARCH_TEST_ROOT=~/riscv-arch-test        # your clone, old-framework-3.x branch
export SPIKE_BIN=~/riscv-isa-sim/build/spike   # your built spike binary
./verification/arch-test/run_full_suite.sh
```

This builds and diffs all 38 `rv32i_m/I/src/*.S` files (every instruction
this core implements: `add addi and andi auipc beq bge bgeu blt bltu bne
fence jal jalr lb lbu lh lhu lui lw or ori sb sh sll slli slt slti sltiu
sltu sra srai srl srli sub sw xor xori`) against both the DUT (via
Verilator) and spike, and prints one `PASS`/`FAIL` line per file plus a
final `N passed, M failed` summary. Exit code is 0 iff every file passed.
Each file takes anywhere from under a second to ~10-20 seconds
(the seven size-outlier branch/JAL files, which the script automatically
builds against a larger 2MB memory image — see comments in the script).

If a file fails, the script tells you which log/signature files under its
temp build directory to look at (compile log, Verilator log, or the two
signature files being diffed) — that's enough to tell whether it's a
build-environment problem (wrong toolchain flags, missing include) or an
actual RTL mismatch.

### Known caveat

The DUT is a Harvard-architecture single-cycle core with a fixed-size
instruction memory. The official arch-test generators pad seven files
(`jal-01` and the six branch files) out to hundreds of KB to exercise the
far end of their immediate encoding's range. `run_full_suite.sh` already
handles this (bigger link script + bigger Verilator memory/cycle
parameters for exactly those seven files) — this is a test-infrastructure
accommodation, not something you need to configure.

## What "passing" means here

A `PASS` line means: the DUT and spike, given the identical compiled
binary, wrote byte-identical signature words to the memory region the
official test itself designates for checking correctness (the same
mechanism the official RISC-V compliance flow uses) — i.e., the DUT
computed exactly what the golden reference model computed, for every
value that test is designed to probe. This is instruction-level ISA
compliance, not a claim about performance, timing, or anything outside
RV32I (this core implements no M/F/D/C extensions, no CSRs/privileged
mode — so there is nothing else in `riscv-arch-test` applicable to it).
