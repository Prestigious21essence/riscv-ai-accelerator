/**
 * =============================================================================
 * RISC-V 2-Way Superscalar Neural Processing Unit (NPU) Software Driver
 * File: npu_driver_superscalar.h
 *
 * Description:
 *   High-performance C driver for the concurrent, double-buffered, non-blocking
 *   memory-mapped NPU coprocessor mapped at base address 0x80000000.
 *
 * Microarchitectural Highlights:
 *   1. Ping-Pong Double Buffering:
 *      - Computes on active_bank while concurrently streaming tiles into shadow_bank.
 *      - Completely hides memory transfer latency behind computation.
 *   2. Asynchronous 4-Entry Command FIFO:
 *      - Pushes commands without spin-lock polling.
 *      - CPU immediately resumes executing loop counters, pointer arithmetic, etc.
 *   3. Dual-Channel DMA Streaming:
 *      - Matrix A and Matrix B can be streamed in parallel across Port 0 & Port 1.
 * =============================================================================
 */

#ifndef NPU_DRIVER_SUPERSCALAR_H
#define NPU_DRIVER_SUPERSCALAR_H

#include <stdint.h>

// -----------------------------------------------------------------------------
// MMIO Base Addresses & Register Definitions
// -----------------------------------------------------------------------------
#define NPU_BASE            0x80000000U

#define NPU_DIM_M           ((volatile uint32_t*)(NPU_BASE + 0x00))
#define NPU_DIM_K           ((volatile uint32_t*)(NPU_BASE + 0x04))
#define NPU_DIM_N           ((volatile uint32_t*)(NPU_BASE + 0x08))
#define NPU_TRIGGER         ((volatile uint32_t*)(NPU_BASE + 0x0C))
#define NPU_RESET           ((volatile uint32_t*)(NPU_BASE + 0x10))
#define NPU_CMD_FIFO        ((volatile uint32_t*)(NPU_BASE + 0x14))
#define NPU_STATUS          ((volatile uint32_t*)(NPU_BASE + 0x18))
#define NPU_CTRL            ((volatile uint32_t*)(NPU_BASE + 0x1C))
#define NPU_CYCLES          ((volatile uint32_t*)(NPU_BASE + 0x20))
#define NPU_FIFO_COUNT      ((volatile uint32_t*)(NPU_BASE + 0x24))

// Status register bitfields
#define NPU_STATUS_DONE         (1U << 0)
#define NPU_STATUS_BUSY         (1U << 1)
#define NPU_STATUS_FIFO_FULL    (1U << 2)
#define NPU_STATUS_FIFO_EMPTY   (1U << 3)
#define NPU_STATUS_ACTIVE_BANK  (1U << 4)
#define NPU_STATUS_IRQ          (1U << 5)

// Control register bitfields
#define NPU_CTRL_MANUAL_SWAP    (1U << 0)
#define NPU_CTRL_AUTO_SHADOW    (1U << 1)
#define NPU_CTRL_AUTO_SWAP_DONE (1U << 2)

// Command Opcodes for NPU_CMD_FIFO
#define NPU_CMD_NOP                     0x0U
#define NPU_CMD_START_GEMM              0x1U
#define NPU_CMD_SWAP_BANKS              0x2U
#define NPU_CMD_START_GEMM_AUTO_SWAP    0x3U
#define NPU_CMD_SOFT_RESET              0x4U

// On-Chip SRAM Buffers (Bank 0 by default, bit 12 = 1 selects Bank 1)
#define NPU_BANK_STRIDE     0x1000U // Bit 12 selects bank

#define NPU_MAT_A_BANK0     ((volatile int32_t*)(NPU_BASE + 0x100))
#define NPU_MAT_B_BANK0     ((volatile int32_t*)(NPU_BASE + 0x500))
#define NPU_MAT_C_BANK0     ((volatile int32_t*)(NPU_BASE + 0x900))

#define NPU_MAT_A_BANK1     ((volatile int32_t*)(NPU_BASE + 0x100 + NPU_BANK_STRIDE))
#define NPU_MAT_B_BANK1     ((volatile int32_t*)(NPU_BASE + 0x500 + NPU_BANK_STRIDE))
#define NPU_MAT_C_BANK1     ((volatile int32_t*)(NPU_BASE + 0x900 + NPU_BANK_STRIDE))

