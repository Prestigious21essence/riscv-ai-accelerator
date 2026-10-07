# 5-Stage Pipelined RV32I Core Architecture & Hazard Resolution

This document details the architectural design, hazard resolution mechanisms, pipeline stages, and verification methodology for the 5-stage pipelined RV32I processor located in [`rtl/rv32i_pipelined/`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/).

The pipelined core achieves **100% compliance (38/38 tests passing, 0 differences)** against the official RISC-V architectural test suite (`riscv-arch-test`) verified bit-for-bit against the golden reference simulator (`spike`).

---

## 1. High-Level Architecture Overview

The core implements a classical Harvard-architecture 5-stage pipeline:
1. **IF (Instruction Fetch)**: Fetch 32-bit instruction from IMEM at current PC; compute next PC.
2. **ID (Instruction Decode & Register Read)**: Decode opcode/funct3/funct7, read register file with write-first forwarding, generate immediate.
3. **EX (Execute & Address Calculation)**: Execute ALU operations, evaluate branch conditions, compute jump/branch target addresses, forward data from EX/MEM and MEM/WB.
4. **MEM (Memory Access)**: Read or write data memory with byte/halfword/word alignment and sign/zero extension.
5. **WB (Writeback)**: Select final result (ALU result, memory read data, or link address `PC+4`) and write back to register file.

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

---

## 2. Pipeline Stages in Detail

### Stage 1: IF (Instruction Fetch)
- **Program Counter (`pc_pipeline.sv`)**: Holds the current 32-bit instruction fetch address.
  - Enabled by `pc_write`: When `pc_write = 1`, PC advances; when `pc_write = 0` (load-use hazard), PC freezes.
  - Target multiplexer:
    $$\text{next\_pc} = \begin{cases} \text{ex\_target\_pc} & \text{if } \text{ex\_redirect} = 1 \\ \text{if\_pc} + 4 & \text{otherwise} \end{cases}$$
- **Instruction Memory (`instruction_memory.sv`)**: Combinational read of 32-bit instruction word addressed by `if_pc[IDX_HI:2]`.

### Stage 2: ID (Instruction Decode & Register Read)
- **Control Unit (`control.sv`)**: Combinational decoder generating control signals:
  - `reg_write`, `mem_read`, `mem_write`, `mem_to_reg`, `alu_src`, `alu_op`, `branch`, `lui`, `jal`, `jalr`, `auipc`.
- **Immediate Generator (`imm_gen.sv`)**: Decodes sign-extended immediates for I-type, S-type, B-type, U-type, and J-type instructions.
- **Register File (`register_file_pipeline.sv`)**: 32 general-purpose 32-bit registers ($x0$ hardwired to 0).
  - Includes **internal write-to-read forwarding** to eliminate WB-to-ID hazards (see Section 3.4).
- **Source Register Tracking**: Combinational signals `id_uses_rs1` and `id_uses_rs2` identify whether the decoded instruction actually reads `rs1` and `rs2`.

### Stage 3: EX (Execute, ALU, Branch & Jump Resolution)
- **Forwarding Multiplexers**: Select between ID/EX register data, EX/MEM forwarded data, and MEM/WB writeback data for both ALU inputs.
- **ALU (`alu.sv`)**:
  - Operand A Mux: Supports `0` (for LUI), `ex_pc` (for AUIPC), or forwarded $rs1$.
  - Operand B Mux: Supports immediate (for I/S/U/J types) or forwarded $rs2$ (for R/B types).
  - Operations: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT (signed), SLTU (unsigned).
- **Branch Evaluation**:
  - Evaluates `funct3` with ALU zero flag and comparison results:
    - `BEQ`: `ex_zero`
    - `BNE`: `~ex_zero`
    - `BLT`: `ex_alu_result[0]` (signed SLT)
    - `BGE`: `~ex_alu_result[0]`
    - `BLTU`: `ex_alu_result[0]` (unsigned SLTU)
    - `BGEU`: `~ex_alu_result[0]`
- **Target PC Generation**:
  - Branches / JAL: `ex_pc + ex_imm`
  - JALR: `(forwarded_a + ex_imm) & ~1`
  - Link address for JAL/JALR: `ex_pc + 4`
- **Control Redirect**: Signal `ex_redirect` asserts if any branch is taken, or if instruction is JAL/JALR.

### Stage 4: MEM (Data Memory Access)
- **Data Memory (`data_memory.sv`)**:
  - Address: `ex_mem_alu_result`
  - Write data: forwarded store data `ex_mem_write_data` (with WB-to-MEM store forwarding bypass)
  - Funct3 width control:
    - Byte: `LB` (sign-extended), `LBU` (zero-extended), `SB` (byte write mask)
    - Halfword: `LH` (sign-extended), `LHU` (zero-extended), `SH` (halfword write mask)
    - Word: `LW`, `SW` (full word write)

