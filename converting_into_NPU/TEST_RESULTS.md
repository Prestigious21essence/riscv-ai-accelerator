# RISC-V RV32I Always-Stall Core & NPU Accelerator — Comprehensive Test Results

**Date**: October 5, 2026  
**Status**: **ALL 7/7 TEST SUITES PASSED (100% SUCCESS, 0 ERRORS)**  
**Target Environment**: Linux, Verilator 5.020, 100 MHz Simulated Clock  
**Architecture**: 5-Stage RV32I Pipelined Core with Always-Stall Branch Unit + Memory-Mapped I/O (MMIO) NPU Coprocessor at `0x8000_0000`

---

## 1. Executive Summary Table

| Test Suite | Module Under Test | Description | Result | Details |
| :--- | :--- | :--- | :---: | :--- |
| **[1/7] Core Basic** | `tb_pipeline_stallbranch_core` | Base RV32I instruction integrity & basic register ops | **PASS** | 7/7 assertions passed |
| **[2/7] Hazard Stress** | `tb_pipeline_stallbranch_hazards` | EX-to-EX & MEM-to-EX forwarding, load-use 1-cycle stall | **PASS** | 11/11 assertions passed |
| **[3/7] Branch & JALR** | `tb_pipeline_stallbranch_branch_jalr` | All branches (`beq`, `bne`, `blt`, `bltu`, `bge`, `bgeu`) & jumps | **PASS** | 18/18 assertions passed |
| **[4/7] Stall Behavior** | `tb_stall_behavior_check` | Zero speculative fetch; PC frozen in ID, resolved in EX | **PASS** | 0 wrong-path instructions |
| **[5/7] NPU Unit Tests** | `tb_npu_top` | 8 arithmetic & control corner case tests on NPU hardware | **PASS** | 8/8 tests passed |
| **[6/7] System Co-Sim** | `tb_pipeline_npu_core` | CPU + NPU concurrent execution, MMIO isolation, polling | **PASS** | 5/5 verifications passed |
| **[7/7] 32x32 Benchmark** | `tb_pipeline_npu_benchmark32` | End-to-end 32x32 tiled GEMM with real data from `matmul.c` | **PASS** | **1,024/1,024 words matched (0 errors)** |

---

## 2. Detailed Results by Test Suite

### [1/7] Core Basic Functional Regression
* **File**: `converting_into_NPU/tb/tb_pipeline_stallbranch_core.sv`
* **Coverage**: Basic ALU execution, register writeback, initial pipeline flow.
* **Results**:
  * `x1 = 5`: PASS
  * `x2 = 10`: PASS
  * `x3 = 15` (forwarded add): PASS
  * `x4 = 15` (loaded from mem): PASS
  * `x5 = 10` (load-use stall): PASS
  * `x6 = 0`: PASS
  * `x7 = 15`: PASS
* **Status**: **PASS (0 errors)**

---

### [2/7] Hazard Stress Regression
* **File**: `converting_into_NPU/tb/tb_pipeline_stallbranch_hazards.sv`
* **Coverage**: Forwarding unit and hazard detection under back-to-back dependency chains.
* **Results**:
  * `x1 = 10`: PASS
  * `x2 = 30` (EX-to-EX forwarding on `rs1`): PASS
  * `x3 = 40` (MEM-to-EX `rs1` + EX-to-EX `rs2`): PASS
  * `x4 = 100`: PASS
  * `x5 = 150` (MEM-to-EX forwarding on `rs1`): PASS
  * `x6 = 10` (loaded from mem): PASS
  * `x7 = 15` (1-cycle load-use stall then forwarded): PASS
  * `x8 = 77` (stored to memory): PASS
  * `x9 = 77` (reloaded from memory): PASS
  * `x10 = 99`: PASS
  * `x11 = 100` (WB-to-ID write-through): PASS
* **Status**: **PASS (11/11 passed)**

---