// -----------------------------------------------------------------------------
// Driver Utility Functions
// -----------------------------------------------------------------------------

/**
 * Reset NPU internal datapath, pointers, and FIFO.
 */
static inline void npu_superscalar_reset(void) {
    *NPU_RESET = 1;
}

/**
 * Configure matrix dimensions for upcoming hardware GEMM operations.
 * Supported range: 1 to 16 for M, K, and N.
 */
static inline void npu_superscalar_set_dims(uint32_t M, uint32_t K, uint32_t N) {
    *NPU_DIM_M = M;
    *NPU_DIM_K = K;
    *NPU_DIM_N = N;
}

/**
 * Enable or disable automatic shadow streaming and auto-swap mode.
 */
static inline void npu_superscalar_set_control(uint32_t flags) {
    *NPU_CTRL = flags;
}

/**
 * Push an asynchronous command into the 4-entry Command FIFO.
 * Waits only if the FIFO is completely full (non-blocking in typical execution).
 */
static inline void npu_superscalar_push_cmd(uint32_t cmd_word) {
    while (*NPU_STATUS & NPU_STATUS_FIFO_FULL);
    *NPU_CMD_FIFO = cmd_word;
}

/**
 * Query current active compute bank (0 or 1).
 */
static inline uint32_t npu_superscalar_get_active_bank(void) {
    return (*NPU_STATUS & NPU_STATUS_ACTIVE_BANK) ? 1U : 0U;
}

/**
 * Query current shadow streaming bank (~active_bank).
 */
static inline uint32_t npu_superscalar_get_shadow_bank(void) {
    return npu_superscalar_get_active_bank() ^ 1U;
}

/**
 * Non-blocking check for GEMM completion.
 * Returns 1 if complete, 0 if still calculating.
 */
static inline int npu_superscalar_is_done(void) {
    return (*NPU_STATUS & NPU_STATUS_DONE) ? 1 : 0;
}

/**
 * Non-blocking check for NPU busy status.
 */
static inline int npu_superscalar_is_busy(void) {
    return (*NPU_STATUS & NPU_STATUS_BUSY) ? 1 : 0;
}

/**
 * Wait for ongoing NPU compute to finish (sync barrier).
 */
static inline void npu_superscalar_wait_done(void) {
    while (!(*NPU_STATUS & NPU_STATUS_DONE));
}

/**
 * Read the total execution cycles accumulated by the NPU.
 */
static inline uint32_t npu_superscalar_get_cycles(void) {
    return *NPU_CYCLES;
}

/**
 * Manual flip of active and shadow buffer pointers.
 */
static inline void npu_superscalar_swap_banks(void) {
    *NPU_CTRL = *NPU_CTRL | NPU_CTRL_MANUAL_SWAP;
}

// -----------------------------------------------------------------------------
// High-Level Ping-Pong Overlapped Tiled GEMM
// -----------------------------------------------------------------------------

/**
 * Stream a tile into a specified bank.
 */
static inline void npu_superscalar_stream_tile(uint32_t bank,
                                              int M, int K, int N,
                                              const int32_t *A, int lda,
                                              const int32_t *B, int ldb) {
    volatile int32_t *target_a = (bank == 0) ? NPU_MAT_A_BANK0 : NPU_MAT_A_BANK1;
    volatile int32_t *target_b = (bank == 0) ? NPU_MAT_B_BANK0 : NPU_MAT_B_BANK1;

    // Stream Matrix A tile (16-word pitch)
    for (int i = 0; i < M; i++) {
        for (int k = 0; k < K; k++) {
            target_a[i * 16 + k] = A[i * lda + k];
        }
    }

    // Stream Matrix B tile (16-word pitch)
    for (int k = 0; k < K; k++) {
        for (int j = 0; j < N; j++) {
            target_b[k * 16 + j] = B[k * ldb + j];
        }
    }
}

/**
 * Read computed result tile C from a specified bank.
 */
static inline void npu_superscalar_read_tile_c(uint32_t bank,
                                              int M, int N,
                                              int32_t *C, int ldc) {
    volatile int32_t *target_c = (bank == 0) ? NPU_MAT_C_BANK0 : NPU_MAT_C_BANK1;
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < N; j++) {
            C[i * ldc + j] = target_c[i * 16 + j];
        }
    }
}

#endif // NPU_DRIVER_SUPERSCALAR_H

