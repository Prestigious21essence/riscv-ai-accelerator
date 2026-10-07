# Hardware Implementation Roadmap: RISC-V NPU Accelerator Core

This document outlines the detailed, step-by-step engineering roadmap for converting the 5-stage non-speculative always-stall RV32I pipelined core ([`converting_into_NPU/`](./)) into a high-performance AI/NPU matrix acceleration processor.

---

## 1. System Architecture Overview

The Neural Processing Unit (NPU) accelerator is integrated as a high-throughput **Memory-Mapped I/O (MMIO) Coprocessor** mapped into the physical address space starting at `0x8000_0000`. 

Rather than modifying the CPU's instruction decoder with non-standard custom ISA opcodes, the NPU interfaces with the CPU in the **MEM (Memory) Stage** alongside the main data RAM ([`data_memory.sv`](rtl/data_memory.sv)). The CPU communicates with the NPU using standard unprivileged RISC-V load and store instructions (`lw`, `sw`).

```
                         [ EX/MEM Pipeline Register ]
                                      |
                     ex_mem_alu_result (Address), ex_mem_write_data
                                      |
                                      v
                 +------------------------------------------+
                 |       MEM Stage Address Decoder          |
                 +------------------------------------------+
                       /                              \
        addr < 0x8000_0000                      addr >= 0x8000_0000
                     /                                  \
                    v                                    v
       +-------------------------+          +-------------------------+
       |   data_memory.sv        |          |      npu_top.sv         |
       |   (Main System RAM)     |          |   (AI Accelerator)      |
       +-------------------------+          +-------------------------+
                    \                                    /
                     \                                  /
                      v                                v
                   +--------------------------------------+
                   |      Read Data Multiplexer           |
                   +--------------------------------------+
                                      |
                             mem_dmem_read_data
                                      |
                                      v
                         [ MEM/WB Pipeline Register ]
```

### Why the MMIO Architecture is Superior
1. **100% ISA Compliance Preservation**: The core retains bit-for-bit compatibility with standard unprivileged RV32I. All 38 official `riscv-arch-test` compliance suites remain 100% passing.
2. **Zero Toolchain Friction**: Standard, unmodified `riscv32-unknown-elf-gcc` compiles C/C++ matrix algorithms directly without compiler patches, custom gas assemblers, or fragile inline assembly macros.
3. **Zero CPU Pipeline Disruption**: The Fetch, Decode, Execute, and Writeback stages are completely unaffected. Synchronization is handled via lightweight status polling (`while (!(*NPU_STATUS & 1));`).
4. **Decoupled Accelerator Microarchitecture**: The compute core inside `npu_top.sv` can evolve from an iterative Multiply-Accumulate (MAC) FSM into a fully parallel 2D systolic array without changing a single line of software driver code or CPU pipeline RTL.

---

## 2. Memory Map & Register Specification

The NPU peripheral occupies the address space from `0x8000_0000` to `0x8000_0FFF`.

### 2.1 Configuration & Control Registers
| Byte Address | Register Name | R/W | Description |
|---|---|---|---|
| `0x8000_0000` | `NPU_DIM_M` | R/W | Matrix Dimension $M$ (Number of rows in $A$ and $C$, $1 \dots 16$) |
| `0x8000_0004` | `NPU_DIM_K` | R/W | Matrix Dimension $K$ (Inner dimension: columns in $A$, rows in $B$, $1 \dots 16$) |
| `0x8000_0008` | `NPU_DIM_N` | R/W | Matrix Dimension $N$ (Number of columns in $B$ and $C$, $1 \dots 16$) |
| `0x8000_000C` | `NPU_TRIGGER` | W | Writing `1` initiates hardware matrix multiplication |
| `0x8000_0010` | `NPU_RESET` | W | Writing `1` soft-resets NPU state, counters, and registers |
| `0x8000_0018` | `NPU_STATUS` | R | **Bit 0**: `done` (1 = calculation complete, cleared on reset/trigger)<br>**Bit 1**: `busy` (1 = compute in progress) |
| `0x8000_0020` | `NPU_CYCLES` | R | Cycle counter measuring computation latency |

