# RISC-V AI Accelerator RTL

RISC-V RTL implementation exploring pipelined cores and dedicated neural processing hardware accelerators, developed under Prof. Ashwin.

---

## 1. Architecture Overview

- **RV32I Base Scalar Cores**:
  - **Single-Cycle Core** (`rtl/rv32i/`): Fully verified RV32I base integer implementation.
  - **5-Stage Pipelined Core (Speculative)** (`rtl/rv32i_pipelined/`): Classic 5-stage pipeline (IF, ID, EX, MEM, WB) with predict-not-taken branch prediction, full forwarding (EX-to-EX, MEM-to-EX), 1-cycle load-use hazard stalling, and write-through register file.
  - **5-Stage Pipelined Core (Always-Stall on Branch)** (`rtl/rv32i_pipelined_stallbranch/`): Non-speculative branch resolution that freezes instruction fetch when a branch/jump enters ID until resolved in EX, guaranteeing zero wrong-path instruction execution.
- **Neural Processing Unit (NPU) Coprocessor** (`converting_into_NPU/`):
  - Memory-Mapped I/O (MMIO) coprocessor mapped at physical address `0x8000_0000`.
  - On-chip dedicated SRAM buffers: Matrix A ($256 \times 32$-bit), Matrix B ($256 \times 32$-bit), Matrix C ($256 \times 32$-bit).
  - 32-bit iterative Multiply-Accumulate (MAC) datapath operating at 1 MAC/clock cycle.
  - Block-tiled matrix multiplication supporting arbitrary matrix dimensions ($16 \times 16$, $32 \times 32$, $64 \times 64$, etc.).
  - 100% standard unprivileged RV32I ISA compliance (zero custom opcodes required).

---

## 2. How to Test the CPU

The CPU cores are verified using both official industry-standard compliance suites and targeted hazard/branch unit testbenches.

### 2.1 Official RISC-V Architectural Compliance (38/38 PASS)
Run the complete official `riscv-arch-test` suite for unprivileged RV32I instructions (verifies bit-for-bit equivalence against the Spike golden ISS reference):

```bash
# Verify the Always-Stall Pipelined Core (38/38 PASS)
./verification/arch-test/run_stallbranch_suite.sh

# Verify the Speculative Pipelined Core (38/38 PASS)
./verification/arch-test/run_pipeline_suite.sh
```

### 2.2 Pipelined Core Unit & Hazard Regressions
Run the Verilator self-checking unit testbenches to verify forwarding and hazard handling:

```bash
# 1. Pipelined Core Basic Functional Test
verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_core.sv rtl/rv32i_pipelined/*.sv \
  --top-module tb_pipeline_core -Mdir build/obj_pipe_core
./build/obj_pipe_core/Vtb_pipeline_core

# 2. Hazard & Forwarding Stress Test (EX-to-EX, MEM-to-EX, 1-cycle load-use stalls)
mkdir -p build && cp tb/rv32i_pipelined/instr_mem_hazards.hex build/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_hazards.sv rtl/rv32i_pipelined/*.sv \
  --top-module tb_pipeline_hazards -Mdir build/obj_pipe_hazards
(cd build && ./obj_pipe_hazards/Vtb_pipeline_hazards)

# 3. Branch & JALR Stress Test (all 6 branch conditions + JAL/JALR links)
cp tb/rv32i_pipelined/instr_mem_branch_jalr.hex build/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined/tb_pipeline_branch_jalr.sv rtl/rv32i_pipelined/*.sv \
  --top-module tb_pipeline_branch_jalr -Mdir build/obj_pipe_branch
(cd build && ./obj_pipe_branch/Vtb_pipeline_branch_jalr)

# 4. Cycle-Accurate Branch Stall Verification (confirms zero wrong-path execution)
cp tb/rv32i_pipelined_stallbranch/instr_mem_stallbranch_demo.hex build/instr_mem.hex
verilator --binary --timing tb/rv32i_pipelined_stallbranch/tb_stall_behavior_check.sv rtl/rv32i_pipelined_stallbranch/*.sv \
  --top-module tb_stall_behavior_check -Mdir build/obj_stall_check
(cd build && ./obj_stall_check/Vtb_stall_behavior_check)
```

---

## 3. How to Test the NPU

The NPU accelerator is located in `converting_into_NPU/` and is verified across standalone hardware unit tests, CPU+NPU co-simulation, and an end-to-end $32 \times 32$ matrix multiplication benchmark.

