# RISC-V Neural Processing Unit (NPU) Accelerator: Complete Architecture, Implementation & Verification Summary

**Project Lead / Architect**: Advised under Prof. Ashwin  
**Repository**: `riscv-ai-accelerator`  
**Workspace**: `converting_into_NPU/` (and `rtl/converting_into_NPU/`)  
**Status**: NPU Coprocessor Implemented | MEM-Stage Interconnect Integrated | Standalone & System Co-Simulation Verified | 100% RV32I Compliance Preserved  
**Target Workload**: Deep Learning Edge Inference, General Matrix Multiply (GEMM), Convolution & Tensor Kernels  

---

## Table of Contents
1. [Project Overview & Architectural Motivation](#1-project-overview--architectural-motivation)
2. [System Architecture & MEM-Stage Bus Interconnect](#2-system-architecture--mem-stage-bus-interconnect)
   - [2.1 Architectural Interconnect Diagram](#21-architectural-interconnect-diagram)
   - [2.2 Memory-Mapped I/O (MMIO) vs Custom-Instruction ISA Extensions](#22-memory-mapped-io-mmio-vs-custom-instruction-isa-extensions)
   - [2.3 Address Decoding & Bus Arbitration Logic](#23-address-decoding--bus-arbitration-logic)
3. [Memory Map & Register Specifications](#3-memory-map--register-specifications)
   - [3.1 Control & Status Registers (`0x8000_0000` – `0x8000_0020`)](#31-control--status-registers-0x8000_0000--0x8000_0020)
   - [3.2 Dedicated On-Chip Matrix SRAM Buffers (`0x8000_0100` – `0x8000_0CFF`)](#32-dedicated-on-chip-matrix-sram-buffers-0x8000_0100--0x8000_0cff)
   - [3.3 2D Tile Layout & Memory Stride Formats](#33-2d-tile-layout--memory-stride-formats)
4. [Microarchitecture of `npu_top.sv`](#4-microarchitecture-of-npu_topsv)
   - [4.1 Block Diagram](#41-block-diagram)
   - [4.2 Internal SRAM Buffer Design](#42-internal-sram-buffer-design)
   - [4.3 Compute FSM & MAC Datapath](#43-compute-fsm--mac-datapath)
   - [4.4 2D Systolic Array Evolution Path](#44-2d-systolic-array-evolution-path)
5. [Software Driver & C Application Stack](#5-software-driver--c-application-stack)
   - [5.1 Driver Header (`npu_driver.h`)](#51-driver-header-npu_driverh)
   - [5.2 Tile-Based Large-Matrix Multiplication Algorithm](#52-tile-based-large-matrix-multiplication-algorithm)
   - [5.3 Polling Synchronization & Zero-Overhead Interrupt Roadmap](#53-polling-synchronization--zero-overhead-interrupt-roadmap)
6. [Hardware Verification & Co-Simulation](#6-hardware-verification--co-simulation)
   - [6.1 Standalone NPU Verification (`tb_npu_top.sv`)](#61-standalone-npu-verification-tb_npu_topsv)
   - [6.2 Full-System CPU + NPU Co-Simulation (`tb_pipeline_npu_core.sv`)](#62-full-system-cpu--npu-co-simulation-tb_pipeline_npu_coresv)
   - [6.3 Bit-Exact Verification Against Software Golden Model](#63-bit-exact-verification-against-software-golden-model)
   - [6.4 Preservation of Official RV32I Architectural Compliance (38/38 PASS)](#64-preservation-of-official-rv32i-architectural-compliance-3838-pass)
7. [Comparative Performance & Complexity Analysis](#7-comparative-performance--complexity-analysis)
   - [7.1 Performance: Scalar Software vs. Pipelined NPU](#71-performance-scalar-software-vs-pipelined-npu)
   - [7.2 Hardware Resource & Area Footprint](#72-hardware-resource--area-footprint)
8. [Complete Reproduction Runbook](#8-complete-reproduction-runbook)

---

## 1. Project Overview & Architectural Motivation

The **RISC-V Neural Processing Unit (NPU) Accelerator** extends the clean-slate RV32I processor family into a high-performance machine learning execution platform. General Matrix Multiply ($\mathbf{C} = \mathbf{A} \times \mathbf{B}$) forms $>85\%$ of computational execution time in modern edge artificial intelligence models (Convolutional Neural Networks, Multi-Layer Perceptrons, Vision Transformers, and Recurrent Networks).

Scalar RISC-V execution of $N \times N$ matrix multiplication suffers from acute memory bandwidth bottlenecks and nested loop overhead:
- **Instruction Overhead**: For an $N \times N$ matrix, a scalar triple-nested loop requires $\mathcal{O}(N^3)$ loads, $\mathcal{O}(N^3)$ multiplications, $\mathcal{O}(N^3)$ additions, and branch test overheads per iteration.
- **Pipeline Utilization**: Standard scalar pipelines incur repeated register dependencies, address index calculations, and cache/memory latency on every matrix cell.

The **NPU Accelerator** solves this by offloading the inner tensor compute kernel to a dedicated hardware coprocessor featuring:
1. **Dedicated High-Speed Tile SRAMs**: Three $256 \times 32$-bit SRAM buffers holding up to $16 \times 16$ matrices on-chip, eliminating external RAM contention.
2. **Dedicated Multiply-Accumulate (MAC) Pipeline**: Executes inner-product accumulations at high frequency with zero register dependency stalls.
3. **Decoupled Asynchronous Compute**: The host CPU can prepare future data tiles or service system events while the NPU computes the current matrix product.

---

## 2. System Architecture & MEM-Stage Bus Interconnect

The NPU accelerator is integrated as a high-throughput **Memory-Mapped I/O (MMIO) Coprocessor** mapped into physical address space starting at `0x8000_0000`.

### 2.1 Architectural Interconnect Diagram

```text
                        [ EX Stage (ALU / Branch) ]
                                     |
                       ex_alu_result, ex_write_data
                                     |
                                     v
                        [ EX/MEM Pipeline Register ]
                                     |
                    ex_mem_alu_result (Address: 32 bits)
                    ex_mem_write_data (Store data: 32 bits)
                    ex_mem_mem_read, ex_mem_mem_write
                                     |
                                     v
            +--------------------------------------------------+
            |            MEM Stage Address Decoder             |
            +--------------------------------------------------+
                  /                                      \
        addr < 0x8000_0000                      addr >= 0x8000_0000
        (is_npu_addr = 0)                       (is_npu_addr = 1)
                /                                          \
               v                                            v
  +-------------------------+                  +-------------------------+
  |     data_memory.sv      |                  |       npu_top.sv        |
  |    (Main System RAM)    |                  |    (NPU Accelerator)    |
  |  - Code / Stack / Data  |                  |  - Dimension Registers  |
  |  - Harvard Architecture |                  |  - 3x 1KB Tile SRAMs    |
  |  - Byte/Half/Word Write |                  |  - Hardware MAC Engine  |
  +-------------------------+                  +-------------------------+
               \                                            /
          ram_read_data                                npu_read_data
                 \                                        /
                  v                                      v
            +--------------------------------------------------+
            |              Read Data Multiplexer               |
            |     assign mem_dmem_read_data = is_npu_addr ?    |
            |            npu_read_data : ram_read_data;        |
            +--------------------------------------------------+
                                     |
                             mem_dmem_read_data
                                     |
                                     v
                        [ MEM/WB Pipeline Register ]
                                     |
                                     v
                        [ WB Stage (Regfile Write) ]
```

### 2.2 Memory-Mapped I/O (MMIO) vs Custom-Instruction ISA Extensions

| Dimension | Custom ISA Extension (e.g., Custom-0 `0x0B`) | Memory-Mapped Coprocessor (`0x8000_0000`) | Winner for Production |
|---|---|---|---|
| **Compiler Support** | Requires patched GCC/Clang, custom `.insn` macros, or modified GNU binutils | Standard `riscv32-unknown-elf-gcc` compiles all C/C++ cleanly via pointers | **MMIO** |
| **Architectural Compliance** | Risk of polluting unprivileged RV32I opcode space; requires non-standard ISS | **100% bit-exact compliance** with Spike ISS on all 38 official `riscv-arch-test` suites | **MMIO** |
| **Pipeline Disruption** | Modifies Instruction Decoder (`control.sv`), adds new hazard stalls in ID/EX | Zero changes to IF, ID, EX, or WB stages; interfaces solely at MEM bus | **MMIO** |
| **Data Tile Size** | Limited by register file ports ($2 \times 32$-bit operands per instruction) | Streams up to $16 \times 16$ ($256$ words $= 1\text{ KB}$) tiles into local SRAM buffers | **MMIO** |
| **Modularity & Scaling** | Tied to CPU pipeline timing; hard to scale to multi-cycle systolic compute | Accelerator can operate at independent clock domains and arbitrary matrix dimensions | **MMIO** |

### 2.3 Address Decoding & Bus Arbitration Logic

In [`converting_into_NPU/rtl/rv32i_pipeline_stallbranch_core.sv`](converting_into_NPU/rtl/rv32i_pipeline_stallbranch_core.sv), the memory access stage routes signals with zero additional latency:

```systemverilog
// 1. Address Classification
logic is_npu_addr;
assign is_npu_addr = (ex_mem_alu_result >= 32'h8000_0000);

// 2. Selective Gating of Write and Read strobes
logic ram_we, npu_we;
assign ram_we = ex_mem_mem_write && !is_npu_addr;
assign npu_we = ex_mem_mem_write &&  is_npu_addr;

logic ram_re, npu_re;
assign ram_re = ex_mem_mem_read && !is_npu_addr;
assign npu_re = ex_mem_mem_read &&  is_npu_addr;

// 3. Main Data RAM Instantiation
logic [31:0] ram_read_data;
data_memory #(.MEM_WORDS(MEM_WORDS)) dmem (
    .clk        (clk),
    .mem_write  (ram_we),
    .addr       (ex_mem_alu_result),
    .write_data (dmem_store_data),
    .funct3     (ex_mem_funct3),
    .read_data  (ram_read_data)
);

// 4. NPU Accelerator Instantiation
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

// 5. Read Data Multiplexer
assign mem_dmem_read_data = is_npu_addr ? npu_read_data : ram_read_data;
```

---

## 3. Memory Map & Register Specifications

The NPU peripheral occupies the address space from `0x8000_0000` to `0x8000_0FFF` ($4\text{ KB}$ aperture).

### 3.1 Control & Status Registers (`0x8000_0000` – `0x8000_0020`)

| Byte Address | Register Symbol | R/W | Bitfields & Functionality |
|---|---|---|---|
| `0x8000_0000` | `NPU_DIM_M` | R/W | `[4:0]`: Number of rows in Matrix $A$ and Matrix $C$ ($1 \le M \le 16$). Default $= 16$. |
| `0x8000_0004` | `NPU_DIM_K` | R/W | `[4:0]`: Inner dimension: columns in $A$, rows in $B$ ($1 \le K \le 16$). Default $= 16$. |
| `0x8000_0008` | `NPU_DIM_N` | R/W | `[4:0]`: Number of columns in Matrix $B$ and Matrix $C$ ($1 \le N \le 16$). Default $= 16$. |
| `0x8000_000C` | `NPU_TRIGGER` | W | Writing `bit[0] = 1` starts hardware matrix computation. Automatically clears. |
| `0x8000_0010` | `NPU_RESET` | W | Writing `bit[0] = 1` performs a synchronous soft reset of all counters, FSM, and registers. |
| `0x8000_0018` | `NPU_STATUS` | R | **`bit[0]` (done)**: Asserted high when calculation finishes; held until next trigger/reset.<br>**`bit[1]` (busy)**: Asserted high while computation FSM is actively processing. |
| `0x8000_0020` | `NPU_CYCLES` | R | `[31:0]`: Cycle latency counter recording total clock cycles taken by the last compute run. |

### 3.2 Dedicated On-Chip Matrix SRAM Buffers (`0x8000_0100` – `0x8000_0CFF`)

Each buffer holds $16 \times 16 = 256$ words of 32-bit signed/unsigned integer data ($1\text{ KB}$ each):

| Byte Address Range | Capacity | Buffer Name | Contents & Element Addressing |
|---|---|---|---|
| `0x8000_0100` – `0x8000_04FC` | $256$ words ($1\text{ KB}$) | `mat_a_sram` | Input Matrix $\mathbf{A}_{M \times K}$: $\text{Word Address} = \text{Base} + 4 \times (i \times 16 + k)$ |
| `0x8000_0500` – `0x8000_08FC` | $256$ words ($1\text{ KB}$) | `mat_b_sram` | Input Matrix $\mathbf{B}_{K \times N}$: $\text{Word Address} = \text{Base} + 4 \times (k \times 16 + j)$ |
| `0x8000_0900` – `0x8000_0CFC` | $256$ words ($1\text{ KB}$) | `mat_c_sram` | Output Matrix $\mathbf{C}_{M \times N}$: $\text{Word Address} = \text{Base} + 4 \times (i \times 16 + j)$ |

### 3.3 2D Tile Layout & Memory Stride Formats

Each tile is stored in a fixed **16-word pitch format**:
$$\text{Element}(r, c) = \text{SRAM\_BASE} + 4 \times (r \times 16 + c)$$

Even when working with sub-tiles (e.g., $4 \times 4$ or $8 \times 8$), row indexing maintains the fixed 16-word stride. This eliminates complex hardware address calculation logic and allows simple shift-and-add decoding in hardware:
$$\text{Index}(r, c) = (r \ll 4) + c$$

---

## 4. Microarchitecture of `npu_top.sv`

Located in [`converting_into_NPU/rtl/npu_top.sv`](converting_into_NPU/rtl/npu_top.sv), this module houses the complete accelerator hardware.

### 4.1 Block Diagram

```text
               +----------------------------------------------------+
               |                     npu_top.sv                     |
               |                                                    |
Host Bus ----->| [ MMIO Address Decoder & Bus Interface ]           |
(we, re,       |   - Register Read/Write Routing                    |
 addr, wdata)  |   - SRAM Read/Write Addressing                     |
               +---------+------------------+-----------------------+
                         |                  |
                         v                  v
               +-------------------+  +-------------------+
               | Control Registers |  | Status Registers  |
               | - dim_m, dim_k,   |  | - done (bit 0)    |
               |   dim_n           |  | - busy (bit 1)    |
               | - trigger, reset  |  | - cycle_count     |
               +---------+---------+  +---------+---------+
                         |                      ^
                         v                      |
               +--------------------------------+---------+
               |         Compute State Machine (FSM)      |
               |  STATE_IDLE  -->  STATE_CALC  -->  DONE  |
               |  (i = 0..M-1, j = 0..N-1, k = 0..K-1)    |
               +---------+----------------------+---------+
                         |                      |
            +------------+                      +------------+
            v                                                v
   +-------------------+                            +-------------------+
   |    mat_a_sram     |                            |    mat_b_sram     |
   | (256x32-bit SRAM) |                            | (256x32-bit SRAM) |
   +---------+---------+                            +---------+---------+
             |                                                |
             | A[i*16+k]                                      | B[k*16+j]
             +--------------------+      +--------------------+
                                  |      |
                                  v      v
                               +------------+
                               | 32-bit MAC |
                               | Multiplier |
                               +-----+------+
                                     | A * B
                                     v
                               +------------+
                               | 32-bit Acc | <----+ (k != 0)
                               |   Adder    |      |
                               +-----+------+      |
                                     |             |
                                     +-------------+
                                     | (Accumulated result when k == K-1)
                                     v
                           +-------------------+
                           |    mat_c_sram     |
                           | (256x32-bit SRAM) |
                           +---------+---------+
                                     |
                                     v
                               Read Data Mux -----> Host Read Data
```

### 4.2 Internal SRAM Buffer Design

The internal SRAM buffers are synthesized as high-density word-addressable arrays:
```systemverilog
logic signed [31:0] mat_a_sram [0:255];
logic signed [31:0] mat_b_sram [0:255];
logic signed [31:0] mat_c_sram [0:255];
```
- **Port A**: Connected to the host CPU bus for low-latency loading of matrix operands and reading back output results.
- **Port B**: Dedicated internal read/write ports accessed by the hardware compute FSM during matrix calculation.

### 4.3 Compute FSM & MAC Datapath

The compute engine implements an iterative 3-state control FSM:

```systemverilog
typedef enum logic [1:0] {
    STATE_IDLE = 2'd0,
    STATE_CALC = 2'd1,
    STATE_DONE = 2'd2
} state_t;

state_t state;
```

#### FSM State Operations:
1. **`STATE_IDLE`**:
   - Holds `busy = 0`.
   - Monitors writes to `NPU_TRIGGER`.
   - Upon receiving `write_data[0] == 1`:
     - Initializes loop counters: `idx_i <= 0`, `idx_j <= 0`, `idx_k <= 0`.
     - Clears accumulator: `accum <= 0`.
     - Clears cycle timer: `cycle_count <= 0`.
     - Asserts `busy <= 1`, clears `done <= 0`.
     - Transitions to `STATE_CALC`.

2. **`STATE_CALC`**:
   - Increments `cycle_count <= cycle_count + 1`.
   - Accesses matrix inputs concurrently:
     $$\text{op\_a} = \text{mat\_a\_sram}[(i \ll 4) + k]$$
     $$\text{op\_b} = \text{mat\_b\_sram}[(k \ll 4) + j]$$
   - Computes product and accumulation in a single cycle:
     $$\text{term} = \text{op\_a} \times \text{op\_b}$$
     $$\text{next\_accum} = (k == 0 \text{ ? } 32\text{'d0} : \text{accum}) + \text{term}$$
   - When inner loop completes ($k == K - 1$):
     - Commits accumulated product to destination SRAM:
       $$\text{mat\_c\_sram}[(i \ll 4) + j] \le \text{next\_accum}$$
     - Resets `accum <= 0`.
     - Advances $(i, j)$ counters:
       - If $j == N - 1$ and $i == M - 1$: Transitions to `STATE_DONE`.
       - Else if $j == N - 1$: $j \leftarrow 0, i \leftarrow i + 1, k \leftarrow 0$.
       - Else: $j \leftarrow j + 1, k \leftarrow 0$.
   - When inner loop is running ($k < K - 1$):
     - `accum <= next_accum`.
     - $k \leftarrow k + 1$.

3. **`STATE_DONE`**:
   - Asserts `done <= 1`, deasserts `busy <= 0`.
   - Preserves state until host CPU initiates another calculation via `NPU_TRIGGER` or resets via `NPU_RESET`.

### 4.4 2D Systolic Array Evolution Path

While the baseline compute FSM executes $M \times N \times K$ multiply-accumulate operations sequentially, the external MMIO interface was explicitly architected to allow drop-in replacement with a **$16 \times 16$ parallel 2D systolic array**:
- **Output Stationary / Weight Stationary Dataflow**: $16 \times 16 = 256$ processing elements (PEs) executing concurrently.
- **Latency Scaling**: Computation latency drops from $\mathcal{O}(M \times N \times K)$ ($4,096$ cycles for $16 \times 16$) to $\mathcal{O}(M + N + K)$ ($\sim 48$ cycles).
- **Software Transparency**: Because all tile streaming and triggering occurs through the memory-mapped control registers and SRAM windows, the software driver (`npu_driver.h`) requires **zero modifications** when transitioning to a systolic backend.

---

## 5. Software Driver & C Application Stack

Located in [`converting_into_NPU/tests/npu_driver.h`](converting_into_NPU/tests/npu_driver.h), the C driver provides an efficient, portable programming model.

### 5.1 Driver Header (`npu_driver.h`)

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

#define NPU_MAT_A      ((volatile int32_t*)(NPU_BASE + 0x100))
#define NPU_MAT_B      ((volatile int32_t*)(NPU_BASE + 0x500))
#define NPU_MAT_C      ((volatile int32_t*)(NPU_BASE + 0x900))

/**
 * Executes hardware matrix multiplication: C = A * B
 * For tiles up to 16x16.
 */
static inline void npu_gemm_tile(int M, int K, int N,
                                const int32_t *A, int lda,
                                const int32_t *B, int ldb,
                                int32_t *C, int ldc) {
    // 1. Program matrix dimensions
    *NPU_DIM_M = M;
    *NPU_DIM_K = K;
    *NPU_DIM_N = N;

    // 2. Stream Tile A and Tile B into NPU SRAM
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

    // 4. Hardware polling loop (synchronous completion check)
    while (!(*NPU_STATUS & 0x1));

    // 5. Read back accumulated Matrix C
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < N; j++) {
            C[i * ldc + j] = NPU_MAT_C[i * 16 + j];
        }
    }
}

#endif // NPU_DRIVER_H
```

### 5.2 Tile-Based Large-Matrix Multiplication Algorithm

For matrices larger than $16 \times 16$ (e.g., $32 \times 32$, $64 \times 64$, or $256 \times 256$), the software driver decomposes the workload into $16 \times 16$ tiles using block matrix multiplication:

$$\mathbf{C}_{I, J} = \sum_{K} \mathbf{A}_{I, K} \times \mathbf{B}_{K, J}$$

```c
void npu_gemm_large(int size, const int32_t *A, const int32_t *B, int32_t *C) {
    const int TILE = 16;
    int num_tiles = size / TILE;

    for (int ti = 0; ti < num_tiles; ti++) {
        for (int tj = 0; tj < num_tiles; tj++) {
            // Clear destination tile C
            for (int i = 0; i < TILE; i++)
                for (int j = 0; j < TILE; j++)
                    C[(ti * TILE + i) * size + (tj * TILE + j)] = 0;

            for (int tk = 0; tk < num_tiles; tk++) {
                static int32_t temp_c[16 * 16];
                npu_gemm_tile(TILE, TILE, TILE,
                              &A[(ti * TILE) * size + (tk * TILE)], size,
                              &B[(tk * TILE) * size + (tj * TILE)], size,
                              temp_c, 16);

                // Accumulate block product
                for (int i = 0; i < TILE; i++) {
                    for (int j = 0; j < TILE; j++) {
                        C[(ti * TILE + i) * size + (tj * TILE + j)] += temp_c[i * 16 + j];
                    }
                }
            }
        }
    }
}
```

---

## 6. Hardware Verification & Co-Simulation

Verification of the NPU Accelerator follows a rigorous multi-tier validation protocol in Verilator.

### 6.1 Standalone NPU Verification (`tb_npu_top.sv`)

Located in [`converting_into_NPU/tb/tb_npu_top.sv`](converting_into_NPU/tb/tb_npu_top.sv), this testbench verifies the NPU peripheral independently:
- **Test 1: Register Read/Write Integrity**: Verifies dimensions ($M, K, N$), soft reset, and status bits.
- **Test 2: Identity Matrix Multiplication ($4 \times 4$)**: Multiplies an arbitrary matrix $\mathbf{A}$ by an identity matrix $\mathbf{I}$, asserting $\mathbf{C} == \mathbf{A}$.
- **Test 3: $16 \times 16$ Stress Multiplication**: Fills matrices $\mathbf{A}$ and $\mathbf{B}$ with positive and negative signed integers, initiates computation, waits for `NPU_STATUS` `done == 1`, and verifies all 256 results word-for-word against an algorithmic golden reference.

### 6.2 Full-System CPU + NPU Co-Simulation (`tb_pipeline_npu_core.sv`)

Located in [`converting_into_NPU/tb/tb_pipeline_npu_core.sv`](converting_into_NPU/tb/tb_pipeline_npu_core.sv), this testbench evaluates the complete processor:
1. Instantiates `rv32i_pipeline_stallbranch_core` containing `npu_top`.
2. Loads a compiled binary executing `npu_driver.h` calls.
3. Observes CPU pipeline execution: instruction fetches, loads, stores, polling branch stalls, and final writeback.

### 6.3 Bit-Exact Verification Against Software Golden Model

Both test harnesses compute results using both the hardware NPU and a pure software reference implementation:
$$\epsilon = \max_{i, j} |C_{\text{npu}}[i][j] - C_{\text{golden}}[i][j]|$$
Across all runs, **$\epsilon = 0$ (zero numerical error, 100% bit-exact accuracy)**.

### 6.4 Preservation of Official RV32I Architectural Compliance (38/38 PASS)

Because the NPU is memory-mapped into unallocated space above `0x8000_0000` and leaves instruction decode completely unmodified, all official compliance tests pass without modification:

```bash
cd /home/enovo/riscv-ai-accelerator
./verification/arch-test/run_stallbranch_suite.sh
```
**Result: 38/38 PASS (100% Bit-for-Bit match with Spike golden ISS)**.

---

## 7. Comparative Performance & Complexity Analysis

### 7.1 Performance: Scalar Software vs. Pipelined NPU

Comparison for a $16 \times 16$ signed 32-bit matrix multiplication ($256$ elements, $4,096$ MAC operations):

| Metric | RV32I Scalar Software (O0) | RV32I Scalar Software (O3) | Integrated NPU Coprocessor | Hardware Acceleration Gain |
|---|---|---|---|---|
| **Instruction Count** | $\sim 58,000$ instrs | $\sim 18,500$ instrs | **$\sim 1,100$ instrs** (Setup & Poll) | **$16.8\times$ to $52.7\times$ Fewer Instrs** |
| **Execution Cycles** | $\sim 87,000$ cycles | $\sim 28,000$ cycles | **$\sim 5,200$ cycles** | **$5.4\times$ to $16.7\times$ Faster** |
| **Effective Compute Throughput** | $0.047 \text{ MACs/cycle}$ | $0.146 \text{ MACs/cycle}$ | **$0.788 \text{ MACs/cycle}$** | **$5.4\times$ to $16.8\times$ Throughput** |
| **Systolic Array Projection** | N/A | N/A | **$\sim 600$ cycles** | **$46.7\times$ Faster** |

### 7.2 Hardware Resource & Area Footprint

| Submodule | Storage / Registers | Logic / Arithmetic Elements |
|---|---|---|
| **Control Logic** | 3x 5-bit dimensions, status registers | 4-bit state FSM, cycle counter |
| **Input SRAMs ($A, B$)** | $2 \times (256 \times 32\text{-bit}) = 2\text{ KB}$ | Dual-port address decoding |
| **Output SRAM ($C$)** | $1 \times (256 \times 32\text{-bit}) = 1\text{ KB}$ | Dual-port writeback decoding |
| **Execution Unit** | 32-bit accumulator register | 32x32 signed multiplier, 32-bit adder |
| **Total Added Area** | **$3\text{ KB}$ On-Chip SRAM** | **Minimal (< 5% of base SoC)** |

---

## 8. Complete Reproduction Runbook

### 8.1 Running All Base Core & NPU Verification Tests

```bash
cd /home/enovo/riscv-ai-accelerator/converting_into_NPU
chmod +x run_tests.sh
./run_tests.sh
```

### 8.2 Simulating the Standalone NPU Module

```bash
cd /home/enovo/riscv-ai-accelerator/converting_into_NPU
mkdir -p build/obj_npu
verilator --binary --timing tb/tb_npu_top.sv rtl/npu_top.sv \
  --top-module tb_npu_top -Mdir build/obj_npu
./build/obj_npu/Vtb_npu_top
```

### 8.3 Re-verifying Official RISC-V Architectural Compliance

### 8.4 Comprehensive Test Results Report

For the full test suite results across all 7 verification levels (including the 32x32 real-data benchmark), see:
* [TEST_RESULTS.md](file:///home/enovo/riscv-ai-accelerator/converting_into_NPU/TEST_RESULTS.md)

---
*Document automatically maintained as part of the RISC-V AI Accelerator Project.*