### 2.2 Dedicated On-Chip Matrix SRAM Buffers
Each buffer stores up to $16 \times 16 = 256$ 32-bit integer words ($1\text{ KB}$ each):
| Byte Address Range | Size | Buffer Name | Contents / Indexing |
|---|---|---|---|
| `0x8000_0100` – `0x8000_04FF` | $1\text{ KB}$ (256 words) | `mat_a_sram` | Input Matrix $A$: Word index $= i \times 16 + k$ |
| `0x8000_0500` – `0x8000_08FF` | $1\text{ KB}$ (256 words) | `mat_b_sram` | Input Matrix $B$: Word index $= k \times 16 + j$ |
| `0x8000_0900` – `0x8000_0CFF` | $1\text{ KB}$ (256 words) | `mat_c_sram` | Output Matrix $C$: Word index $= i \times 16 + j$ |

---

## 3. Five-Phase Implementation Plan

```text
+-----------------------------------------------------------------------------------+
|  PHASE 1: MEM Stage Bus Interconnect & Address Decoding                           |
|  PHASE 2: NPU Top-Level, Registers & On-Chip SRAM (npu_top.sv)                    |
|  PHASE 3: Hardware Matrix Multiplication Engine (Compute FSM / MAC Unit)          |
|  PHASE 4: RISC-V Software Driver Library & C Application Benchmark                |
|  PHASE 5: Verification, Co-Simulation & Architectural Regression                  |
+-----------------------------------------------------------------------------------+
```

---

### Phase 1: MEM Stage Bus Interconnect & Address Decoding

**Objective**: Modify [`converting_into_NPU/rtl/rv32i_pipeline_stallbranch_core.sv`](rtl/rv32i_pipeline_stallbranch_core.sv) to route memory transactions cleanly between main RAM and the NPU.

#### Implementation Details:
1. **Address Classification**:
   ```systemverilog
   logic is_npu_addr;
   assign is_npu_addr = (ex_mem_alu_result >= 32'h8000_0000);
   ```
2. **Selective Write Enable Gating**:
   ```systemverilog
   logic ram_we, npu_we;
   assign ram_we = ex_mem_mem_write && !is_npu_addr;
   assign npu_we = ex_mem_mem_write &&  is_npu_addr;
   ```
3. **Selective Read Enable Gating**:
   ```systemverilog
   logic ram_re, npu_re;
   assign ram_re = ex_mem_mem_read && !is_npu_addr;
   assign npu_re = ex_mem_mem_read &&  is_npu_addr;
   ```
4. **NPU Module Instantiation**:
   ```systemverilog
   logic [31:0] npu_read_data;
   npu_top npu_inst (
       .clk        (clk),
       .rst        (rst),
       .we         (npu_we),
       .re         (npu_re),
       .addr       (ex_mem_alu_result),
       .write_data (dmem_store_data),
       .read_data  (npu_read_data)
   );
   ```
5. **Read Multiplexing**:
   ```systemverilog
   assign mem_dmem_read_data = is_npu_addr ? npu_read_data : ram_read_data;
   ```

---

### Phase 2: NPU Top-Level, Registers & On-Chip SRAM (`npu_top.sv`)

**Objective**: Implement [`converting_into_NPU/rtl/npu_top.sv`](rtl/npu_top.sv) providing memory-mapped configuration registers and dedicated high-speed SRAM buffers.

#### Implementation Details:
- **Control State Storage**:
  - `dim_m`, `dim_k`, `dim_n` ($5$ bits each, range $0 \dots 16$).
  - `done`, `busy` status flags.
  - Cycle latency accumulator (`cycle_count`).
- **Internal Storage**:
  - `mat_a_sram`: $256 \times 32\text{-bit}$ array.
  - `mat_b_sram`: $256 \times 32\text{-bit}$ array.
  - `mat_c_sram`: $256 \times 32\text{-bit}$ array.
