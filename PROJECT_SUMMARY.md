# RISC-V AI Accelerator: Complete Project Architecture, Implementation & Verification Summary

**Project Lead / Architect**: Advised under Prof. Ashwin  
**Repository**: `riscv-ai-accelerator`  
**Status**: Single-Cycle Core Verified | 5-Stage Speculative Pipeline Verified | 5-Stage Always-Stall Pipeline Verified | Interactive Dual-Core Telemetry Visualizer Operational  
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
5. [Interactive Telemetry & Visualization System](#5-interactive-telemetry--visualization-system)
   - [5.1 Telemetry Architecture & Cycle-Accurate Probing](#51-telemetry-architecture--cycle-accurate-probing)
   - [5.2 Python Telemetry Engine & Microarchitectural Profiler](#52-python-telemetry-engine--microarchitectural-profiler)
   - [5.3 Interactive Web Dashboard (`index.html`)](#53-interactive-web-dashboard-indexhtml)
   - [5.4 Dual-Core Visualizer Presentation](#54-dual-core-visualizer-presentation)
     - [Single-Cycle Datapath View](#single-cycle-datapath-view)
     - [5-Stage Always-Stall Pipeline View](#5-stage-always-stall-pipeline-view)
   - [5.5 Verified 18-Cycle Pipeline Execution Gantt Timeline](#55-verified-18-cycle-pipeline-execution-gantt-timeline)
6. [Repository Structure & File Organization](#6-repository-structure--file-organization)
7. [Reproduction Commands & Verification Runbook](#7-reproduction-commands--verification-runbook)
8. [Future Roadmap (Phase 2 & Phase 3)](#8-future-roadmap-phase-2--phase-3)

---

## 1. Project Overview & Architectural Roadmap

The **RISC-V AI Accelerator** project focuses on the clean-slate RTL design, hardware verification, and cycle-accurate performance analysis of high-efficiency RISC-V compute cores. The architecture is developed in SystemVerilog, targeting low-power embedded intelligence, machine learning edge acceleration, and high-throughput vector processing.

### Multi-Phase Engineering Trajectory
```
Phase 1: Scalar Foundations (COMPLETE)
  ├── 1. RV32I Single-Cycle Processor (rtl/rv32i/)
  ├── 2. RV32I 5-Stage Speculative Pipelined Core (rtl/rv32i_pipelined/)
  ├── 3. RV32I 5-Stage Always-Stall Pipelined Core (rtl/rv32i_pipelined_stallbranch/)
  └── 4. Cycle-Accurate Dual-Core Interactive Telemetry Visualizer (tools/visualizer/)

Phase 2: Vector & Matrix Extensions (UPCOMING)
  ├── RV32IV: RISC-V Vector extension integration (SIMD lanes, vector register file)
  └── RV32IVMatrix: Dedicated 2D systolic/tensor accelerator unit for GEMM/convolution

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

## 5. Interactive Telemetry & Modular Visualization System

Located in [`tools/visualizer/`](tools/visualizer/), this infrastructure provides real-time, cycle-by-cycle observability into both single-cycle and pipelined cores without modifying any core RTL files.

```
  +-------------------------------------------------------------------------+
  |                        Verilator RTL Simulation                         |
  |      (rv32i_core.sv  /  rv32i_pipeline_stallbranch_core.sv)             |
  +-------------------------------------------------------------------------+
                                       |
                                       | Cycle probes (IF, ID, EX, MEM, WB, Regs, Hazards)
                                       v
  +-------------------------------------------------------------------------+
  |                   Telemetry Testbenches (*_trace.sv)                    |
  |         Emits cycle snapshots at negedge clk to cycle_dump.json         |
  +-------------------------------------------------------------------------+
                                       |
                                       | Raw cycle records
                                       v
  +-------------------------------------------------------------------------+
  |               Python Telemetry Engine (trace_engine.py)                 |
  | - Full RV32I disassembly of instruction machine words                   |
  | - Hazard profiling (Load-use stalls, branch flushes, forwarding counts) |
  | - Performance metrics computation (IPC, CPI, Efficiency %)              |
  +-------------------------------------------------------------------------+
                    |                                       |
                    v                                       v
  +-----------------------------------+   +------------------------------------+
  |     Terminal ASCII Gantt View     |   |   Modular HTML5 / CSS3 / JS Engine |
  |  (Printed to stdout instantly)    |   |     (build_visualizer.py -> JS)    |
  | - Instruction-by-cycle grid       |   +------------------------------------+
  | - Stall (-S-) & Bubble (-B-) tags |                     |
  | - Summary performance card        |                     v
  +-----------------------------------+   +------------------------------------+
                                          | Standalone Browser UI (index.html) |
                                          | - style.css (Dark responsive theme)|
                                          | - pipeline_visualizer.js (Engine)  |
                                          | - trace_data.js (Telemetry dataset)|
                                          | - Interactive Gantt Chart          |
                                          | - Pipeline Registers Inspector     |
                                          | - Instruction Bitfield Decoder     |
                                          | - Explicit Stage Inputs & Outputs  |
                                          | - Live 32-Register Matrix (Pulse)  |
                                          +------------------------------------+
```

### 5.1 Telemetry Architecture & Cycle-Accurate Probing

- **Non-Intrusive RTL Probing**: Probes are instantiated in testbenches (`tb_singlecycle_trace.sv`, `tb_pipeline_stallbranch_trace.sv`) using hierarchical references and shadow pipeline registers to track instructions through `IF ➔ ID ➔ EX ➔ MEM ➔ WB`.
- **Negedge Sampling**: Telemetry is captured strictly at `negedge clk`:
  1. Synchronous state from the preceding `posedge clk` has stabilized.
  2. Combinational logic (ALU, hazard detection, forwarding multiplexers, memory reads) has settled.
  3. Cycle snapshot is serialized directly into `cycle_dump.json`.
- **64K Word Memory Capacity**: To support large official architectural tests (`link_big.ld` section offsets), memory depth in `tb_pipeline_stallbranch_trace.sv` is set to `parameter MEM_WORDS = 65536`.

---

### 5.2 Python Telemetry Engine & Microarchitectural Profiler

[`tools/visualizer/trace_engine.py`](tools/visualizer/trace_engine.py):
- **RV32I Machine Code Disassembler**: Complete decoding of all 32-bit RV32I opcodes, funct3, funct7, registers ($rs1, rs2, rd$), and sign-extended immediates.
- **Instance-Based Instruction Tracking**: Uniquely tracks instruction instances through their physical lifecycle (`IF -> ID -> EX -> MEM -> WB`), eliminating ghost bubble rows or address-bus latch artifacts.
- **Performance Accounting**:
  $$\text{IPC} = \frac{\text{Retired Instructions}}{\text{Total Cycles}}, \quad \text{CPI} = \frac{\text{Total Cycles}}{\text{Retired Instructions}}, \quad \text{Efficiency} = \frac{\text{Retired Instructions}}{\text{Total Cycles}} \times 100\%$$

---

### 5.3 Modular Web Dashboard Architecture

The frontend visualization system is completely modularized for maintainability, separation of concerns, and clean extension:

1. **`index.html`**: Clean, semantic HTML skeleton defining responsive CSS grid layouts for all telemetry cards, register matrix, pipeline stages, and Gantt charts without inline styling or inline JavaScript bloat.
2. **`style.css`**: Dedicated dark modern theme stylesheet featuring CSS custom properties, responsive flexbox/grid layouts, glowing hazard/forwarding status badges, and green pulse animations on register writeback.
3. **`pipeline_visualizer.js`**: Pure vanilla JavaScript visualizer engine providing:
   - **Interactive Playback Controller**: Play, pause, step forward/backward, speed controls ($0.5\times$ to $5\times$), cycle scrubber slider, and keyboard shortcuts.
   - **Interactive Gantt Chart**: Full cycle-by-cycle execution matrix tracking instruction flow through `IF`, `ID`, `EX`, `MEM`, and `WB`. Cells are color-coded per stage, show load-use stall tags (`ID*`), and display branch bubble markers (`-B-`). Clicking any cell immediately jumps the visualizer to that cycle.
   - **Pipeline Registers Inspector**: Detailed breakdown of latched signals inside `IF/ID`, `ID/EX`, `EX/MEM`, and `MEM/WB` at each clock cycle (valid bits, latched PC, instruction word, operand register indices, and latched control words).
   - **32-Bit Instruction Bitfield Decoder**: Comprehensive instruction dissection showing opcode, rd, rs1, rs2, funct3, funct7, sign-extended immediate (hex and dec), and instruction format classification (R-type, I-type, S-type, B-type, U-type, J-type).
   - **Explicit Stage Inputs & Outputs Inspector**: Real-time card displaying exact inputs consumed, outputs generated, ALU operations, multiplexer routing, and forwarding sources at each stage (`IF`, `ID`, `EX`, `MEM`, `WB`).
   - **Architectural Register Matrix**: 32-word register file with ABI names, live hexadecimal and signed decimal values, and pulse animations indicating active register updates at WB.
   - **Event-Indexed Navigation**: Jump buttons (`jumpToNextStall`, `jumpToNextForward`, `jumpToNextBranch`) that index telemetry events and allow 1-click navigation to hazards.
4. **`trace_data.js`**: JavaScript dataset generated by `build_visualizer.py` containing `window.PIPELINE_TRACE_DATA` and `window.SINGLECYCLE_TRACE_DATA`.
5. **`build_visualizer.py`**: Automated compilation script that ingests `pipeline_trace.json` and `trace_singlecycle.json` and emits `trace_data.js`.

---

### 5.4 Architectural Test Suite Visualizer Integration (`run_arch_visualizer.sh`)

[`tools/visualizer/run_arch_visualizer.sh`](tools/visualizer/run_arch_visualizer.sh) provides a one-click bridge between the official RISC-V architectural compliance suite and the interactive visualizer:

1. Takes any official compliance test name (e.g., `beq-01`, `add-01`, `bne-01`, `jal-01`).
2. Automatically selects the appropriate linker script (`link.ld` or `link_big.ld` for large branch offsets).
3. Compiles the assembly source using `riscv32-unknown-elf-gcc` and extracts `.text` via `riscv32-unknown-elf-objcopy`.
4. Converts the binary to hexadecimal word format using `hex_convert.py`.
5. Executes the simulation on `tb_pipeline_stallbranch_trace.sv` in Verilator.
6. Parses cycle telemetry with `trace_engine.py` and compiles the dataset via `build_visualizer.py`.
7. Instantly opens the visualizer or launches the local HTTP server.

---

### 5.5 Verified 18-Cycle Pipeline Execution Gantt Timeline

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
├── tools/
│   └── visualizer/                         # Cycle-Accurate Telemetry & Modular Visualizer Suite
│       ├── index.html                      # Semantic HTML5 dashboard skeleton
│       ├── style.css                       # Dedicated dark modern theme styling
│       ├── pipeline_visualizer.js          # Modular client-side visualization engine
│       ├── trace_data.js                   # Compiled execution trace dataset
│       ├── build_visualizer.py             # Trace dataset compiler & asset builder
│       ├── run_visualizer.sh               # One-click simulation and dashboard builder
│       ├── run_arch_visualizer.sh          # Arch-test compiler & visualizer runner
│       ├── trace_engine.py                 # Disassembler & ASCII Gantt chart generator
│       ├── pipeline_trace.json             # Pipelined execution trace
│       ├── trace_stallbranch.json          # Always-stall pipeline execution trace
│       └── trace_singlecycle.json          # Single-cycle execution trace
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
│   ├── BRANCH_STALL.md                     # Always-stall microarchitecture & timing analysis
│   └── VISUALIZER.md                       # Telemetry extraction & visualizer manual
│
└── PROJECT_SUMMARY.md                      # This master reference document
```

---

## 7. Complete Runbook: How to Run, Simulate & Open Everything

This section provides complete, copy-paste-ready commands to run every testbench, execute all architectural suites, and open the visualizer dashboard.

---

### 7.1 How to Open the Interactive Visualizer

You can open the visualizer either directly as a file (zero dependencies, works out of the box) or via a local web server:

#### Option A: Direct File Open (Easiest, No Server Needed)
Simply open the generated HTML file directly in your browser or from the command line:
- **Direct File Path**:
  ```text
  file:///home/enovo/riscv-ai-accelerator/tools/visualizer/index.html
  ```
- **From Terminal (Linux Desktop)**:
  ```bash
  xdg-open tools/visualizer/index.html
  # or
  google-chrome tools/visualizer/index.html
  # or
  firefox tools/visualizer/index.html
  ```

#### Option B: Local Web Server
If you prefer viewing over HTTP:
```bash
# Start the local server
./tools/visualizer/run_visualizer.sh --serve 8080
# Or using Python directly:
python3 -m http.server 8080 --directory tools/visualizer
```
Then navigate to:
```text
http://localhost:8080/index.html
```

#### How to Switch Between Cores in the Visualizer
At the top-right header of the web page, click the navigation tabs:
1. **Single-Cycle Core Tab**: Displays the 12-instruction all-types breakdown with 5-stage conceptual anatomy (inputs used, outputs produced, memory handling, register updates).
2. **5-Stage Pipelined (Always-Stall) Tab**: Displays the verified pipeline execution with live register matrix, glowing forwarding indicators, latched pipeline registers, stage inputs/outputs, instruction bitfield decoder, and the interactive Gantt chart.

#### Web Dashboard Keyboard Shortcuts
- `Space`: Play / Pause timeline playback
- `→` (Right Arrow): Step forward 1 cycle
- `←` (Left Arrow): Step backward 1 cycle
- `S`: Quick-jump to next hazard stall
- `B`: Quick-jump to next branch/jump event
- `F`: Quick-jump to next data forwarding event

---

### 7.2 How to Re-generate Visualizer Traces

To simulate and regenerate the visualizer dashboard with custom cycle counts or programs:

```bash
# 1. Regenerate Always-Stall Pipeline (Default demo, 18 cycles)
./tools/visualizer/run_visualizer.sh --core stallbranch --cycles 18

# 2. Regenerate Single-Cycle Core (12 instructions)
./tools/visualizer/run_visualizer.sh --core singlecycle --cycles 12

# 3. Regenerate Speculative Pipeline (30 cycles)
./tools/visualizer/run_visualizer.sh --core speculative --cycles 30
```

---

### 7.3 How to Visualize Official Architectural Compliance Tests

To compile any official RISC-V architectural compliance test (`.S`), simulate it on the always-stall core, and visualize its execution cycle-by-cycle:

```bash
# 1. Compile & visualize beq-01 (60 cycles)
./tools/visualizer/run_arch_visualizer.sh beq-01 60

# 2. Compile & visualize add-01 (40 cycles)
./tools/visualizer/run_arch_visualizer.sh add-01 40

# 3. Compile & visualize bne-01 (70 cycles) and launch HTTP server on port 8080
./tools/visualizer/run_arch_visualizer.sh bne-01 70 --serve 8080
```

---

### 7.4 How to Run Official Architectural Compliance Suites (`riscv-arch-test`)

Run the complete 38-test architectural compliance suites verified against the Spike golden model:

```bash
# Core 1: Single-Cycle Processor (38/38 PASS)
./verification/arch-test/run_singlecycle_suite.sh

# Core 2: 5-Stage Speculative Pipeline Core (38/38 PASS)
./verification/arch-test/run_pipeline_suite.sh

# Core 3: 5-Stage Always-Stall Pipeline Core (38/38 PASS)
./verification/arch-test/run_stallbranch_suite.sh
```

---

### 7.5 How to Run Unit Test Regressions

#### 1. Always-Stall Pipelined Core (`rtl/rv32i_pipelined_stallbranch/`)
```bash
# Hazard Stress Regression (11/11 PASS)
mkdir -p /tmp/haz_sb && cp tb/rv32i_pipelined/instr_mem_hazards.hex /tmp/haz_sb/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined_stallbranch/tb_pipeline_stallbranch_hazards.sv \
  rtl/rv32i_pipelined_stallbranch/*.sv rtl/rv32i_pipelined/alu.sv rtl/rv32i_pipelined/control.sv \
  rtl/rv32i_pipelined/imm_gen.sv rtl/rv32i_pipelined/instruction_memory.sv \
  rtl/rv32i_pipelined/data_memory.sv rtl/rv32i_pipelined/register_file_pipeline.sv \
  rtl/rv32i_pipelined/pipeline_regs.sv rtl/rv32i_pipelined/pc_pipeline.sv \
  --top-module tb_pipeline_stallbranch_hazards -Mdir /tmp/haz_sb/obj_dir
(cd /tmp/haz_sb && ./obj_dir/Vtb_pipeline_stallbranch_hazards)

# Branch & JALR Stress Regression (19/19 PASS)
mkdir -p /tmp/bj_sb && cp tb/rv32i/instr_mem_branch_jalr.hex /tmp/bj_sb/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined_stallbranch/tb_pipeline_stallbranch_branch_jalr.sv \
  rtl/rv32i_pipelined_stallbranch/*.sv rtl/rv32i_pipelined/alu.sv rtl/rv32i_pipelined/control.sv \
  rtl/rv32i_pipelined/imm_gen.sv rtl/rv32i_pipelined/instruction_memory.sv \
  rtl/rv32i_pipelined/data_memory.sv rtl/rv32i_pipelined/register_file_pipeline.sv \
  rtl/rv32i_pipelined/pipeline_regs.sv rtl/rv32i_pipelined/pc_pipeline.sv \
  --top-module tb_pipeline_stallbranch_branch_jalr -Mdir /tmp/bj_sb/obj_dir
(cd /tmp/bj_sb && ./obj_dir/Vtb_pipeline_stallbranch_branch_jalr)

# Core Basic Regression (7/7 PASS)
verilator --binary --timing tb/rv32i_pipelined_stallbranch/tb_pipeline_stallbranch_core.sv \
  rtl/rv32i_pipelined_stallbranch/*.sv rtl/rv32i_pipelined/alu.sv rtl/rv32i_pipelined/control.sv \
  rtl/rv32i_pipelined/imm_gen.sv rtl/rv32i_pipelined/instruction_memory.sv \
  rtl/rv32i_pipelined/data_memory.sv rtl/rv32i_pipelined/register_file_pipeline.sv \
  rtl/rv32i_pipelined/pipeline_regs.sv rtl/rv32i_pipelined/pc_pipeline.sv \
  --top-module tb_pipeline_stallbranch_core -Mdir /tmp/core_sb/obj_dir
/tmp/core_sb/obj_dir/Vtb_pipeline_stallbranch_core
```

#### 2. Speculative Pipelined Core (`rtl/rv32i_pipelined/`)
```bash
# Hazard Stress Regression (11/11 PASS)
mkdir -p /tmp/haz_pipe && cp tb/rv32i_pipelined/instr_mem_hazards.hex /tmp/haz_pipe/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_hazards.sv rtl/rv32i_pipelined/*.sv \
  --top-module tb_pipeline_hazards -Mdir /tmp/haz_pipe/obj_dir
(cd /tmp/haz_pipe && ./obj_dir/Vtb_pipeline_hazards)

# Branch & JALR Regression (19/19 PASS)
mkdir -p /tmp/bj_pipe && cp tb/rv32i/instr_mem_branch_jalr.hex /tmp/bj_pipe/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_branch_jalr.sv rtl/rv32i_pipelined/*.sv \
  --top-module tb_pipeline_branch_jalr -Mdir /tmp/bj_pipe/obj_dir
(cd /tmp/bj_pipe && ./obj_dir/Vtb_pipeline_branch_jalr)

# Core Regression (7/7 PASS)
verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_core.sv rtl/rv32i_pipelined/*.sv \
  --top-module tb_pipeline_core -Mdir /tmp/obj_pipe_core && /tmp/obj_pipe_core/Vtb_pipeline_core
```

#### 3. Single-Cycle Core (`rtl/rv32i/`)
```bash
# Branch & JALR Tests
mkdir -p /tmp/sc_bj && cp tb/rv32i/instr_mem_branch_jalr.hex /tmp/sc_bj/instr_mem.hex
verilator --binary --timing tb/rv32i/tb_branch_jalr.sv rtl/rv32i/*.sv \
  --top-module tb_branch_jalr -Mdir /tmp/sc_bj/obj_dir
(cd /tmp/sc_bj && ./obj_dir/Vtb_branch_jalr)

# SLTU & Byte Memory Alignment
verilator --binary --timing tb/rv32i/tb_sltu_bytemem.sv rtl/rv32i/*.sv \
  --top-module tb_sltu_bytemem -Mdir /tmp/sc_sltu/obj_dir
/tmp/sc_sltu/obj_dir/Vtb_sltu_bytemem

# Register File Tests
verilator --binary --timing tb/rv32i/tb_register_file.sv rtl/rv32i/*.sv \
  --top-module tb_register_file -Mdir /tmp/sc_rf/obj_dir
/tmp/sc_rf/obj_dir/Vtb_register_file

# AUIPC Tests
verilator --binary --timing tb/rv32i/tb_auipc.sv rtl/rv32i/*.sv \
  --top-module tb_auipc -Mdir /tmp/sc_auipc/obj_dir
/tmp/sc_auipc/obj_dir/Vtb_auipc

# LUI & JAL Tests
verilator --binary --timing tb/rv32i/tb_lui_jal.sv rtl/rv32i/*.sv \
  --top-module tb_lui_jal -Mdir /tmp/sc_luijal/obj_dir
/tmp/sc_luijal/obj_dir/Vtb_lui_jal
```

---

## 8. Future Roadmap & Replicated NPU Accelerator Extension

With all three scalar cores fully verified against the official RISC-V architectural compliance suite, the project is moving towards specialized hardware acceleration:

### 8.1 Replicated NPU Hardware Accelerator (`RISCV_CPU`)

As part of the cross-repository architectural exploration, the latest additions from [`https://github.com/vroopaaa/RISCV_CPU`](https://github.com/vroopaaa/RISCV_CPU) (commit [`44b0644`](https://github.com/vroopaaa/RISCV_CPU/commit/44b0644)) have been replicated and verified in `/home/enovo/RISCV_CPU`:

- **16x16 NPU Systolic Array Architecture**: Implements a dedicated Neural Processing Unit coprocessor capable of tile-based matrix multiply-accumulate (MAC) execution.
- **Custom-0 Extension Instruction (`0x0B`)**: Extends the RISC-V ISA with a dedicated opcode for initiating multi-word strided tile loads/stores and matrix compute directly from software.
- **Strided Memory Subsystem**: Enhanced memory model supporting row/column stride access for 2D matrix tiles.
- **Matrix Multiplication Verification**:
  - `npu_matmul_test.c`: 16x16 matrix multiplication ($256$ elements) verified **PASS** with zero numerical errors.
  - `npu_matmul_256by256.c`: 32x32 tiled matrix multiplication ($1024$ elements across four 16x16 tiles) verified **PASS**.
  - Software harness in `tests/npu/run_npu_tests.py` automated using `riscv32-unknown-elf-gcc`.

### 8.2 Memory-Mapped NPU Accelerator Integration Roadmap

The dedicated conversion workspace [`converting_into_NPU/`](converting_into_NPU/) (symlinked as `converting into NPU`) contains the complete engineering roadmap in [**`converting_into_NPU/ROADMAP.md`**](converting_into_NPU/ROADMAP.md):

1. **Phase 1: MEM Stage Bus Interconnect**:
   - Address decoder in `rv32i_pipeline_stallbranch_core.sv` splits addresses at `0x8000_0000`.
   - Normal addresses (`< 0x8000_0000`) route to main RAM (`data_memory.sv`).
   - Accelerator addresses (`>= 0x8000_0000`) route to `npu_top.sv`.
2. **Phase 2: NPU Module & On-Chip SRAMs (`npu_top.sv`)**:
   - Dimension registers ($M, K, N$ at `0x8000_0000`–`0x08`), `NPU_TRIGGER` (`0x0C`), `NPU_STATUS` (`0x18`).
   - Three on-chip $256 \times 32$-bit SRAM buffers (`mat_a_sram`, `mat_b_sram`, `mat_c_sram`).
3. **Phase 3: Hardware Matrix Multiplication Engine**:
   - Compute FSM (`STATE_IDLE`, `STATE_CALC`, `STATE_DONE`) with 32-bit MAC pipeline.
   - Upgradable to a parallel $16 \times 16$ 2D systolic array behind the identical MMIO interface.
4. **Phase 4: C Software Driver (`npu_driver.h`)**:
   - Clean C API for tile streaming, triggering, and hardware polling (`while (!(*NPU_STATUS & 1));`).
5. **Phase 5: Hardware-Software Co-Simulation**:
   - Bit-exact verification against software golden matrix loops and re-verification of the 38/38 architectural suite.

---
*Document automatically maintained as part of the RISC-V AI Accelerator Project.*


