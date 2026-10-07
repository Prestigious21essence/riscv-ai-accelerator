# RISC-V AI Accelerator: Complete Project Architecture, Implementation & Verification Summary

**Project Lead / Architect**: Advised under Prof. Ashwin  
**Repository**: `riscv-ai-accelerator`  
**Status**: Single-Cycle Core Verified | 5-Stage Speculative Pipeline Verified | 5-Stage Always-Stall Pipeline Verified | MMIO NPU Coprocessor Verified  
**Compliance**: **38/38 PASS (100%)** on official RISC-V Architectural Compliance Test Suite (`riscv-arch-test`) vs. Spike golden reference across all cores.

---

## Table of Contents
1. [Project Overview & Architectural Roadmap](#1-project-overview--architectural-roadmap)
2. [Microarchitecture 1: RV32I Single-Cycle Processor](#2-microarchitecture-1-rv32i-single-cycle-processor)
   - [2.1 Core Datapath & Modules](#21-core-datapath--modules)
   - [2.2 5-Stage Conceptual Anatomy (IF / ID / EX / MEM / WB)](#22-5-stage-conceptual-anatomy-if--id--ex--mem--wb)
   - [2.3 Instruction Format Coverage & Execution Sequence](#23-instruction-format-coverage--execution-sequence)
   - [2.4 Verification & Compliance Results](#24-verification--compliance-results)
3. [Microarchitecture 2: 5-Stage Speculative Pipelined Core](#3-microarchitecture-2-5-stage-speculative-pipelined-core)
   - [3.1 Physical Stages & Latched Pipeline Registers](#31-physical-stages--latched-pipeline-registers)
   - [3.2 Forwarding & Hazard Resolution Units](#32-forwarding--hazard-resolution-units)
   - [3.3 Speculative Predict-Not-Taken Branch Logic](#33-speculative-predict-not-taken-branch-logic)
   - [3.4 Verification & Compliance Results](#34-verification--compliance-results)
4. [Microarchitecture 3: 5-Stage Always-Stall on Branch Core](#4-microarchitecture-3-5-stage-always-stall-on-branch-core)
   - [4.1 Motivation & Non-Speculative Design Philosophy](#41-motivation--non-speculative-design-philosophy)
   - [4.2 Cycle-by-Cycle Timing & Fetch Freezing](#42-cycle-by-cycle-timing--fetch-freezing)
   - [4.3 Priority Hazard Arbitration Logic](#43-priority-hazard-arbitration-logic)
   - [4.4 Microarchitectural Comparison: Speculative vs. Always-Stall](#44-microarchitectural-comparison-speculative-vs-always-stall)
   - [4.5 Verification & Compliance Results](#45-verification--compliance-results)
5. [Cycle-Accurate Pipeline Execution & Hazard Verification](#5-cycle-accurate-pipeline-execution--hazard-verification)
   - [5.1 Verified 18-Cycle Pipeline Execution Gantt Timeline](#51-verified-18-cycle-pipeline-execution-gantt-timeline)
   - [5.2 Cycle-by-Cycle Hazard Mechanics Breakdown](#52-cycle-by-cycle-hazard-mechanics-breakdown)
6. [Repository Structure & File Organization](#6-repository-structure--file-organization)
7. [Reproduction Commands & Verification Runbook](#7-reproduction-commands--verification-runbook)
   - [7.1 How to Test the CPU](#71-how-to-test-the-cpu)
   - [7.2 How to Test the NPU](#72-how-to-test-the-npu)
8. [Neural Processing Unit (NPU) Architecture & Hardware Acceleration](#8-neural-processing-unit-npu-architecture--hardware-acceleration)

---

## 1. Project Overview & Architectural Roadmap

The **RISC-V AI Accelerator** project focuses on the clean-slate RTL design, hardware verification, and cycle-accurate performance analysis of high-efficiency RISC-V compute cores. The architecture is developed in SystemVerilog, targeting low-power embedded intelligence, machine learning edge acceleration, and high-throughput matrix compute.

### Multi-Phase Engineering Trajectory
```
Phase 1: Scalar Foundations (COMPLETE)
  ├── 1. RV32I Single-Cycle Processor (rtl/rv32i/)
  ├── 2. RV32I 5-Stage Speculative Pipelined Core (rtl/rv32i_pipelined/)
  ├── 3. RV32I 5-Stage Always-Stall Pipelined Core (rtl/rv32i_pipelined_stallbranch/)
  └── 4. Cycle-Accurate Hazard & Telemetry Verification Engine

Phase 2: Neural Processing Unit (NPU) Coprocessor (COMPLETE)
  ├── 1. Memory-Mapped I/O (MMIO) bus integration at 0x8000_0000
  ├── 2. Dedicated on-chip SRAM buffers for Matrix A, B, and C (256x32 each)
  ├── 3. High-throughput 32-bit Multiply-Accumulate (MAC) datapath (1 MAC/cycle)
  └── 4. Bit-exact 32x32 tiled GEMM hardware-software co-simulation

Phase 3: Advanced Execution Topologies (FUTURE)
  └── Multi-issue superscalar and VLIW-like execution clusters inspired by Vortex GPGPU
```

All implementations are strictly verified against the **official RISC-V Architectural Test Suite (`riscv-arch-test`)** using the Berkeley **Spike ISS (Instruction Set Simulator)** as the bit-for-bit golden reference.

---

## 2. Microarchitecture 1: RV32I Single-Cycle Processor

Located in [`rtl/rv32i/`](rtl/rv32i/), this core implements the baseline RV32I unpipelined architecture. Every instruction is fetched, decoded, executed, accesses memory, and writes back its architectural state in exactly **one clock cycle** ($\text{CPI} = 1.0$).

```
+----------------------------------------------------------------------------------------------------+
|                                    RV32I Single-Cycle Core                                         |
|                                                                                                    |
|  +-------+  PC  +-------------+  Instr  +---------+   Reg Data   +-------+   ALU Out  +---------+  |
|  |  PC   |----->| Instruction |-------->| Control |------------->|  ALU  |----------->|  Data   |  |
|  | Logic |      |   Memory    |         | & Regs  |              | Logic |            | Memory  |  |
|  +-------+      +-------------+         +---------+              +-------+            +---------+  |
|      ^                                                                                     |       |
|      |                                     Writeback Bus                                   |       |
|      +-------------------------------------------------------------------------------------+       |
+----------------------------------------------------------------------------------------------------+
```

### 2.1 Core Datapath & Modules

1. **Program Counter (`pc.sv`)**:
   - Maintains the 32-bit instruction address pointer.
   - Synchronously updates on `posedge clk`:
     $$\text{next\_pc} = \begin{cases} \text{branch\_target} & \text{if branch is taken} \\ \text{jump\_target} & \text{if JAL or JALR} \\ \text{current\_pc} + 4 & \text{otherwise} \end{cases}$$
2. **Instruction Memory (`instruction_memory.sv`)**:
   - 32-bit word-aligned memory array providing combinational instruction lookup for `pc[IDX_HI:2]`.
3. **Control Unit (`control.sv`)**:
   - Full combinational opcode/funct3/funct7 decoder producing control lines: `reg_write`, `mem_read`, `mem_write`, `mem_to_reg`, `alu_src`, `alu_op`, `branch`, `lui`, `jal`, `jalr`, `auipc`.
4. **Immediate Generator (`imm_gen.sv`)**:
   - Decodes 32-bit sign-extended immediates across I-type, S-type, B-type, U-type, and J-type instruction encodings.
5. **Register File (`register_file.sv`)**:
   - 32 general-purpose 32-bit registers ($x0 \dots x31$).
   - Synchronous write on `posedge clk` when `reg_write = 1` and `rd != 0`.
   - Register $x0$ is hardwired to zero. Combinational read ports for `rs1` and `rs2`.
6. **ALU (`alu.sv`)**:
   - 32-bit execution unit supporting: `ADD`, `SUB`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`, `SLT` (signed comparison), and `SLTU` (unsigned comparison).
7. **Data Memory (`data_memory.sv`)**:
   - Byte-addressable Harvard data memory supporting byte (`LB`, `LBU`, `SB`), halfword (`LH`, `LHU`, `SH`), and full word (`LW`, `SW`) operations with sign/zero extension.

---

### 2.2 5-Stage Conceptual Anatomy (IF / ID / EX / MEM / WB)

Although physically evaluated in a single clock period, the execution path naturally decomposes into 5 functional stages:

| Stage | Input Items Used | Hardware Operation & Logic | Output Items Produced | Memory & State Handling |
|---|---|---|---|---|
| **1. IF (Fetch)** | `pc` (32-bit address) | IMEM word lookup, PC+4 adder | `instr` (32-bit word), `pc_plus_4` | Read-only access to Instruction Memory |
| **2. ID (Decode)** | `instr`, Register File | Opcode/funct parsing, immediate generation, regfile read | `rs1_data`, `rs2_data`, `imm`, control lines | Combinational regfile read; $x0$ forced to $0$ |
| **3. EX (Execute)** | `rs1_data`, `rs2_data`, `imm`, `pc` | Operand muxing, ALU arithmetic/logic, branch condition evaluation, jump target adder | `alu_result`, `zero_flag`, `branch_taken`, `target_pc` | Combinational execution; zero memory interaction |
| **4. MEM (Memory)** | `alu_result` (address), `rs2_data` (store data) | Byte/half/word address decoding, byte-write masking, read alignment | `read_data` (from DMEM) | If `mem_read`: DMEM read; If `mem_write`: DMEM write; Else: bypass |
| **5. WB (Writeback)**| `alu_result`, `read_data`, `pc_plus_4` | Multiplexer selection (`mem_to_reg`, `jal/jalr`) | `wb_data` written to `rd` register | Synchronous register write committed at next `posedge clk` |

---

### 2.3 Instruction Format Coverage & Execution Sequence

The single-cycle core was verified across a comprehensive 12-instruction sequence covering all major RV32I formats without duplicate terminal loop rows:

```text
 #  PC      Instr Hex   Disassembly             Format  Operation
 1  0x0000  0x123450b7  lui   x1, 0x12345       U-Type  x1 = 0x12345000 (Upper immediate)
 2  0x0004  0x00002117  auipc x2, 2             U-Type  x2 = PC + (2 << 12) = 0x00002004
 3  0x0008  0x01900193  addi  x3, x0, 25        I-Type  x3 = 0 + 25 = 25 (ALU immediate)
 4  0x000c  0x00318233  add   x4, x3, x3        R-Type  x4 = 25 + 25 = 50 (Register addition)
 5  0x0010  0x02402023  sw    x4, 32(x0)        S-Type  Mem[32] = 50 (Word store)
 6  0x0014  0x02002283  lw    x5, 32(x0)        I-Type  x5 = Mem[32] = 50 (Word load)
 7  0x0018  0x00521463  bne   x4, x5, +8        B-Type  50 != 50? False -> Not taken (fallthrough)
 8  0x001c  0x00520463  beq   x4, x5, +8        B-Type  50 == 50? True -> Taken (Target = 0x24)
 9  0x0024  0x008003ef  jal   x7, +8            J-Type  x7 = 0x28, Jump to 0x2c
10  0x002c  0x00c38567  jalr  x10, 12(x7)       I-Type  x10 = 0x30, Jump to x7 + 12 = 0x34
11  0x0034  0x06400593  addi  x11, x0, 100      I-Type  x11 = 100
12  0x0038  0x0000006f  jal   x0, 0             J-Type  Self-loop (program termination)
```

---

### 2.4 Verification & Compliance Results

- **Official Architectural Suite (`verification/arch-test/run_singlecycle_suite.sh`)**:
  - **38/38 PASS (100%)** bit-for-bit match with Spike golden memory signatures.
- **Unit Test Regression**:
  - `tb_auipc.sv`: Validates PC-relative upper immediate math.
  - `tb_branch_jalr.sv`: Validates all 6 branch conditions (`BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`) and indirect jumps.
  - `tb_lui_jal.sv`: Validates large constant loads and unconditional jumps with link.
  - `tb_register_file.sv`: Validates dual-port read, single-port synchronous write, and zero-register immutability.
  - `tb_sltu_bytemem.sv`: Validates unsigned comparisons and byte/halfword memory alignments.

---

## 3. Microarchitecture 2: 5-Stage Speculative Pipelined Core

Located in [`rtl/rv32i_pipelined/`](rtl/rv32i_pipelined/), this core implements a classical 5-stage RISC pipeline with speculative execution, dynamic hazard forwarding, and predict-not-taken branch resolution.

```
                      +-------------------+
                      |   Hazard Unit     |<--------------------+
                      | - Forwarding      |                     |
                      | - Load-Use Stall  |                     |
                      | - Branch Flush    |                     |
                      +---+---+---+---+---+                     |
                          |   |   |   |                         |
         Flush/Stall      |   |   |   | Forwarding              |
         +----------------+   |   |   +---------------------+   |
         |                    |   +---------------------+   |   |
         v                    v                         v   v   |
    +---------+   IF/ID   +--------+   ID/EX   +--------+   +--------+   MEM/WB  +--------+
--->|   IF    |==========>|   ID   |==========>|   EX   |==>|  MEM   |==========>|   WB   |
    |         |           |        |           |        |   |        |           |        |
    | PC+IMEM |           | Decode |           |  ALU   |   |  DMEM  |           | Regfile|
    +---------+           | RegFile|           | Branch |   +--------+           | Write  |
         ^                +--------+           +--------+        |               +---+----+
         |                    ^                     |            |                   |
         |                    | Write-First Bypass  +------------+                   |
         |                    +------------------------------------------------------+
         | Branch/Jump Target                       Writeback Data
         +---------------------------------------------------------------------------+
```

### 3.1 Physical Stages & Latched Pipeline Registers

1. **`if_id_reg`**: Latches instruction fetch output.
   - Signals: `pc`, `instr`.
   - Control: Enabled by `if_id_write`; cleared by `flush_if_id` (inserts NOP `0x00000013`).
2. **`id_ex_reg`**: Latches decoded operands and execution controls.
   - Signals: `pc`, `rs1_data`, `rs2_data`, `imm`, `rs1`, `rs2`, `rd`, funct3, funct7, and control lines (`reg_write`, `mem_read`, `mem_write`, `mem_to_reg`, `alu_src`, `alu_op`, `branch`, `lui`, `jal`, `jalr`, `auipc`).
   - Control: Synchronous flush on `flush_id_ex` (clears control words to zero).
3. **`ex_mem_reg`**: Latches execution results and memory access signals.
   - Signals: `pc`, `alu_result`, `write_data` (store data), `rd`, funct3, `reg_write`, `mem_read`, `mem_write`, `mem_to_reg`.
4. **`mem_wb_reg`**: Latches memory read data and writeback selections.
   - Signals: `read_data`, `alu_result`, `link_addr`, `rd`, `reg_write`, `mem_to_reg`, `jal/jalr`.

---

### 3.2 Forwarding & Hazard Resolution Units

#### RAW Data Forwarding (`hazard_unit.sv`)
Resolves Read-After-Write hazards without stalling by forwarding operands directly to the ALU in EX:
- **EX-to-EX Forwarding (Distance 1)**:
  `if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs1) forward_a = 2'b10;`
- **MEM-to-EX Forwarding (Distance 2)**:
  `else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs1) forward_a = 2'b01;`
- **Store Data Forwarding**:
  `forward_b` routes forwarded operands directly into `ex_write_data`. An additional MEM-stage bypass allows back-to-back `LW -> SW` sequences to execute with only 1 stall cycle.

#### Load-Use Hazard Stall Unit
When an instruction in ID reads a register loaded by an immediately preceding load instruction in EX:
```systemverilog
assign load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                         ((id_uses_rs1 && (id_rs1 == id_ex_rd)) ||
                          (id_uses_rs2 && (id_rs2 == id_ex_rd)));
```
Hardware action:
1. `pc_write = 1'b0`: PC register frozen.
2. `if_id_write = 1'b0`: `IF/ID` register frozen.
3. `flush_id_ex = 1'b1`: Bubble NOP injected into `ID/EX`.

#### Register File Write-Through (WB-to-ID Bypass)
When instruction $i$ in WB writes to register $x_k$ and instruction $i+2$ in ID reads $x_k$ in the same cycle:
`assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 : (we && (rd_addr == rs1_addr)) ? rd_data : regs[rs1_addr];`

---

### 3.3 Speculative Predict-Not-Taken Branch Logic

- **Speculation Strategy**: Fetches sequentially ($PC+4$) behind every branch.
- **Resolution**: Branch condition evaluated in the **EX stage**.
- **Not-Taken**: Speculation correct $\rightarrow$ **0-cycle penalty**.
- **Taken / JAL / JALR**: Speculation incorrect $\rightarrow$ **2-cycle penalty**.
  - `ex_redirect = 1'b1` redirects PC to target address.
  - `flush_if_id = 1'b1` and `flush_id_ex = 1'b1` purge the 2 speculatively fetched wrong-path instructions.

---

### 3.4 Verification & Compliance Results

- **Official Architectural Suite (`run_pipeline_suite.sh`)**: **38/38 PASS (100%)** bit-for-bit vs. Spike.
- **Core Regression (`tb_pipeline_core.sv`)**: 7/7 PASS.
- **Branch/JALR Regression (`tb_pipeline_branch_jalr.sv`)**: 19/19 PASS (0 leaked instructions).
- **Hazard Stress Test (`tb_pipeline_hazards.sv`)**: 11/11 PASS (forwarding, load-use stall, regfile bypass).

---

## 4. Microarchitecture 3: 5-Stage Always-Stall on Branch Core

Located in [`rtl/rv32i_pipelined_stallbranch/`](rtl/rv32i_pipelined_stallbranch/), this core implements a robust, non-speculative branch resolution model.

```
+-----------------------------------+-----------------------------------+
|   Predict-Not-Taken (Speculative) |    Always-Stall (Non-Speculative) |
|      [rtl/rv32i_pipelined/]       | [rtl/rv32i_pipelined_stallbranch/]|
+-----------------------------------+-----------------------------------+
| - Fetches PC+4 speculatively      | - Freezes PC fetch when branch    |
|   behind every branch.            |   arrives in ID stage.            |
| - Resolves condition in EX stage. | - Resolves condition in EX stage. |
| - If Taken:                       | - In EX, updates PC to target or  |
|   Flushes IF/ID & ID/EX (2 bubbles|   fallthrough address.            |
| - If Not-Taken:                   | - Both Taken & Not-Taken incur    |
|   0 penalty (speculation correct).|   2 stall cycles.                 |
| - Requires pipeline flush logic.  | - Zero speculative instructions   |
|                                   |   ever enter the datapath.        |
+-----------------------------------+-----------------------------------+
```

### 4.1 Motivation & Non-Speculative Design Philosophy

In security-critical, deterministic, or mixed-criticality accelerator environments, speculative execution introduces timing side channels (e.g., Spectre-style cache perturbation) and complex recovery rollbacks. The **Always-Stall on Branch** core eliminates speculation completely:
- Zero instructions on the wrong execution path are ever fetched or decoded.
- All branch conditions and targets are evaluated deterministically in EX before the next instruction fetch occurs.

---

### 4.2 Cycle-by-Cycle Timing & Fetch Freezing

#### Example: Branch at Address `0x100` (Taken Target = `0x200`)
```
Cycle 1: IF: Fetches BEQ at 0x100. Next sequential PC becomes 0x104.
Cycle 2: ID: BEQ arrives in ID (id_branch_or_jump = 1).
         Hardware Action:
         - pc_write = 0 (PC held at 0x104, fetch frozen)
         - if_id_write = 1, flush_if_id = 1 (inserts bubble NOP into IF/ID)
         - BEQ advances cleanly into EX stage.
Cycle 3: EX: BEQ evaluates in EX stage (ex_branch_or_jump = 1).
         Hardware Action:
         - Condition evaluates to TAKEN.
         - ex_resolved_pc = 0x200 (target address).
         - pc_write = 1 (PC updates to 0x200 on next clock edge).
         - if_id_write = 0 (fetch remains stalled; no fetch into IF/ID).
         - flush_if_id = 0 (no speculative fetch, no flush; IF/ID holds NOP bubble).
         - flush_id_ex = 0.
Cycle 4: IF: Fetches target instruction at 0x200.
         ID: NOP bubble.
         EX: NOP bubble.
         MEM: BEQ in MEM.
Cycle 5: ID: Decodes target instruction at 0x200.
         EX: NOP bubble.
         MEM: NOP bubble.
         WB: BEQ in WB.
```
**Net Result**: Exactly 2 bubble cycles. Exactly 0 wrong-path instructions fetched or executed.

---

### 4.3 Priority Hazard Arbitration Logic

The hazard unit (`hazard_unit_stallbranch.sv`) enforces strict priority across load-use data stalls and branch control freezes:

```systemverilog
always_comb begin
    if (load_use_hazard) begin
        // Priority 1: Load-use stall takes precedence.
        // Freezes PC and IF/ID, inserts bubble into ID/EX.
        pc_write    = 1'b0;
        if_id_write = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b1;
    end else if (ex_branch_or_jump) begin
        // Priority 2: Branch/jump is resolving in EX this cycle.
        // Enable PC update to the resolved target/fallthrough address at clock edge.
        // Instruction fetch remains stalled: do NOT fetch into IF/ID, and do NOT flush.
        // IF/ID holds the bubble cleanly without fetching or flushing.
        pc_write    = 1'b1;
        if_id_write = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;
    end else if (id_branch_or_jump) begin
        // Priority 3: Branch/jump arrives in ID.
        // Freeze instruction fetch until branch reaches EX and resolves.
        // Insert bubble into IF/ID, allow branch to advance to EX.
        pc_write    = 1'b0;
        if_id_write = 1'b1;
        flush_if_id = 1'b1;
        flush_id_ex = 1'b0;
    end else begin
        // Priority 4: Normal sequential execution.
        pc_write    = 1'b1;
        if_id_write = 1'b1;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;
    end
end
```

#### Hardware Bubble Insertion Nomenclature
In `pipeline_regs.sv`, the synchronous clear input on `id_ex_reg` and `if_id_reg` is labeled `flush`:
- `id_ex_reg.flush` (`flush_id_ex`): Inserts a 1-cycle NOP bubble into EX during a load-use stall so the dependent instruction frozen in ID does not execute twice.
- `if_id_reg.flush` (`flush_if_id`): Inserts a NOP bubble into IF/ID when a branch arrives in ID.
- `ex_mem_reg` and `mem_wb_reg` have **no** flush inputs because bubbles are never injected into MEM or WB.

---

### 4.4 Microarchitectural Comparison: Speculative vs. Always-Stall

| Microarchitectural Parameter | Speculative Predict-Not-Taken (`rtl/rv32i_pipelined/`) | Always-Stall on Branch (`rtl/rv32i_pipelined_stallbranch/`) |
|---|---|---|
| **Branch Penalty (Taken)** | 2 cycles (flushes IF/ID and ID/EX) | 2 cycles (fetch frozen in ID and EX) |
| **Branch Penalty (Not-Taken)** | **0 cycles** (speculation correct) | 2 cycles (fixed stall) |
| **JAL / JALR Penalty** | 2 cycles (flushes IF/ID and ID/EX) | 2 cycles (fetch frozen in ID and EX) |
| **Wrong-Path Execution** | Fetches 2 instructions speculatively | **Zero** wrong-path instructions ever fetched |
| **Pipeline Flush Count** | 2 flushes per taken branch/jump | **0 flushes** (strictly stalls/bubbles) |
| **Hardware Complexity** | Dual-stage pipeline flush network | Simpler fetch freeze and bubble insertion |
| **Architectural Compliance** | **38/38 PASS (100%)** | **38/38 PASS (100%)** |

---

### 4.5 Verification & Compliance Results

- **Official Architectural Suite (`run_stallbranch_suite.sh`)**: **38/38 PASS (100%)** bit-for-bit vs. Spike.
- **Branch & JALR Regression (`tb_pipeline_stallbranch_branch_jalr.sv`)**: 19/19 PASS.
- **Hazard Regression (`tb_pipeline_stallbranch_hazards.sv`)**: 11/11 PASS (EX-EX forward, MEM-EX forward, load-use stall, store forwarding, write-first regfile bypass).
- **Core Regression (`tb_pipeline_stallbranch_core.sv`)**: 7/7 PASS.

---

## 5. Cycle-Accurate Pipeline Execution & Hazard Verification

The 5-stage pipeline behavior is verified with cycle-accurate probing at `negedge clk` across both normal execution and hazard conditions. This methodology verifies the exact cycle transitions through `IF ➔ ID ➔ EX ➔ MEM ➔ WB`, tracking register forwarding, load-use stall insertion, and non-speculative branch resolution.

### 5.1 Verified 18-Cycle Pipeline Execution Gantt Timeline

The non-speculative always-stall pipeline running [`instr_mem_stallbranch_demo.hex`](tb/rv32i_pipelined_stallbranch/instr_mem_stallbranch_demo.hex) completes in exactly **18 cycles**:

```text
==============================================================================================================================
                                     RISC-V 5-STAGE PIPELINE EXECUTION GANTT CHART
==============================================================================================================================
PC       Instruction                     |  1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18
------------------------------------------------------------------------------------------------------------------------------
0x0000   addi    x1, x0, 10              | IF  ID  EX  ME  WB   .   .   .   .   .   .   .   .   .   .   .   .   .
0x0004   addi    x2, x1, 20              |  .  IF  ID  EX  ME  WB   .   .   .   .   .   .   .   .   .   .   .   .
0x0008   add     x3, x1, x2              |  .   .  IF  ID  EX  ME  WB   .   .   .   .   .   .   .   .   .   .   .
0x000c   addi    x4, x0, 100             |  .   .   .  IF  ID  EX  ME  WB   .   .   .   .   .   .   .   .   .   .
0x0010   nop                             |  .   .   .   .  IF  ID  EX  ME  WB   .   .   .   .   .   .   .   .   .
0x0014   add     x5, x4, x1              |  .   .   .   .   .  IF  ID  EX  ME  WB   .   .   .   .   .   .   .   .
0x0018   sw      x1, 0(x0)               |  .   .   .   .   .   .  IF  ID  EX  ME  WB   .   .   .   .   .   .   .
0x001c   lw      x6, 0(x0)               |  .   .   .   .   .   .   .  IF  ID  EX  ME  WB   .   .   .   .   .   .
0x0020   addi    x7, x6, 5               |  .   .   .   .   .   .   .   .  IF ID*  EX  ME  WB   .   .   .   .   .
0x0024   beq     x1, x6, 8               |  .   .   .   .   .   .   .   .   .  IF  ID  EX  ME  WB   .   .   .   .
0x002c   addi    x9, x0, 77              |  .   .   .   .   .   .   .   .   .   .   .   .  IF  ID  EX  ME  WB   .
0x0030   jal     x0, 0                   |  .   .   .   .   .   .   .   .   .   .   .   .   .  IF  ID  EX  ME  WB
------------------------------------------------------------------------------------------------------------------------------
Legend: IF=Fetch | ID=Decode | ID*=Load-Use Stall | EX=Execute | ME=Memory | WB=Writeback | .=Inactive
==============================================================================================================================
                                            MICROARCHITECTURAL PERFORMANCE
==============================================================================================================================
  Total Simulated Cycles : 18       Retired Instructions : 12
  IPC (Instructions/Cyc) : 0.667    CPI (Cycles/Inst)    : 1.500
  Branch Stalls          : 5        Load-Use Stalls      : 1
  Flushes                : 0        Forwarding EX->EX    : 3
  Forwarding MEM->EX     : 3        Pipeline Efficiency  : 66.7%
==============================================================================================================================
```

#### Cycle-by-Cycle Hazard Mechanics Breakdown:
1. **Cycle 10 (Load-Use Stall on $x6$)**:
   - Instruction `lw x6, 0(x0)` is in `EX`, while `addi x7, x6, 5` enters `ID`.
   - Hazard unit freezes PC and IF/ID (`ID*`), inserting a bubble into `ID/EX`.
   - In Cycle 11, data is forwarded from `MEM/WB` to `EX`.
2. **Cycles 11–13 (Taken Branch Stall on `beq`)**:
   - `beq x1, x6, 8` enters `ID` in Cycle 11. Fetch is frozen (`pc_write = 0`).
   - In Cycle 12, `beq` evaluates in `EX` (Condition: $10 == 10$, TAKEN).
   - In Cycle 13, PC updates to resolved target `0x2c`.
   - Zero instructions from the skipped branch path (`0x0028 addi x8, x0, 99`) enter `ID` or `EX`.
3. **Cycles 14–16 (Self-Loop JAL Stall)**:
   - `jal x0, 0` enters `ID` in Cycle 15. Fetch is frozen.
   - Evaluates in `EX` in Cycle 16, redirecting PC back to `0x30`.
   - Simulation terminates cleanly after `jal` commits in `WB` at Cycle 18.

---

## 6. Repository Structure & File Organization

```text
riscv-ai-accelerator/
├── rtl/
│   ├── rv32i/                              # Microarchitecture 1: RV32I Single-Cycle Core
│   │   ├── rv32i_core.sv                   # Top single-cycle datapath
│   │   ├── alu.sv                          # 32-bit arithmetic logic unit
│   │   ├── control.sv                      # Combinational opcode decoder
│   │   ├── data_memory.sv                  # Byte/half/word Harvard data memory
│   │   ├── imm_gen.sv                      # Immediate extractor (I/S/B/U/J)
│   │   ├── instruction_memory.sv           # Harvard instruction memory
│   │   ├── pc.sv                           # Program counter logic
│   │   └── register_file.sv                # 32-word regfile (x0 hardwired to 0)
│   │
│   ├── rv32i_pipelined/                    # Microarchitecture 2: 5-Stage Speculative Core
│   │   ├── rv32i_pipeline_core.sv          # Pipelined top module
│   │   ├── hazard_unit.sv                  # Forwarding, load-use stall, branch flush
│   │   ├── pipeline_regs.sv                # IF/ID, ID/EX, EX/MEM, MEM/WB registers
│   │   ├── pc_pipeline.sv                  # PC register with freeze control
│   │   └── register_file_pipeline.sv       # Regfile with write-first bypass
│   │
│   └── rv32i_pipelined_stallbranch/        # Microarchitecture 3: 5-Stage Always-Stall Core
│       ├── rv32i_pipeline_stallbranch_core.sv # Top datapath with non-speculative branch stall
│       └── hazard_unit_stallbranch.sv      # Priority hazard arbitration unit
│
├── converting_into_NPU/                    # Neural Processing Unit (NPU) Coprocessor Workspace
│   ├── rtl/
│   │   ├── npu_top.sv                      # Memory-mapped NPU coprocessor with on-chip SRAMs & MAC
│   │   ├── rv32i_pipeline_stallbranch_core.sv # CPU core with MMIO bus interconnect at 0x8000_0000
│   │   └── ...                             # Full SystemVerilog CPU+NPU RTL datapath
│   ├── tb/
│   │   ├── tb_npu_top.sv                   # Standalone NPU hardware unit verification (8 corner cases)
│   │   ├── tb_pipeline_npu_core.sv         # Full-system CPU + NPU hardware-software co-simulation
│   │   └── tb_pipeline_npu_benchmark32.sv  # End-to-end 32x32 tiled GEMM benchmark (1024 words)
│   ├── tests/
│   │   ├── npu_driver.h                    # High-level C hardware driver for MMIO registers & SRAMs
│   │   ├── matmul_32_t2_s32_O2.c           # Real benchmark program for 32x32 matrix multiplication
│   │   ├── gen_npu_test_hex.py             # Assembler generating tb/instr_mem_npu.hex
│   │   └── gen_npu_benchmark32.py          # Assembler generating 32x32 benchmark program & datasets
│   ├── run_tests.sh                        # Automated 7/7 comprehensive regression test runner
│   └── TEST_RESULTS.md                     # Comprehensive cycle-accurate verification logs
│
├── tb/
│   ├── rv32i/                              # Single-cycle unit testbenches
│   │   ├── instr_mem_all_types.hex         # 12-instruction comprehensive verification program
│   │   ├── tb_singlecycle_trace.sv         # Negedge telemetry probe testbench
│   │   └── tb_rv32i_core.sv                # Basic functional regression
│   │
│   ├── rv32i_pipelined/                    # Speculative pipeline testbenches
│   │   ├── instr_mem_hazards.hex           # Dedicated hazard stress test program
│   │   ├── tb_pipeline_hazards.sv          # 11-case hazard test suite
│   │   └── tb_pipeline_trace.sv            # Speculative pipeline tracer
│   │
│   └── rv32i_pipelined_stallbranch/        # Always-stall pipeline testbenches
│       ├── instr_mem_stallbranch_demo.hex  # 18-cycle verified demo program
│       ├── tb_pipeline_stallbranch_trace.sv# Non-speculative telemetry probe (64K words)
│       └── tb_pipeline_stallbranch_hazards.sv # Hazard verification testbench
│
├── verification/
│   └── arch-test/                          # Official RISC-V Architectural Test Suite Harness
│       ├── run_singlecycle_suite.sh        # Single-cycle compliance runner (38/38 PASS)
│       ├── run_pipeline_suite.sh           # Speculative pipeline compliance runner (38/38 PASS)
│       ├── run_stallbranch_suite.sh        # Always-stall compliance runner (38/38 PASS)
│       ├── link.ld                         # Standard test harness linker script
│       ├── link_big.ld                     # Large-offset linker script for branches/jumps
│       └── hex_convert.py                  # Binary-to-hex word conversion utility
│
├── docs/                                   # Architectural Documentation
│   ├── PIPELINE.md                         # Detailed 5-stage speculative pipeline architecture
│   └── BRANCH_STALL.md                     # Always-stall microarchitecture & timing analysis
│
└── PROJECT_SUMMARY.md                      # This master reference document
```

---

## 7. Reproduction Commands & Verification Runbook

### 7.1 How to Test the CPU

The CPU cores are verified using official industry-standard compliance suites (`riscv-arch-test`) and targeted unit testbenches.

#### A. Official Architectural Compliance Suites (38/38 PASS)
Run the complete 38-test architectural compliance suites verified bit-for-bit against the Spike golden reference model:

```bash
# Core 1: 5-Stage Always-Stall Pipeline Core (38/38 PASS)
./verification/arch-test/run_stallbranch_suite.sh

# Core 2: 5-Stage Speculative Pipeline Core (38/38 PASS)
./verification/arch-test/run_pipeline_suite.sh

# Core 3: Single-Cycle Processor (38/38 PASS)
./verification/arch-test/run_singlecycle_suite.sh
```

#### B. Pipelined Core Unit & Hazard Regressions
Execute the self-checking unit testbenches to verify forwarding and hazard resolution:

```bash
# 1. Hazard Stress Regression on Always-Stall Core (11/11 PASS)
mkdir -p build && cp tb/rv32i_pipelined/instr_mem_hazards.hex build/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined_stallbranch/tb_pipeline_stallbranch_hazards.sv \
  rtl/rv32i_pipelined_stallbranch/*.sv rtl/rv32i_pipelined/alu.sv rtl/rv32i_pipelined/control.sv \
  rtl/rv32i_pipelined/imm_gen.sv rtl/rv32i_pipelined/instruction_memory.sv \
  rtl/rv32i_pipelined/data_memory.sv rtl/rv32i_pipelined/register_file_pipeline.sv \
  rtl/rv32i_pipelined/pipeline_regs.sv rtl/rv32i_pipelined/pc_pipeline.sv \
  --top-module tb_pipeline_stallbranch_hazards -Mdir build/obj_haz_sb
(cd build && ./obj_haz_sb/Vtb_pipeline_stallbranch_hazards)

# 2. Branch & JALR Stress Regression (19/19 PASS)
cp tb/rv32i/instr_mem_branch_jalr.hex build/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined_stallbranch/tb_pipeline_stallbranch_branch_jalr.sv \
  rtl/rv32i_pipelined_stallbranch/*.sv rtl/rv32i_pipelined/alu.sv rtl/rv32i_pipelined/control.sv \
  rtl/rv32i_pipelined/imm_gen.sv rtl/rv32i_pipelined/instruction_memory.sv \
  rtl/rv32i_pipelined/data_memory.sv rtl/rv32i_pipelined/register_file_pipeline.sv \
  rtl/rv32i_pipelined/pipeline_regs.sv rtl/rv32i_pipelined/pc_pipeline.sv \
  --top-module tb_pipeline_stallbranch_branch_jalr -Mdir build/obj_bj_sb
(cd build && ./obj_bj_sb/Vtb_pipeline_stallbranch_branch_jalr)

# 3. Always-Stall Behavior Check (zero wrong-path execution)
cp tb/rv32i_pipelined_stallbranch/instr_mem_stallbranch_demo.hex build/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined_stallbranch/tb_stall_behavior_check.sv rtl/rv32i_pipelined_stallbranch/*.sv \
  --top-module tb_stall_behavior_check -Mdir build/obj_stall_check
(cd build && ./obj_stall_check/Vtb_stall_behavior_check)
```

---

### 7.2 How to Test the NPU

The NPU accelerator is located in `converting_into_NPU/` and verified across unit tests, CPU co-simulation, and an end-to-end $32 \times 32$ matrix multiplication benchmark.

#### A. Run All NPU Tests in One Command
```bash
cd converting_into_NPU
chmod +x run_tests.sh
./run_tests.sh
```

**Output Summary**:
```
================================================================================
          ALL 7/7 CORE & NPU TESTS PASSED FOR converting_into_NPU               
================================================================================
  [1/7] Core Basic Functional Regression           --> PASS (0 errors)
  [2/7] Hazard Stress Regression (11 checks)       --> PASS (11/11 passed)
  [3/7] Branch & JALR Regression                   --> PASS (0 errors)
  [4/7] Pipeline Stall Behavior Check              --> PASS (0 errors)
  [5/7] Standalone NPU Hardware Unit Verification  --> PASS (8/8 corner cases)
  [6/7] Full-System CPU + NPU Co-Simulation        --> PASS (0 errors)
  [7/7] End-to-End 32x32 Tiled GEMM Benchmark      --> PASS (1024/1024 bit-exact)
================================================================================
```

#### B. Standalone NPU Unit Tests (`tb_npu_top.sv`)
Verifies the NPU compute datapath across 8 mathematical and control corner cases:
```bash
cd converting_into_NPU
verilator --binary --timing tb/tb_npu_top.sv rtl/npu_top.sv \
  --top-module tb_npu_top -Mdir build/obj_npu
./build/obj_npu/Vtb_npu_top
```

#### C. Full-System CPU + NPU Co-Simulation (`tb_pipeline_npu_core.sv`)
Verifies CPU memory-stage bus decoding at `0x8000_0000`, true non-blocking concurrent execution, and polling loop synchronization:
```bash
cd converting_into_NPU
python3 tests/gen_npu_test_hex.py
mkdir -p build/obj_system && cp tb/instr_mem_npu.hex build/obj_system/instr_mem.hex
verilator --binary --timing tb/tb_pipeline_npu_core.sv rtl/*.sv \
  --top-module tb_pipeline_npu_core -Mdir build/obj_system
(cd build/obj_system && ./Vtb_pipeline_npu_core)
```

#### D. End-to-End 32x32 Tiled GEMM Benchmark (`tb_pipeline_npu_benchmark32.sv`)
Executes an end-to-end $32 \times 32$ signed matrix multiplication benchmark using real test datasets from `matmul_32_t2_s32_O2.c`:
```bash
cd converting_into_NPU
python3 tests/gen_npu_benchmark32.py
mkdir -p build/obj_benchmark32
cp tb/instr_mem_benchmark32.hex build/obj_benchmark32/instr_mem.hex
cp tb/data_a.hex tb/data_b.hex tb/golden_c.hex build/obj_benchmark32/
verilator --binary --timing tb/tb_pipeline_npu_benchmark32.sv rtl/*.sv \
  --top-module tb_pipeline_npu_benchmark32 -Mdir build/obj_benchmark32
(cd build/obj_benchmark32 && ./Vtb_pipeline_npu_benchmark32)
```

---

## 8. Neural Processing Unit (NPU) Architecture & Hardware Acceleration

### 8.1 Memory-Mapped Architecture
The NPU coprocessor is integrated seamlessly into the 5-stage pipeline via Memory-Mapped I/O (MMIO) without requiring custom non-standard instructions. When the CPU performs standard `sw` or `lw` instructions with memory addresses $\ge \text{0x8000\_0000}$, the bus address decoder directs the request to the NPU:

| Address Offset | Register / Memory | Access | Description |
| :--- | :--- | :---: | :--- |
| `0x8000_0000` | `NPU_DIM_M` | R/W | Number of rows in Matrix A and Matrix C ($1 \le M \le 16$) |
| `0x8000_0004` | `NPU_DIM_K` | R/W | Shared inner dimension of Matrix A and Matrix B ($1 \le K \le 16$) |
| `0x8000_0008` | `NPU_DIM_N` | R/W | Number of columns in Matrix B and Matrix C ($1 \le N \le 16$) |
| `0x8000_000C` | `NPU_TRIGGER` | W | Writing `1` initiates hardware matrix multiplication |
| `0x8000_0010` | `NPU_RESET` | W | Writing `1` resets computation FSM, cycle count, and status flags |
| `0x8000_0014` | `NPU_CYCLES` | R | Cycle counter measuring computation time |
| `0x8000_0018` | `NPU_STATUS` | R | Bit 0: `done` flag, Bit 1: `busy` flag |
| `0x8000_1000` - `0x8000_13FC` | `MAT_A_SRAM` | R/W | 256-word dedicated on-chip buffer for tile Matrix A |
| `0x8000_2000` - `0x8000_23FC` | `MAT_B_SRAM` | R/W | 256-word dedicated on-chip buffer for tile Matrix B |
| `0x8000_3000` - `0x8000_33FC` | `MAT_C_SRAM` | R/W | 256-word dedicated on-chip buffer for tile Matrix C |

### 8.2 Performance Benchmark Results
Comparing full $32 \times 32$ tiled matrix multiplication execution ($32,768$ MAC operations):

| Kernel Execution Mode | Execution Cycles | Compute Description |
| :--- | :---: | :--- |
| **Pure Scalar Software (RV32I)** | **~1,550,000 cycles** | 3-nested loop C implementation with software-emulated multiplication (~45 cycles/inner loop) |
| **NPU Accelerator (MMIO Architecture)** | **186,433 cycles** | 8 hardware tile GEMMs @ 1 MAC/cycle + MMIO data streaming and block accumulation |
| **Full System Speedup** | **~8.3x Faster** | End-to-end wall-clock cycles including all loop overhead and memory transfers |
| **MAC Datapath Speedup** | **~45x Faster** | 32,768 hardware cycles vs ~1,470,000 software multiplication cycles |

---
*Document automatically maintained as part of the RISC-V AI Accelerator Project.*