- **Write Port Decoder**:
  - Decodes register offsets `0x00`, `0x04`, `0x08`, `0x0C`, `0x10`.
  - In SRAM address ranges, translates byte addresses to word index:
    $$\text{Index}_A = (\text{addr} - \text{MAT\_A\_ADDR}) \gg 2$$
    $$\text{Index}_B = (\text{addr} - \text{MAT\_B\_ADDR}) \gg 2$$
- **Read Port Multiplexer**:
  - Zero-latency combinational read multiplexer delivering status or Matrix $C$ output to the CPU in the MEM stage.

---

### Phase 3: Hardware Matrix Multiplication Engine (Compute FSM)

**Objective**: Add the hardware compute pipeline inside `npu_top.sv` to execute tile matrix multiplication:
$$\mathbf{C}_{M \times N} = \mathbf{A}_{M \times K} \times \mathbf{B}_{K \times N}$$

```
   +-------------------+
   |      IDLE         | <------+ (Reset / Completed)
   +-------------------+        |
             |                  |
             | start_trigger    |
             v                  |
   +-------------------+        |
   |      CALC         |        |
   | - Loop i: 0..M-1  |        |
   | - Loop j: 0..N-1  |        |
   | - Loop k: 0..K-1  |        |
   | - Acc += A*B      |        |
   +-------------------+        |
             |                  |
             | Finished M*N*K   |
             v                  |
   +-------------------+        |
   |      DONE         | -------+
   | (Assert done = 1) |
   +-------------------+
```

#### FSM State Operations:
1. **`STATE_IDLE`**:
   - `busy = 0`.
   - Listens for write to `NPU_TRIGGER`.
   - On trigger, sets `busy = 1`, `done = 0`, resets loop counters ($i=0, j=0, k=0$), and enters `STATE_CALC`.
2. **`STATE_CALC`**:
   - Loops row index $i$ ($0 \dots M-1$), column index $j$ ($0 \dots N-1$), and inner index $k$ ($0 \dots K-1$).
   - Synchronously reads $A[i \times 16 + k]$ and $B[k \times 16 + j]$.
   - Computes:
     $$\text{accum} \leftarrow (k == 0 \text{ ? } 0 \text{ : } \text{accum}) + (A[i \times 16 + k] \times B[k \times 16 + j])$$
   - When $k == K-1$, commits $\text{accum}$ into `mat_c_sram[i * 16 + j]`.
   - Advances loop counters until $i == M-1 \land j == N-1 \land k == K-1$.
3. **`STATE_DONE`**:
   - Sets `done = 1`, `busy = 0`.
   - Holds status until the CPU reads the result or triggers a new calculation.

---

### Phase 4: RISC-V Software Driver Library & C Application

**Objective**: Provide a clean C driver interface ([`npu_driver.h`](tests/npu_driver.h)) allowing developers to call hardware GEMM transparently.