### Stage 5: WB (Writeback)
- **Writeback Multiplexer**:
  $$\text{wb\_write\_data} = \begin{cases} \text{wb\_link\_addr} & \text{if } \text{wb\_jal} \lor \text{wb\_jalr} \\ \text{wb\_read\_data} & \text{if } \text{wb\_mem\_to\_reg} \\ \text{wb\_alu\_result} & \text{otherwise} \end{cases}$$
- Written synchronously to register file at `posedge clk` if `wb_reg_write` is asserted and `wb_rd != 0`.

---

## 3. Hazard Resolution Mechanisms

### 3.1 RAW Data Hazards & Forwarding Unit
Read-After-Write (RAW) data hazards occur when an instruction needs the result of a preceding instruction before it has reached the WB stage.

The **Hazard Unit (`hazard_unit.sv`)** detects these dependencies and forwards operands directly to the ALU inputs in EX:

```
Cycle       1      2      3      4      5      6
Inst 1:   [IF]   [ID]   [EX]   [MEM]  [WB]
Inst 2:          [IF]   [ID]   [EX]   [MEM]  [WB]
                          ^      |
                          +------+  (EX-to-EX Forwarding: distance = 1)
Inst 3:                 [IF]   [ID]   [EX]   [MEM]  [WB]
                                 ^             |
                                 +-------------+  (MEM-to-EX Forwarding: distance = 2)
```

#### Forwarding Rules
1. **EX Hazard (Priority 1 — Most Recent)**:
   ```systemverilog
   if (ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1))
       forward_a = 2'b10; // Forward ex_mem_forward_data
   ```
2. **MEM Hazard (Priority 2)**:
   ```systemverilog
   else if (mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1))
       forward_a = 2'b01; // Forward wb_write_data
   ```
   *(Identical logic applies to Operand B / Store data with `id_ex_rs2`)*.

3. **Store Data Forwarding**:
   When a store instruction (`sw`, `sh`, `sb`) in EX depends on a prior ALU or load result, `forward_b` routes the forwarded operand into `ex_write_data`. An additional bypass in the MEM stage (`(wb_reg_write && wb_rd == ex_mem_rs2) ? wb_write_data : ex_mem_write_data`) allows back-to-back load-to-store operations to execute cleanly with only a single stall.

---

### 3.2 Load-Use Hazard & 1-Cycle Stall Unit
A load instruction does not produce valid read data until the end of its MEM stage. Therefore, an instruction immediately following a load that depends on the loaded register **cannot** be resolved by forwarding alone:

```
Without stall:
lw  x1, 0(x2)   [IF]   [ID]   [EX]   [MEM: Data ready here]   [WB]
add x3, x1, x4         [IF]   [ID]   [EX: Needs data here!]  <--- HAZARD!
```

#### Hardware Stall Implementation
When the hazard unit detects:
```systemverilog
assign load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                         ((id_uses_rs1 && (id_rs1 == id_ex_rd)) ||
                          (id_uses_rs2 && (id_rs2 == id_ex_rd)));
```
The pipeline automatically intervenes for exactly **1 cycle**:
1. `pc_write = 1'b0`: PC register is frozen (same instruction fetched again).
2. `if_id_write = 1'b0`: IF/ID pipeline register is frozen (dependent instruction held in ID).
3. `flush_id_ex = 1'b1`: A bubble (NOP: all control signals 0) is injected into ID/EX.

```
With 1-cycle stall:
lw  x1, 0(x2)   [IF]   [ID]   [EX]   [MEM]   [WB]
add x3, x1, x4         [IF]   [ID]   [STALL] [EX]   [MEM]   [WB]
                                        ^      |
                                        +------+ Forwarded from WB!
```
In the subsequent cycle, the load has reached WB, and the MEM-to-EX forwarding path delivers the data directly to the ALU without any further delay.

---

### 3.3 Control Hazards & 2-Cycle Branch/Jump Flush
Branch and jump instructions change the instruction execution flow. In this architecture, all branch conditions and target addresses (including JALR register indirect targets) are resolved in the **EX stage**.

- **Default Prediction**: Predict Not-Taken (sequential fetch `PC + 4`).
- **Branch Not-Taken**: 0-cycle penalty. The sequential instructions in IF and ID continue seamlessly.
- **Branch Taken / JAL / JALR**:
  - `ex_redirect` asserts.
  - Next PC multiplexer selects `ex_target_pc`.
  - The speculatively fetched instructions in IF and ID are on the incorrect branch path and are flushed:
    - `flush_if_id = 1'b1` (clears IF/ID to `addi x0, x0, 0` NOP)
    - `flush_id_ex = 1'b1` (clears ID/EX to NOP bubble)
  - **Penalty**: Exactly 2 bubble cycles for taken branches, JAL, and JALR.

