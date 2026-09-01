#!/usr/bin/env bash
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

# -fno-pic: without it, "la"-based address loads (used by RVTEST_SIGBASE to
# set up the signature-region pointer) compile to GOT-indirect auipc+lw
# sequences instead of plain auipc+addi -- the GOT then lands outside this
# script's own data_mem.hex, so the load returns garbage and the signature
# pointer ends up wrong. Confirmed via objdump: without this flag you get
# "auipc gp,0x2; lw gp,2032(gp)"; with it, "auipc gp,0x2; addi gp,gp,-328".
riscv32-unknown-elf-gcc \
  -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles -fno-pic \
  -DXLEN=32 -DTEST_CASE_1 \
  -Wl,--build-id=none -Wl,--no-check-sections \
  -I "$ARCH_TEST_ROOT/riscv-test-suite/env" -I "$HERE" \
  -T "$HERE/link.ld" \
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
echo "--- checking for GOT-indirect addressing (should be empty) ---"
grep -c "GLOBAL_OFFSET_TABLE" "$BUILD/$NAME.dis" || true
echo
echo "Wrote $BUILD/instr_mem.hex and $BUILD/data_mem.hex"