#### Driver Header (`npu_driver.h`):
```c
#ifndef NPU_DRIVER_H
#define NPU_DRIVER_H

#include <stdint.h>

#define NPU_BASE       0x80000000
#define NPU_DIM_M      ((volatile uint32_t*)(NPU_BASE + 0x00))
#define NPU_DIM_K      ((volatile uint32_t*)(NPU_BASE + 0x04))
#define NPU_DIM_N      ((volatile uint32_t*)(NPU_BASE + 0x08))
#define NPU_TRIGGER    ((volatile uint32_t*)(NPU_BASE + 0x0C))
#define NPU_RESET      ((volatile uint32_t*)(NPU_BASE + 0x10))
#define NPU_STATUS     ((volatile uint32_t*)(NPU_BASE + 0x18))
#define NPU_CYCLES     ((volatile uint32_t*)(NPU_BASE + 0x20))

#define NPU_MAT_A      ((volatile uint32_t*)(NPU_BASE + 0x100))
#define NPU_MAT_B      ((volatile uint32_t*)(NPU_BASE + 0x500))
#define NPU_MAT_C      ((volatile uint32_t*)(NPU_BASE + 0x900))

static inline void npu_gemm_tile(int M, int K, int N,
                                const int32_t *A, int lda,
                                const int32_t *B, int ldb,
                                int32_t *C, int ldc) {
    // 1. Set dimensions
    *NPU_DIM_M = M;
    *NPU_DIM_K = K;
    *NPU_DIM_N = N;

    // 2. Stream Tile A and Tile B into NPU SRAM (16-word stride)
    for (int i = 0; i < M; i++) {
        for (int k = 0; k < K; k++) {
            NPU_MAT_A[i * 16 + k] = A[i * lda + k];
        }
    }
    for (int k = 0; k < K; k++) {
        for (int j = 0; j < N; j++) {
            NPU_MAT_B[k * 16 + j] = B[k * ldb + j];
        }
    }

    // 3. Trigger hardware computation
    *NPU_TRIGGER = 1;

    // 4. Hardware polling loop
    while (!(*NPU_STATUS & 0x1));

    // 5. Extract output tile C
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < N; j++) {
            C[i * ldc + j] = NPU_MAT_C[i * 16 + j];
        }
    }
}

#endif
```

---

### Phase 5: Verification & Hardware-Software Co-Simulation

**Objective**: Rigorously verify RTL accuracy against golden software models and verify that CPU architectural compliance remains 100%.

#### Verification Steps:
1. **Standalone NPU Testbench (`tb_npu_top.sv`)**:
   - Stimulates `npu_top.sv` directly with simulated bus cycles.
   - Verifies dimension registers, matrix loads, trigger, polling, and result correctness on a $4 \times 4$ and $16 \times 16$ matrix.
2. **System-Level Processor Regression (`tb_pipeline_npu_core.sv`)**:
   - Integrates CPU core + NPU.
   - Compiles `test_npu_matmul.c` with `riscv32-unknown-elf-gcc`.
   - Simulates in Verilator.
3. **Golden Software Co-Simulation**:
   - The test program computes identical matrices using both:
     1. Software CPU triple-nested loop: $\sum A_{ik} \times B_{kj}$
     2. Hardware NPU coprocessor: `npu_gemm_tile(...)`
   - Test program asserts $0$ differences:
     $$\forall i, j: \quad |C_{\text{cpu}}[i][j] - C_{\text{npu}}[i][j]| == 0$$
4. **Architectural Compliance Regression**:
   - Re-run `run_stallbranch_suite.sh` on the modified core to confirm all 38/38 official RISC-V architectural tests continue to pass.

---

## 4. Work Tracking & Status Checklist

- [x] **Phase 1: Bus Interconnect**
  - [x] Add `is_npu_addr` decoder to `rv32i_pipeline_stallbranch_core.sv`
  - [x] Add `npu_we`, `npu_re`, and `mem_dmem_read_data` mux
  - [x] Verify core regressions pass unmodified
- [x] **Phase 2: NPU Module & Registers**
  - [x] Create `npu_top.sv` with SRAMs for $A$, $B$, $C$
  - [x] Implement MMIO address decoding for registers and SRAMs
  - [x] Create unit testbench `tb_npu_top.sv`
- [x] **Phase 3: Hardware Compute FSM**
  - [x] Implement `STATE_IDLE`, `STATE_CALC`, `STATE_DONE`
  - [x] Implement inner MAC pipeline with 32-bit accumulator
  - [x] Validate calculation latency and status flags
- [x] **Phase 4: Software Driver**
  - [x] Create `npu_driver.h`
  - [x] Write test benchmark (`gen_npu_test_hex.py` & assembly binary)
- [x] **Phase 5: Co-Simulation & Verification**
  - [x] Execute Verilator simulation of full system (`tb_pipeline_npu_core.sv`)
  - [x] Verify 0 mismatches between CPU and NPU GEMM (Bit-exact match)
  - [x] All 6/6 automated test regressions passing in `run_tests.sh`
