OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 0x4000   /* 4096 words */
  DMEM (rw)  : ORIGIN = 0x00000000, LENGTH = 0x4000   /* 4096 words */
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
