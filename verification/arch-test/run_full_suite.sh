#!/usr/bin/env bash
# Build every rv32i_m/I/src/*.S file from riscv-arch-test against BOTH this
# repo's DUT (Verilator) and spike (golden reference), diff their
# signatures, and print a PASS/FAIL summary line per file plus a final
# count. This is the single entry point for reproducing the "38/38,
# 0 differences vs. spike" result documented in the project notes -- run
# it after the one-time environment setup in REPRODUCE.md.
#
# Usage (from anywhere):
#   ARCH_TEST_ROOT=~/riscv-arch-test SPIKE_BIN=~/riscv-isa-sim/build/spike \
#     ./run_full_suite.sh
#
# Required on PATH: riscv32-unknown-elf-gcc/-objcopy/-nm, verilator, python3.
# Required env vars: ARCH_TEST_ROOT (riscv-arch-test clone, old-framework-3.x
# branch), SPIKE_BIN (path to a spike binary built from source).
#
# Exit code is 0 iff every test file passed.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
CORE_RTL="$REPO_ROOT/rtl/rv32i"
TB="$HERE/tb_arch_test.sv"
HEXCONV="$HERE/hex_convert.py"
LINK_NORMAL="$HERE/link.ld"
LINK_BIG="$HERE/link_big.ld"

: "${ARCH_TEST_ROOT:?Set ARCH_TEST_ROOT to your riscv-arch-test clone (old-framework-3.x branch)}"
: "${SPIKE_BIN:?Set SPIKE_BIN to your spike binary (built from source)}"

ARCH_ENV="$ARCH_TEST_ROOT/riscv-test-suite/env"
SPIKE_PLUGIN_ENV="$ARCH_TEST_ROOT/riscof-plugins/rv32/spike_simple/env"
SRC_DIR="$ARCH_TEST_ROOT/riscv-test-suite/rv32i_m/I/src"