### [3/7] Branch & JALR Stress Regression
* **File**: `converting_into_NPU/tb/tb_pipeline_stallbranch_branch_jalr.sv`
* **Coverage**: All 6 conditional branch types and unconditional jump links.
* **Results**:
  * `BEQ` (taken branch): PASS
  * `BNE` (not taken, fallthrough): PASS
  * `BLT` (signed comparison, taken): PASS
  * `BLTU` (unsigned comparison, fallthrough): PASS
  * `BGE` (signed comparison, taken): PASS
  * `BGEU` (unsigned comparison, fallthrough): PASS
  * `JAL` (target taken, return PC+4 stored in link register): PASS
  * `JALR` (indirect target taken, return PC+4 stored in link register): PASS
  * Skipped instructions confirmed never reached ID or EX stage: PASS
* **Status**: **PASS (18/18 passed)**

---

### [4/7] Pipeline Stall Behavior Check
* **File**: `converting_into_NPU/tb/tb_stall_behavior_check.sv`
* **Coverage**: Cycle-accurate verification of Always-Stall branch policy.
* **Results**:
  * When branch is in ID: `pc_write = 0` (PC frozen): PASS
  * When branch is in EX: `if_id_write = 0` (Fetch held): PASS
  * `flush_if_id = 0`, `flush_id_ex = 0` (Zero wrong-path instructions fetched or flushed): PASS
  * `pc_write = 1` (PC updates directly to resolved target): PASS
  * Skipped target register (`x8`) remained 0; target register (`x9`) updated to 77: PASS
* **Status**: **PASS (0 errors)**

---