```
beq x1, x2, target  [IF]   [ID]   [EX: Taken!] [MEM]   [WB]
(speculative 1)            [IF]   [ID: FLUSH]  [NOP]
(speculative 2)                   [IF: FLUSH]  [NOP]
target inst                              [IF]  [ID]   [EX]   [MEM]   [WB]
```

#### Priority Handling
If an older branch/jump in EX resolves as taken in the same cycle that a younger instruction in ID signals a load-use stall, **the branch redirect takes absolute priority**:
```systemverilog
if (ex_redirect) begin
    pc_write    = 1'b1; // Redirect PC immediately
    if_id_write = 1'b1;
    flush_if_id = 1'b1; // Flush speculatively fetched instructions
    flush_id_ex = 1'b1;
end else if (load_use_hazard) begin
    pc_write    = 1'b0; // Freeze for 1 cycle
    if_id_write = 1'b0;
    flush_if_id = 1'b0;
    flush_id_ex = 1'b1; // Insert bubble into EX
end
```

---

### 3.4 Register File Write-Through (WB-to-ID Hazard)
When instruction $i$ in WB writes to register $x_k$ at the clock positive edge, and instruction $i+2$ in ID reads register $x_k$ in the same clock cycle:
- Standard registers write on `posedge clk` and read combinationally. Without bypass, ID would observe the stale register value from the previous cycle.
- **Solution (`register_file_pipeline.sv`)**: Internal write-first bypass:
  ```systemverilog
  assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 :
                    (we && (rd_addr == rs1_addr)) ? rd_data : regs[rs1_addr];
  assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 :
                    (we && (rd_addr == rs2_addr)) ? rd_data : regs[rs2_addr];
  ```
This completely eliminates WB-to-ID hazards without requiring external pipeline control.

---

### 3.5 Always-Stall on Branch Variant (`rtl/rv32i_pipelined_stallbranch/`)
In addition to the speculative (predict-not-taken) design described above, a fully non-speculative **Always-Stall on Branch** core is provided in [`rtl/rv32i_pipelined_stallbranch/`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined_stallbranch/):
- Freezes instruction fetch (`pc_write = 0`) whenever a branch or jump is in ID until it resolves in EX.
- Evaluates the target or fallthrough address in EX and dispatches it to the PC.
- Eliminates speculative execution entirely (zero wrong-path instructions enter the datapath).
- Passes all **38/38** architectural tests.
- See [`docs/BRANCH_STALL.md`](BRANCH_STALL.md) for full cycle-by-cycle diagrams and comparison.

---

## 4. Source Files & Structure