for bin in riscv32-unknown-elf-gcc riscv32-unknown-elf-objcopy riscv32-unknown-elf-nm verilator python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "FATAL: '$bin' not found on PATH" >&2; exit 2; }
done
[ -x "$SPIKE_BIN" ] || { echo "FATAL: SPIKE_BIN='$SPIKE_BIN' is not an executable file" >&2; exit 2; }
[ -d "$SRC_DIR" ] || { echo "FATAL: '$SRC_DIR' not found -- is ARCH_TEST_ROOT on the old-framework-3.x branch?" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Test files whose generated .text.init doesn't fit the DUT's normal 16KB
# Harvard IMEM (branch/JAL immediate-range coverage pads these out to
# 200KB-1.7MB) -- these need the bigger link script and bigger Verilator
# memory/cycle parameters. Everything else uses the normal ones.
BIG_TESTS="jal-01 beq-01 bne-01 blt-01 bge-01 bltu-01 bgeu-01"
is_big() { for t in $BIG_TESTS; do [ "$t" = "$1" ] && return 0; done; return 1; }

PASS=0
FAIL=0
FAILED_NAMES=""

CFLAGS_COMMON="-march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles -DXLEN=32 -DTEST_CASE_1 -Wl,--build-id=none -Wl,--no-check-sections"

for SRC in "$SRC_DIR"/*.S; do
  NAME="$(basename "$SRC" .S)"
  BUILD="$WORK/$NAME"
  mkdir -p "$BUILD"
  cd "$BUILD"

  if is_big "$NAME"; then
    LINK="$LINK_BIG"; MEMW=524288; MAXC=600000
  else
    LINK="$LINK_NORMAL"; MEMW=4096; MAXC=8000
  fi

  # ---- DUT side ----
  if ! riscv32-unknown-elf-gcc $CFLAGS_COMMON -I "$HERE" -I "$ARCH_ENV" -T "$LINK" \
        -o dut.elf "$SRC" > dut_compile.log 2>&1; then
    echo "${NAME}: FAIL (DUT compile error)"; FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"; continue
  fi
  riscv32-unknown-elf-objcopy -O binary --only-section=.text.init --only-section=.text dut.elf dut.text.bin
  riscv32-unknown-elf-objcopy -O binary --only-section=.tohost --only-section=.data --only-section=.bss dut.elf dut.data.bin
  python3 "$HEXCONV" dut.text.bin instr_mem.hex > /dev/null
  python3 "$HEXCONV" dut.data.bin data_mem.hex > /dev/null

  BEGIN_ADDR=$(riscv32-unknown-elf-nm dut.elf | awk '/ begin_signature$/{print $1}')
  END_ADDR=$(riscv32-unknown-elf-nm dut.elf | awk '/ end_signature$/{print $1}')
  if [ -z "$BEGIN_ADDR" ] || [ -z "$END_ADDR" ]; then
    echo "${NAME}: FAIL (no signature symbols in DUT elf)"; FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"; continue
  fi
  SIG_START_WORD=$((16#$BEGIN_ADDR / 4))
  SIG_END_WORD=$((16#$END_ADDR / 4))

  rm -rf obj_dir
  if ! verilator --binary --timing -Wno-fatal --top-module tb_arch_test -Mdir obj_dir \
        -GDATA_HEX="\"data_mem.hex\"" -GOUT_FILE="\"dut.signature\"" \
        -GSIG_START_WORD=${SIG_START_WORD} -GSIG_END_WORD=${SIG_END_WORD} \
        -GMEM_WORDS=${MEMW} -GMAX_CYCLES=${MAXC} \
        "$TB" "$CORE_RTL"/*.sv > verilator.log 2>&1; then
    echo "${NAME}: FAIL (Verilator build error -- see $BUILD/verilator.log)"; FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"; continue
  fi
  ./obj_dir/Vtb_arch_test > sim.log 2>&1
  if [ ! -f dut.signature ]; then
    echo "${NAME}: FAIL (sim produced no signature -- see $BUILD/sim.log)"; FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"; continue
  fi

  # ---- spike (golden) side ----
  if ! riscv32-unknown-elf-gcc $CFLAGS_COMMON -I "$SPIKE_PLUGIN_ENV" -I "$ARCH_ENV" \
        -T "$SPIKE_PLUGIN_ENV/link.ld" -o spike.elf "$SRC" > spike_compile.log 2>&1; then
    echo "${NAME}: FAIL (spike-side compile error)"; FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"; continue
  fi
  "$SPIKE_BIN" --isa=rv32i +signature=spike.signature +signature-granularity=4 spike.elf > spike_run.log 2>&1
  if [ ! -f spike.signature ]; then
    echo "${NAME}: FAIL (spike run produced no signature)"; FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"; continue
  fi

  # ---- compare ----
  grep -v '^\s*$' dut.signature > dut.sig.clean
  grep -v '^\s*$' spike.signature > spike.sig.clean
  DUT_WORDS=$(wc -l < dut.sig.clean)
  SPIKE_WORDS=$(wc -l < spike.sig.clean)

  if [ "$DUT_WORDS" != "$SPIKE_WORDS" ]; then
    echo "${NAME}: FAIL (word count mismatch: dut=${DUT_WORDS} spike=${SPIKE_WORDS})"
    FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"; continue
  fi
  DIFF_COUNT=$(diff dut.sig.clean spike.sig.clean | grep -c '^<')
  if [ "$DIFF_COUNT" -eq 0 ]; then
    echo "${NAME}: PASS (${DUT_WORDS} words, 0 differences)"
    PASS=$((PASS+1))
  else
    echo "${NAME}: FAIL (${DIFF_COUNT}/${DUT_WORDS} words differ -- see $BUILD/dut.sig.clean vs spike.sig.clean)"
    FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $NAME"
  fi
done

echo
echo "=== ${PASS} passed, ${FAIL} failed (of $((PASS+FAIL)) total) ==="
if [ "$FAIL" -gt 0 ]; then
  echo "Failed:${FAILED_NAMES}"
  exit 1
fi
exit 0
