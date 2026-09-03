#!/usr/bin/env bash
# Same as build_arch_test.sh, but for the handful of arch-test files whose
# generated .text.init doesn't fit the normal 16KB IMEM (branch-offset and
# JAL-offset tests deliberately pad real code out to the far end of their
# immediate's range -- see claude/arch-test-integration-plan.md, "Full
# suite sweep"). Only difference: links against link_big.ld (2MB IMEM/DMEM)
# instead of link.ld. You'll also need to elaborate tb_arch_test.sv with
# -GMEM_WORDS=524288 -GMAX_CYCLES=600000 instead of the defaults -- see
# step 7 in RUN_BRANCH_JALR_IN_WSL2.md.
#
# Needed for: jal-01, beq-01, bne-01, blt-01, bge-01, bltu-01, bgeu-01.
# Everything else should still use the normal build_arch_test.sh.
#
# Usage:
#   ./build_arch_test_big.sh /path/to/riscv-arch-test/riscv-test-suite/rv32i_m/I/src/beq-01.S

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <test.S>" >&2
  exit 1
fi

SRC="$1"
NAME="$(basename "$SRC" .S)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/build_$NAME"
mkdir -p "$BUILD"

: "${ARCH_TEST_ROOT:?Set ARCH_TEST_ROOT to your riscv-arch-test clone (old-framework-3.x branch)}"

riscv32-unknown-elf-gcc \
  -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
  -DXLEN=32 -DTEST_CASE_1 \
  -Wl,--build-id=none -Wl,--no-check-sections \
  -I "$ARCH_TEST_ROOT/riscv-test-suite/env" -I "$HERE" \
  -T "$HERE/link_big.ld" \
  -o "$BUILD/$NAME.elf" "$SRC"

riscv32-unknown-elf-objcopy -O binary --only-section=.text.init --only-section=.text \
  "$BUILD/$NAME.elf" "$BUILD/$NAME.text.bin"
riscv32-unknown-elf-objcopy -O binary --only-section=.tohost --only-section=.data --only-section=.bss \
  "$BUILD/$NAME.elf" "$BUILD/$NAME.data.bin"

python3 "$HERE/hex_convert.py" "$BUILD/$NAME.text.bin" "$BUILD/instr_mem.hex"
python3 "$HERE/hex_convert.py" "$BUILD/$NAME.data.bin" "$BUILD/data_mem.hex"

riscv32-unknown-elf-objdump -d -M no-aliases "$BUILD/$NAME.elf" > "$BUILD/$NAME.dis"

echo "--- instructions used by $NAME ---"
grep -oP '(?<=\t)[a-z0-9\.]+(?=\t)' "$BUILD/$NAME.dis" | sort -u

echo
echo "Wrote $BUILD/instr_mem.hex and $BUILD/data_mem.hex"
echo "Remember: elaborate tb_arch_test.sv with -GMEM_WORDS=524288 -GMAX_CYCLES=600000 for this one."
