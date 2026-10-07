# RISC-V 5-Stage Pipeline -> NPU Accelerator Conversion Workspace

This folder (`converting_into_NPU`) contains a complete copy of the 5-stage non-speculative always-stall RV32I pipeline core (`rtl/rv32i_pipelined_stallbranch/`) and its verification testbenches (`tb/rv32i_pipelined_stallbranch/`).

This workspace serves as the development environment for integrating hardware Neural Processing Unit (NPU) accelerator features into the RV32I pipeline.

---

## 1. Directory Structure

```text
converting_into_NPU/
├── rtl/                                # Base 5-Stage Always-Stall Pipeline RTL
│   ├── rv32i_pipeline_stallbranch_core.sv # Top-level CPU datapath
│   ├── hazard_unit_stallbranch.sv      # Priority hazard arbitration unit
│   ├── alu.sv                          # 32-bit ALU
│   ├── control.sv                      # Opcode decoder
│   ├── data_memory.sv                  # Harvard data memory
│   ├── imm_gen.sv                      # Immediate generator
│   ├── instruction_memory.sv           # Harvard instruction memory
│   ├── pc_pipeline.sv                  # Program counter with freeze logic
│   ├── pipeline_regs.sv                # Latched IF/ID, ID/EX, EX/MEM, MEM/WB registers
│   └── register_file_pipeline.sv       # 32-word regfile with WB-to-ID write-through
│
├── tb/                                 # Verification Testbenches
│   ├── tb_pipeline_stallbranch_core.sv        # Basic functional testbench
│   ├── tb_pipeline_stallbranch_hazards.sv     # Hazard stress testbench (11/11 cases)
│   ├── tb_pipeline_stallbranch_branch_jalr.sv # Branch/JALR regression
│   ├── tb_stall_behavior_check.sv             # Non-speculative fetch freeze check
│   ├── tb_pipeline_stallbranch_trace.sv       # Cycle-accurate telemetry testbench
│   └── instr_mem_stallbranch_demo.hex         # 18-cycle verified demo program
│
├── run_tests.sh                        # Automated test runner for this workspace
└── README.md                           # This document
```

---

## 2. Running Verification

To run all base regressions and verify the copied code:

```bash
chmod +x run_tests.sh
./run_tests.sh
```

---

## 3. Detailed NPU Implementation Roadmap

For the full, 5-phase engineering roadmap, memory map specifications, and driver details, see:
👉 **[`ROADMAP.md`](./ROADMAP.md)**

### Implementation Phases at a Glance:
- **Phase 1**: MEM Stage Bus Interconnect & Address Decoder (`is_npu_addr >= 32'h8000_0000`).
- **Phase 2**: NPU Top-Level Module, Control Registers & On-Chip SRAMs (`npu_top.sv`).
- **Phase 3**: Hardware Matrix Multiplication Engine (Compute FSM / MAC Unit).
- **Phase 4**: Software Driver (`npu_driver.h`) & Standard C Benchmark Application.
- **Phase 5**: Full Hardware-Software Co-Simulation & Architectural Regression Verification.

