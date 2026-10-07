# 5-Stage Pipelined RV32I Core

This directory contains the independent, 5-stage pipelined RV32I core implementation with full hazard handling:
- **IF Stage**: Instruction Fetch (`pc_pipeline.sv`, `instruction_memory.sv`)
- **ID Stage**: Instruction Decode (`control.sv`, `imm_gen.sv`, `register_file_pipeline.sv`)
- **EX Stage**: Execution & Branch Resolution (`alu.sv`, `rv32i_pipeline_core.sv`)
- **MEM Stage**: Data Memory Access (`data_memory.sv`)
- **WB Stage**: Register Writeback (`register_file_pipeline.sv`)
- **Hazard Handling**: Forwarding, Load-Use Stall, Branch/Jump Flush (`hazard_unit.sv`)
- **Pipeline Registers**: IF/ID, ID/EX, EX/MEM, MEM/WB (`pipeline_regs.sv`)

### Full Documentation
See [`docs/PIPELINE.md`](file:///home/enovo/riscv-ai-accelerator/docs/PIPELINE.md) for full architectural specifications, timing diagrams, hazard truth tables, and verification results.

### Verification
- **Unit Regressions**: In [`tb/rv32i_pipelined/`](file:///home/enovo/riscv-ai-accelerator/tb/rv32i_pipelined/)
- **Full 38-Test Compliance Suite**: Run `verification/arch-test/run_pipeline_suite.sh` (38/38 PASS vs Spike).

