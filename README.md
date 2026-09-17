# RISC-V AI Accelerator RTL

RISC-V RTL implementation exploring pipelined and superscalar/VLIW-like
architectures, developed under Prof. Ashwin.

## Scope
- RV32I: base pipelined scalar core
- RV32IV: + vector extension
- RV32IVMatrix: + matrix/tensor unit
- Automated, self-checking testbenches for each variant
- (Phase 2) Multi-instruction issue: superscalar and VLIW-like exploration

## Status
- **RV32I Single-Cycle Core** (`rtl/rv32i/`): Fully verified, 38/38 official `riscv-arch-test` passing bit-for-bit against Spike.
- **RV32I 5-Stage Pipelined Core (Speculative / Predict Not-Taken)** (`rtl/rv32i_pipelined/`): 5 stages (IF, ID, EX, MEM, WB) with full hazard resolution (forwarding, load-use stall, branch/jump flushes, register write-through). Fully verified, 38/38 official `riscv-arch-test` passing bit-for-bit against Spike. Detailed design in [`docs/PIPELINE.md`](docs/PIPELINE.md).
- **RV32I 5-Stage Pipelined Core (Always-Stall on Branch)** (`rtl/rv32i_pipelined_stallbranch/`): 5 stages with non-speculative branch stalling (freezes fetch on branch/jump in ID until resolved in EX; zero wrong-path instructions executed). Fully verified, 38/38 official `riscv-arch-test` passing bit-for-bit against Spike. Detailed design in [`docs/BRANCH_STALL.md`](docs/BRANCH_STALL.md).

## Reference
Architecture studied via vortexgpgpu/vortex.