### 3.1 Run All NPU Tests in One Command
To execute the complete 7-stage regression suite:

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

---

### 3.2 Individual NPU Test Suites

#### A. Standalone NPU Unit Tests (`tb_npu_top.sv`)
Verifies the NPU compute engine across 8 mathematical and control corner cases:
- Dimension and control register R/W (`DIM_M`, `DIM_K`, `DIM_N`)
- $4 \times 4$ Identity GEMM ($C = A \times I = A$) in 64 cycles
- Full $16 \times 16$ signed GEMM stress test (4,096 MACs in 4,096 cycles)
- All-Zeroes GEMM with active dirty memory overwrite
- Dimension sweeps: $1 \times 1 \times 1$ scalar, $1 \times 16 \times 1$ vector dot-product, $3 \times 7 \times 5$ asymmetric matrix
- Hardware reset semantics (`NPU_RESET`, status and cycle count reset)
- Signed 32-bit two's complement arithmetic wrap-around
- Back-to-back GEMM runs without reset

```bash
cd converting_into_NPU
verilator --binary --timing tb/tb_npu_top.sv rtl/npu_top.sv \
  --top-module tb_npu_top -Mdir build/obj_npu
./build/obj_npu/Vtb_npu_top
```

#### B. Full-System CPU + NPU Co-Simulation (`tb_pipeline_npu_core.sv`)
Verifies CPU memory-stage bus decoding at `0x8000_0000`, true non-blocking concurrent execution (CPU executes arithmetic in parallel while NPU computes in background), main RAM vs MMIO isolation, and polling loop synchronization:

```bash
cd converting_into_NPU
python3 tests/gen_npu_test_hex.py
mkdir -p build/obj_system && cp tb/instr_mem_npu.hex build/obj_system/instr_mem.hex
verilator --binary --timing tb/tb_pipeline_npu_core.sv rtl/*.sv \
  --top-module tb_pipeline_npu_core -Mdir build/obj_system
(cd build/obj_system && ./Vtb_pipeline_npu_core)
```

#### C. End-to-End 32x32 Tiled GEMM Benchmark (`tb_pipeline_npu_benchmark32.sv`)
Executes a full $32 \times 32$ signed matrix multiplication benchmark using real test datasets from `matmul_32_t2_s32_O2.c`:
- Decomposes $32 \times 32$ matrix product into 8 tiles of $16 \times 16$ ($32,768$ MACs).
- Preloads 1,024 words of Matrix A (`0x0000_0000`) and 1,024 words of Matrix B (`0x0000_1000`).
- CPU coordinates tile transfers via MMIO and accumulates partial products into destination Matrix C at `0x000C_8000`.
- Automatically terminates at completion vector `PC == 0x0000000C` in 186,433 cycles.
- Compares all 1,024 computed 32-bit words bit-for-bit against a golden reference.

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

## 4. Performance Speedup

$$\text{Speedup} = \frac{\text{CPU Software Execution Cycles}}{\text{NPU Accelerated Cycles}}$$

| Kernel Execution Mode | Execution Cycles | Compute Description |
| :--- | :---: | :--- |
| **Pure Scalar Software (RV32I)** | **~1,550,000 cycles** | 3-nested loop C implementation with software-emulated multiplication (~45 cycles/inner loop) |
| **NPU Accelerator (MMIO Architecture)** | **186,433 cycles** | 8 hardware tile GEMMs @ 1 MAC/cycle + MMIO data streaming and block accumulation |
| **Full System Speedup** | **~8.3x Faster** | End-to-end wall-clock cycles including all loop overhead and memory transfers |
| **MAC Datapath Speedup** | **~45x Faster** | 32,768 hardware cycles vs ~1,470,000 software multiplication cycles |

---

## 5. 2-Way Dual-Issue Superscalar Core & Concurrent NPU

Located in [`Superscalar/`](Superscalar/), this advanced microarchitecture transitions the single-issue 5-stage scalar pipeline and MMIO NPU into an **In-Order Dual-Issue Superscalar Processor with a Concurrent Double-Buffered NPU Coprocessor**.