| File | Path | Description |
|---|---|---|
| **Top Core** | [`rtl/rv32i_pipelined/rv32i_pipeline_core.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/rv32i_pipeline_core.sv) | 5-stage pipelined datapath connecting IF, ID, EX, MEM, WB, and hazard unit. |
| **Hazard Unit** | [`rtl/rv32i_pipelined/hazard_unit.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/hazard_unit.sv) | Forwarding logic, load-use stall generation, branch flush control. |
| **Pipeline Regs** | [`rtl/rv32i_pipelined/pipeline_regs.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/pipeline_regs.sv) | Definitions of `if_id_reg`, `id_ex_reg`, `ex_mem_reg`, `mem_wb_reg`. |
| **Program Counter** | [`rtl/rv32i_pipelined/pc_pipeline.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/pc_pipeline.sv) | PC register with freeze/stall capability (`pc_write`). |
| **Register File** | [`rtl/rv32i_pipelined/register_file_pipeline.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/register_file_pipeline.sv) | 32-word regfile with internal write-to-read forwarding. |
| **ALU** | [`rtl/rv32i_pipelined/alu.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/alu.sv) | 32-bit arithmetic, logic, shift, and compare unit. |
| **Control Unit** | [`rtl/rv32i_pipelined/control.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/control.sv) | RV32I opcode decoder. |
| **Immediate Gen** | [`rtl/rv32i_pipelined/imm_gen.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/imm_gen.sv) | Immediate extractor for all instruction formats. |
| **Instruction Mem** | [`rtl/rv32i_pipelined/instruction_memory.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/instruction_memory.sv) | Harvard instruction memory. |
| **Data Memory** | [`rtl/rv32i_pipelined/data_memory.sv`](file:///home/enovo/riscv-ai-accelerator/rtl/rv32i_pipelined/data_memory.sv) | Harvard byte-accessible data memory. |

---

## 5. Verification & Test Suite

### 5.1 Unit Tests (Verilator in Sandbox)
1. **Core Regression (`tb_pipeline_core.sv`)**:
   ```bash
   verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_core.sv rtl/rv32i_pipelined/*.sv \
     --top-module tb_pipeline_core -Mdir /tmp/obj_pipe_core && /tmp/obj_pipe_core/Vtb_pipeline_core
   ```
   **Result**: `ALL 5-STAGE PIPELINE CORE TESTS PASSED` (7/7 checks).

2. **Branch & JALR Regression (`tb_pipeline_branch_jalr.sv`)**:
   ```bash
   mkdir -p /tmp/bj_pipe && cp tb/rv32i/instr_mem_branch_jalr.hex /tmp/bj_pipe/instr_mem.hex
   verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_branch_jalr.sv rtl/rv32i_pipelined/*.sv \
     --top-module tb_pipeline_branch_jalr -Mdir /tmp/bj_pipe/obj_dir
   (cd /tmp/bj_pipe && ./obj_dir/Vtb_pipeline_branch_jalr)
   ```
   **Result**: `ALL 5-STAGE PIPELINE BRANCH/JALR TESTS PASSED` (19/19 checks, 0 leaked instructions).

3. **Hazard Stress Test (`tb_pipeline_hazards.sv`)**:
   ```bash
   mkdir -p /tmp/haz_pipe && cp tb/rv32i_pipelined/instr_mem_hazards.hex /tmp/haz_pipe/instr_mem.hex
   verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_hazards.sv rtl/rv32i_pipelined/*.sv \
     --top-module tb_pipeline_hazards -Mdir /tmp/haz_pipe/obj_dir
   (cd /tmp/haz_pipe && ./obj_dir/Vtb_pipeline_hazards)
   ```
   **Result**: `ALL PIPELINE HAZARD TESTS PASSED (11/11)`:
   - EX-to-EX forwarding on `rs1` and `rs2`
   - MEM-to-EX forwarding on `rs1` and `rs2`
   - Load-use stall (1 cycle) followed by forwarding
   - Store data forwarding
   - Register file write-through (WB-to-ID simultaneous write/read)

---

### 5.2 Full Architectural Compliance Suite (`riscv-arch-test`)
The full compliance sweep compares the pipelined core's memory signature bit-for-bit against Spike golden reference for every RV32I instruction:

```bash
PATH="/home/enovo/tools/riscv32-gnu-toolchain/bin:$PATH" \
ARCH_TEST_ROOT=/home/enovo/riscv-arch-test \
SPIKE_BIN=/home/enovo/riscv-isa-sim/build/spike \
./verification/arch-test/run_pipeline_suite.sh
```

**Result: 38/38 Passed (0 Failed)**
```text
add-01:      PASS (590 words, 0 differences)
addi-01:     PASS (563 words, 0 differences)
and-01:      PASS (586 words, 0 differences)
andi-01:     PASS (564 words, 0 differences)
auipc-01:    PASS (66 words, 0 differences)
beq-01:      PASS (585 words, 0 differences)
bge-01:      PASS (592 words, 0 differences)
bgeu-01:     PASS (728 words, 0 differences)
blt-01:      PASS (582 words, 0 differences)
bltu-01:     PASS (728 words, 0 differences)
bne-01:      PASS (586 words, 0 differences)
fence-01:    PASS (3 words, 0 differences)
jal-01:      PASS (34 words, 0 differences)
jalr-01:     PASS (35 words, 0 differences)
lb-align-01: PASS (35 words, 0 differences)
lbu-align-01:PASS (34 words, 0 differences)
lh-align-01: PASS (34 words, 0 differences)
lhu-align-01:PASS (34 words, 0 differences)
lui-01:      PASS (65 words, 0 differences)
lw-align-01: PASS (34 words, 0 differences)
or-01:       PASS (589 words, 0 differences)
ori-01:      PASS (411 words, 0 differences)
sb-align-01: PASS (72 words, 0 differences)
sh-align-01: PASS (73 words, 0 differences)
sll-01:      PASS (91 words, 0 differences)
slli-01:     PASS (90 words, 0 differences)
slt-01:      PASS (586 words, 0 differences)
slti-01:     PASS (562 words, 0 differences)
sltiu-01:    PASS (701 words, 0 differences)
sltu-01:     PASS (724 words, 0 differences)
sra-01:      PASS (92 words, 0 differences)
srai-01:     PASS (89 words, 0 differences)
srl-01:      PASS (94 words, 0 differences)
srli-01:     PASS (92 words, 0 differences)
sub-01:      PASS (594 words, 0 differences)
sw-align-01: PASS (70 words, 0 differences)
xor-01:      PASS (590 words, 0 differences)
xori-01:     PASS (568 words, 0 differences)

=== 38 passed, 0 failed (of 38 total) ===
```

