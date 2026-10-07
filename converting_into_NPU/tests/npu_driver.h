/**
 * =============================================================================
 * RISC-V Neural Processing Unit (NPU) Accelerator Software Driver
 * File: npu_driver.h
 *
 * Description:
 *   High-level C driver for configuring, streaming tiles to, triggering,
 *   and polling the memory-mapped NPU coprocessor mapped at 0x80000000.
 * =============================================================================
 */

#ifndef NPU_DRIVER_H
#define NPU_DRIVER_H

#include <stdint.h>

#define NPU_BASE        0x80000000U
#define NPU_DIM_M       ((volatile uint32_t*)(NPU_BASE + 0x00))
#define NPU_DIM_K       ((volatile uint32_t*)(NPU_BASE + 0x04))
#define NPU_DIM_N       ((volatile uint32_t*)(NPU_BASE + 0x08))
#define NPU_TRIGGER     ((volatile uint32_t*)(NPU_BASE + 0x0C))
#define NPU_RESET       ((volatile uint32_t*)(NPU_BASE + 0x10))
#define NPU_STATUS      ((volatile uint32_t*)(NPU_BASE + 0x18))
#define NPU_CYCLES      ((volatile uint32_t*)(NPU_BASE + 0x20))

#define NPU_MAT_A       ((volatile int32_t*)(NPU_BASE + 0x100))
#define NPU_MAT_B       ((volatile int32_t*)(NPU_BASE + 0x500))
#define NPU_MAT_C       ((volatile int32_t*)(NPU_BASE + 0x900))

/**
 * Reset NPU internal state machine and cycle counters.
 */
static inline void npu_reset(void) {
    *NPU_RESET = 1;
}

/**
 * Configure matrix dimensions for the upcoming hardware GEMM operation.
 * Dimensions must be between 1 and 16.
 */
static inline void npu_set_dims(uint32_t M, uint32_t K, uint32_t N) {
    *NPU_DIM_M = M;
    *NPU_DIM_K = K;
    *NPU_DIM_N = N;
}

/**
 * Check if the NPU calculation is completed.
 * Returns 1 if done, 0 if busy or idle.
 */
static inline int npu_is_done(void) {
    return (*NPU_STATUS & 0x1);
}

/**
 * Read the total execution cycles taken by the last NPU matrix compute run.
 */
static inline uint32_t npu_get_cycles(void) {
    return *NPU_CYCLES;
}

/**
 * Synchronous tile GEMM: C = A * B
 * Matrix A: M rows x K cols, leading dimension lda
 * Matrix B: K rows x N cols, leading dimension ldb
 * Matrix C: M rows x N cols, leading dimension ldc
 * Tile dimensions M, K, N <= 16.
 */
static inline void npu_gemm_tile(int M, int K, int N,
                                 const int32_t *A, int lda,
                                 const int32_t *B, int ldb,
                                 int32_t *C, int ldc) {
    // 1. Program matrix dimensions
    *NPU_DIM_M = (uint32_t)M;
    *NPU_DIM_K = (uint32_t)K;
    *NPU_DIM_N = (uint32_t)N;

    // 2. Stream Tile A into on-chip SRAM buffer (16-word pitch)
    for (int i = 0; i < M; i++) {
        for (int k = 0; k < K; k++) {
            NPU_MAT_A[i * 16 + k] = A[i * lda + k];
        }
    }

    // 3. Stream Tile B into on-chip SRAM buffer (16-word pitch)
    for (int k = 0; k < K; k++) {
        for (int j = 0; j < N; j++) {
            NPU_MAT_B[k * 16 + j] = B[k * ldb + j];
        }
    }

    // 4. Trigger hardware matrix computation
    *NPU_TRIGGER = 1;

    // 5. Hardware polling loop (spin until done bit is asserted)
    while (!(*NPU_STATUS & 0x1));

    // 6. Extract result tile C from on-chip SRAM buffer
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < N; j++) {
            C[i * ldc + j] = NPU_MAT_C[i * 16 + j];
        }
    }
}

/**
 * Tiled general matrix multiplication for arbitrary matrix sizes (multiples of 16).
 * Computes C = A * B by tiling into 16x16 blocks.
 */
static inline void npu_gemm_tiled(int size, const int32_t *A, const int32_t *B, int32_t *C) {
    const int TILE = 16;
    int num_tiles = size / TILE;

    for (int ti = 0; ti < num_tiles; ti++) {
        for (int tj = 0; tj < num_tiles; tj++) {
            // Initialize destination tile C to zero
            for (int i = 0; i < TILE; i++) {
                for (int j = 0; j < TILE; j++) {
                    C[(ti * TILE + i) * size + (tj * TILE + j)] = 0;
                }
            }

            // Accumulate partial tile products
            for (int tk = 0; tk < num_tiles; tk++) {
                int32_t temp_c[16 * 16];
                npu_gemm_tile(TILE, TILE, TILE,
                              &A[(ti * TILE) * size + (tk * TILE)], size,
                              &B[(tk * TILE) * size + (tj * TILE)], size,
                              temp_c, 16);

                for (int i = 0; i < TILE; i++) {
                    for (int j = 0; j < TILE; j++) {
                        C[(ti * TILE + i) * size + (tj * TILE + j)] += temp_c[i * 16 + j];
                    }
                }
            }
        }
    }
}

#endif // NPU_DRIVER_H
