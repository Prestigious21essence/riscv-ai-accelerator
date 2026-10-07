# 5-Stage Pipelined RV32I Core (Always-Stall on Branch)

This directory contains the independent **Always-Stall on Branch** 5-stage pipelined RV32I core:
- **Architecture**: Classic 5-stage RISC-V Harvard architecture (`rv32i_pipeline_stallbranch_core.sv`).
- **Hazard Handling**:
  - RAW Data Forwarding (EX-to-EX and MEM-to-EX for ALU and store data)
  - Load-Use Hazard Detection Unit (1-cycle hardware stall)
  - **Always-Stall on Branch/Jump**: Instruction fetch is frozen whenever a branch or jump enters ID until it resolves in EX. Zero speculative instructions ever enter the datapath.
  - Register File Write-First internal bypass (`register_file_pipeline.sv`).

### Documentation
See [`docs/BRANCH_STALL.md`](file:///home/enovo/riscv-ai-accelerator/docs/BRANCH_STALL.md) for cycle-by-cycle diagrams and hardware trade-offs vs the speculative core in `rtl/rv32i_pipelined/`.

### Verification
- **Unit Regressions**: [`tb/rv32i_pipelined_stallbranch/`](file:///home/enovo/riscv-ai-accelerator/tb/rv32i_pipelined_stallbranch/) (All pass)
- **Full Compliance Suite**: Run `verification/arch-test/run_stallbranch_suite.sh` (**38/38 PASS** vs Spike).

