# riscv-arch-test integration

Runs official [riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test)
(`old-framework-3.x` branch) test sources against this core and verifies
the resulting signature against a real golden reference (`spike`).

## Status

`add-01.S` and `addi-01.S` both produce signatures that are **bit-for-bit
identical** to spike's golden-reference signature — 0 differences,
verified on real hardware (not just simulation-of-a-simulation). The
riscv-arch-test integration pipeline (build, link, run, dump, compare)
is confirmed working end to end.

Not yet run: the rest of the `rv32i_m/I` suite (mechanical repetition of
the same now-working pipeline). Not yet implemented in the core:
conditional branches and `jalr` — real design work, tracked separately.

## Files

- `model_test.h` — target header for this core. Deliberately minimal (no
  trap/CSR support). `RVMODEL_HALT` ends in a `jal x0, halt_loop`
  self-loop — see "Gotchas" below for why that matters.
- `link.ld` — Harvard-aware linker script: separate 4096-word IMEM/DMEM
  regions, both based at address 0 to match this core's memories.
  Requires `--no-check-sections`/`--build-id=none` since the linker
  doesn't natively understand two memories intentionally sharing
  address 0.
- `build_arch_test.sh` — compiles one `.S` test file against the above
  and produces `instr_mem.hex`/`data_mem.hex` for the Verilator
  testbench to load. Requires `riscv32-unknown-elf-gcc` on `PATH` and
  `ARCH_TEST_ROOT` pointing at a riscv-arch-test clone (`old-framework-3.x`
  branch).
- `hex_convert.py` — binary-to-hex helper the build script calls.
- `tb_arch_test.sv` — Verilator testbench: preloads data memory
  (`core_dut.dmem.mem[]`), runs a fixed cycle budget (default 8000),
  dumps the signature region to a hex file.

## Usage

```bash
export ARCH_TEST_ROOT=~/riscv-arch-test   # old-framework-3.x branch
./build_arch_test.sh $ARCH_TEST_ROOT/riscv-test-suite/rv32i_m/I/src/add-01.S
cd build_add-01

verilator --binary --timing --trace ../tb_arch_test.sv ../../../rtl/rv32i/*.sv \
  --top-module tb_arch_test -Mdir obj_dir \
  -GDATA_HEX='"data_mem.hex"' -GSIG_START_WORD=<begin_signature/4> \
  -GSIG_END_WORD=<end_signature/4> -GOUT_FILE='"out.signature"'
./obj_dir/Vtb_arch_test
```

Get the signature bounds with `riscv32-unknown-elf-nm build_*/NAME.elf |
grep -E 'begin_signature|end_signature'` and divide the addresses by 4
(word-addressed memory).

## Verifying against a golden reference (spike)

Build spike from source (`riscv-software-src/riscv-isa-sim`), then build
the *same* test source against riscv-arch-test's own
`riscof-plugins/rv32/spike_simple/env` (link base `0x80000000`, separate
from this core's own address-0-based build) and diff the two signatures:

```bash
SPIKE_ENV=$ARCH_TEST_ROOT/riscof-plugins/rv32/spike_simple/env
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -static -mcmodel=medany \
  -nostdlib -nostartfiles -DXLEN=32 -DTEST_CASE_1 \
  -I $ARCH_TEST_ROOT/riscv-test-suite/env -I "$SPIKE_ENV" -T "$SPIKE_ENV/link.ld" \
  -o ref.elf $ARCH_TEST_ROOT/riscv-test-suite/rv32i_m/I/src/add-01.S
spike --isa=rv32i +signature=ref.signature +signature-granularity=4 ref.elf
diff ref.signature build_add-01/out.signature
```

An empty diff is a real pass.

## Gotchas (found the hard way, worth knowing before debugging a "failed" test)

1. **`-DTEST_CASE_1` is required at compile time.** Every generated test
   file wraps its entire payload in `#ifdef TEST_CASE_1`; without the
   flag, gcc silently compiles away the real test body, leaving only
   ~96 words of prologue/epilogue (a suspiciously tiny `.text` is the
   tell). `build_arch_test.sh` already passes this.
2. **`RVMODEL_HALT` must actually halt, not just write a sentinel and
   fall through.** This core's instruction memory indexes modulo
   `MEM_WORDS`; falling through into the zero-padded tail wraps the PC
   back to address 0 and silently re-executes the whole test a second
   time once the testbench's cycle budget runs long enough, corrupting
   the dump. `model_test.h` uses a `jal x0, halt_loop` self-loop — JAL is
   the one control-flow instruction this core actually redirects the PC
   on (conditional branches are decoded but not yet consumed by `pc.sv`).
3. **`-fno-pic` is required**, or `la`-based address loads (used by
   `RVTEST_SIGBASE` to set up the signature-region pointer) compile to
   GOT-indirect `auipc`+`lw` sequences instead of plain `auipc`+`addi`.
   The GOT then lands outside the generated `data_mem.hex`, so the load
   returns garbage and every signature write lands at the wrong address.
   `build_arch_test.sh` already passes this and checks for
   `GLOBAL_OFFSET_TABLE` in the disassembly (should print `0`).