### [5/7] Standalone NPU Hardware Unit Verification
* **File**: `converting_into_NPU/tb/tb_npu_top.sv`
* **Coverage**: NPU compute FSM, register access, 32-bit MAC engine, numerical corner cases.
* **Results**:
  * **Test 1 (Register R/W)**: `DIM_M = 4`, `DIM_K = 4`, `DIM_N = 4` read/write verified.
  * **Test 2 (4x4 Identity Matrix)**: $A \times I_4 = A$ verified bit-exact in **64 cycles**.
  * **Test 3 (16x16 Full Stress Test)**: 4,096 MAC operations verified bit-exact in **4,096 cycles** across all 256 output elements.
  * **Test 4 (All-Zeroes Overwrite)**: Pre-dirty memory (`0xDEADBEEF`) cleanly overwritten with zeroes.
  * **Test 5 (Dimension Sweeps)**:
    * $1 \times 1 \times 1$ scalar MAC: $7 \times -6 = -42$ in **1 cycle**.
    * $1 \times 16 \times 1$ vector dot-product: sum = 272 in **16 cycles**.
    * $3 \times 7 \times 5$ asymmetric matrix: all 15 elements match golden model in **105 cycles**.
  * **Test 6 (Hardware Reset Semantics)**: `NPU_RESET` resets FSM to `STATE_IDLE`, clears `STATUS` to 0, and clears `CYCLES` to 0.
  * **Test 7 (Signed 32-bit Two's Complement Wrap)**: Large product ($1,000,000 \times 3,000 = 0xB2D05E00$) wrapped accurately.
  * **Test 8 (Back-to-Back Computations)**: Multiple consecutive GEMM runs completed with fresh accumulators without soft-reset.
* **Status**: **PASS (8/8 tests passed, 0 errors)**

---

### [6/7] Full-System CPU + NPU Co-Simulation
* **File**: `converting_into_NPU/tb/tb_pipeline_npu_core.sv`
* **Coverage**: CPU memory stage bus decoding, non-blocking concurrent execution, polling synchronization.
* **Results**:
  * **Non-Blocking CPU Concurrency**: While NPU calculated in the background, CPU concurrently executed:
    * `x20 = 100`: PASS
    * `x21 = 200`: PASS
    * `x22 = x20 + x21 = 300`: PASS
  * **Memory Stage Isolation**: Main RAM write/read at `0x00000050` (`x23 = 42`) completely isolated from MMIO `0x80000000`: PASS
  * **Result Readback**:
    * `C[0,0]` in `x11` = 15: PASS
    * `C[0,1]` in `x12` = 22: PASS
    * `C[1,0]` in `x14` = 23: PASS
    * `C[1,1]` in `x15` = 34: PASS
    * `NPU_CYCLES` in `x16` = 8 cycles: PASS
* **Status**: **PASS (0 errors)**

---

### [7/7] End-to-End 32x32 Benchmark Verification
* **File**: `converting_into_NPU/tb/tb_pipeline_npu_benchmark32.sv`
* **Source Dataset**: Real hardcoded matrix arrays $A$ and $B$ from `matmul_32_t2_s32_O2.c` (1,024 elements each).
* **Memory Map**:
  * Unified RAM: 1 MB (`MEM_WORDS = 262,144`)
  * Matrix A: `0x0000_0000` (words 0..1023)
  * Matrix B: `0x0000_1000` (words 1024..2047)
  * Matrix C: `0x000C_8000` (words 204,800..205,823)
  * Completion Detection: `PC == 0x0000000C` (`j 0x0C`)
* **Execution Details**:
  * Decomposed $32 \times 32$ matrix product into 8 tiles of $16 \times 16$ ($32,768$ MAC operations).
  * Program completed and halted at `PC == 0x0000000C` in **186,433 clock cycles**.
* **Golden Comparison**:
  * Checked all 1,024 computed 32-bit words at `0x000C8000` against Python golden reference.
  * Sample Points:
    * `C[0,  0]`: Expected `-78`, Got `-78` (MATCH)
    * `C[0,  1]`: Expected `-156`, Got `-156` (MATCH)
    * `C[0,  2]`: Expected `-109`, Got `-109` (MATCH)
    * `C[0,  3]`: Expected `-358`, Got `-358` (MATCH)
    * `C[31, 28]`: Expected `157`, Got `157` (MATCH)
    * `C[31, 29]`: Expected `7`, Got `7` (MATCH)
    * `C[31, 30]`: Expected `-343`, Got `-343` (MATCH)
    * `C[31, 31]`: Expected `117`, Got `117` (MATCH)
  * **Total Mismatches**: **0 / 1024 (100% Bit-Exact Match)**
* **Status**: **PASS (0 errors)**

---

## 3. Performance & Speedup Benchmark Summary

$$\text{Speedup} = \frac{\text{CPU Software Execution Cycles}}{\text{NPU Accelerated Cycles}}$$

| Kernel Execution Mode | Execution Cycles | Compute Description |
| :--- | :---: | :--- |
| **Pure Scalar Software (RV32I)** | **~1,550,000 cycles** | 3-nested loop C implementation with software-emulated multiplication (~45 cycles/inner loop) |
| **NPU Accelerator (MMIO Architecture)** | **186,433 cycles** | 8 hardware tile GEMMs @ 1 MAC/cycle + MMIO data streaming and block accumulation |
| **Full System Speedup** | **~8.3x Faster** | End-to-end wall-clock cycles including all loop overhead and memory transfers |
| **MAC Datapath Speedup** | **~45x Faster** | 32,768 hardware cycles vs ~1,470,000 software multiplication cycles |

---

## 4. How to Reproduce

To run all 7 test suites locally:
```bash
cd converting_into_NPU
./run_tests.sh
```

To run individual testbenches:
```bash
# Standalone NPU Unit Tests (Level 1)
verilator --binary --timing tb/tb_npu_top.sv rtl/npu_top.sv --top-module tb_npu_top -Mdir build/obj_npu
./build/obj_npu/Vtb_npu_top

# Full-System CPU + NPU Co-Simulation (Level 2)
python3 tests/gen_npu_test_hex.py
cp tb/instr_mem_npu.hex build/obj_system/instr_mem.hex
verilator --binary --timing tb/tb_pipeline_npu_core.sv rtl/*.sv --top-module tb_pipeline_npu_core -Mdir build/obj_system
(cd build/obj_system && ./Vtb_pipeline_npu_core)

# 32x32 Tiled GEMM Benchmark (Level 3 & 4)
python3 tests/gen_npu_benchmark32.py
cp tb/instr_mem_benchmark32.hex build/obj_benchmark32/instr_mem.hex
cp tb/data_a.hex tb/data_b.hex tb/golden_c.hex build/obj_benchmark32/
verilator --binary --timing tb/tb_pipeline_npu_benchmark32.sv rtl/*.sv --top-module tb_pipeline_npu_benchmark32 -Mdir build/obj_benchmark32
(cd build/obj_benchmark32 && ./Vtb_pipeline_npu_benchmark32)
```