### 5.1 Architecture Highlights
- **Dual-Issue Frontend & 4R/2W RegFile** (Phase 1): 64-bit dual-word fetch, 128-entry BTB with 2-bit bimodal saturating counters, odd-target unaligned steering, and 4-read / 2-write port register file with write-first internal bypassing.
- **Dynamic Hazard & Issue Unit** (Phase 2): Intra-packet RAW detection, younger-port WAW priority, load-use bubble insertion, and memory class conflict matrix.
- **Dual ALUs & Full Crossbar Forwarding** (Phase 3): Dual 32-bit execution ALUs, branch evaluator, and full $4 \times 6$ crossbar forwarding matrix with **intra-cycle ALU0 $\to$ ALU1 bypassing**.
- **True Dual-Port Memory & Arbiter** (Phase 4): Concurrent dual-port RAM and structural hazard arbiter with intra-stage store-to-load forwarding.
- **Concurrent Double-Buffered NPU** (Phase 5): Ping-pong double buffering (Matrix A, B, and C dual 1 KB SRAM banks), dual-channel 64-bit DMA streaming, and 4-entry asynchronous command FIFO.
- **Full Verification & $32 \times 32$ GEMM Benchmark** (Phase 6): 38/38 RV32I architectural compliance (100%), 6-scenario hazard stress suite, and 1,024/1,024 words verified bit-for-bit against golden reference model.

### 5.2 How to Run Superscalar Tests
To run the complete master regression covering all 6 phases:

```bash
cd Superscalar
chmod +x run_all_tests.sh
./run_all_tests.sh
```

To run individual phase regressions:
```bash
./run_phase1_tests.sh   # Frontend & 4R/2W RegFile (77/77 PASS)
./run_phase2_tests.sh   # Dual Decode & Hazard Unit (29/29 PASS)
./run_phase3_tests.sh   # Dual ALUs & 4x6 Forwarding (28/28 PASS)
./run_phase4_tests.sh   # Dual-Port RAM & MemClass Arbiter (13/13 PASS)
./run_phase5_tests.sh   # Double-Buffered NPU & Core Integration (20/20 PASS)
./run_phase6_tests.sh   # RV32I Compliance (38/38) & 32x32 GEMM Benchmark (PASS)
```

### 5.3 Overall Performance Comparison ($32 \times 32$ Matrix Multiplication)

$$\text{Speedup} = \frac{\text{Baseline Execution Cycles}}{\text{Accelerated Cycles}}$$

| Kernel Execution Mode | Execution Cycles | Wall-Clock Speedup | Key Microarchitectural Characteristic |
| :--- | :---: | :---: | :--- |
| **1. Pure Scalar Software (RV32I)** | **~1,550,000 cycles** | $1.0\times$ (Baseline) | Triple-nested software loops with software-emulated multiplication (~45 cycles/inner product). |
| **2. Single-Core CPU + Single-Buffered NPU** | **186,433 cycles** | **~8.3x Faster** | Hardware MAC computes at 1 MAC/cycle, but transfers and compute are strictly sequential. |
| **3. Superscalar Core + Double-Buffered NPU** | **88,524 cycles** | **~17.5x Faster**<br>*(~2.11x vs Single NPU)* | **Dual-issue CPU ($\text{IPC} \le 2.0$)**, **Dual-Channel DMA (64 bits/cycle)**, **Ping-Pong Double Buffering**, and **Command FIFO**. |

---

## 6. Detailed Documentation

- **Superscalar Architectural Plan & Specification**: [`Superscalar/PLAN.md`](Superscalar/PLAN.md)
- **Superscalar Workspace & Phase Regressions**: [`Superscalar/README.md`](Superscalar/README.md)
- **Technical Explanation of Baseline NPU vs. Superscalar NPU**: [`Superscalar/explanation.md`](Superscalar/explanation.md)
- **Production C Driver for Superscalar NPU**: [`Superscalar/sw/npu_driver_superscalar.h`](Superscalar/sw/npu_driver_superscalar.h)
- **Complete Project Architectural Summary**: [`PROJECT_SUMMARY.md`](PROJECT_SUMMARY.md)
- **NPU Architecture & Implementation Specification**: [`PROJECT_SUMMARY_NPU.md`](PROJECT_SUMMARY_NPU.md)
- **Single-Core NPU Test Results Report**: [`converting_into_NPU/TEST_RESULTS.md`](converting_into_NPU/TEST_RESULTS.md)
- **Pipeline Architecture & Hazards**: [`docs/PIPELINE.md`](docs/PIPELINE.md)

---

## Reference
Architecture studied via `vortexgpgpu/vortex`.
