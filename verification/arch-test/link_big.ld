/* Oversized variant of link.ld for arch-test files whose generated
 * .text.init blows past the normal 16KB IMEM/DMEM (branch-offset and
 * JAL-offset tests pad real code out to exercise the far end of their
 * immediate's range). Same Harvard layout, just bigger regions. See
 * claude/arch-test-integration-plan.md, "Full suite sweep" -- jal-01 is
 * ~1.7MB, the six branch tests are ~220-300KB.
 */
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 0x200000   /* 2M bytes = 524288 words */
  DMEM (rw)  : ORIGIN = 0x00000000, LENGTH = 0x200000
}

SECTIONS
{
  .text.init : { *(.text.init) } > IMEM
  .text      : { *(.text) }      > IMEM

  .tohost : { *(.tohost) } > DMEM
  .data   : { *(.data) *(.data.*) } > DMEM
  .bss    : { *(.bss) *(.bss.*) }   > DMEM

  /DISCARD/ : { *(.note.*) *(.comment) *(.riscv.attributes) }
}
