#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H
// Minimal target header for the riscv-ai-accelerator single-cycle core.
// Deliberately does NOT define rvtest_mtrap_routine / rvtest_gpr_save.
#define ALIGNMENT 2
#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 4; .global tohost; tohost: .word 0;                      \
        .align 4; .global fromhost; fromhost: .word 0;                  \
        .popsection;                                                    \
        .align 4; .global begin_regstate; begin_regstate:                \
        .word 128;                                                      \
        .align 4; .global end_regstate; end_regstate:                   \
        .word 4;
// RVMODEL_HALT must actually stop the core, not just write a sentinel and
// fall through: this core's instruction memory is word-indexed modulo
// MEM_WORDS, so falling through into the zero-padded tail wraps back to
// address 0 and silently RE-EXECUTES the entire test program a second
// time once the testbench's cycle budget runs long enough -- corrupting
// the signature dump well after it was already written correctly once.
// JAL is implemented and IS wired to redirect the PC (unlike conditional
// branches, which are decoded but not yet consumed by pc.sv), so a JAL-
// based self-loop is the one control-flow instruction this core can use
// to genuinely park here forever.
#define RVMODEL_HALT \
  li  x31, 0xdeadc0de;  \
  sw  x31, tohost, x30; \
halt_loop: \
  jal x0, halt_loop;
#define RVMODEL_BOOT
#define RVMODEL_DATA_BEGIN \
  RVMODEL_DATA_SECTION     \
  .align ALIGNMENT;        \
  .global begin_signature; begin_signature:
#define RVMODEL_DATA_END \
  .align ALIGNMENT; .global end_signature; end_signature:
#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT
#endif
