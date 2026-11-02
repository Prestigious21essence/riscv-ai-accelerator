// =============================================================================
// RISC-V AI Accelerator - Superscalar Neural Processing Unit (NPU) Top Module
// File: npu_top_superscalar.sv
//
// Description:
//   Advanced 2-Way Concurrent, Double-Buffered Memory-Mapped I/O (MMIO)
//   NPU Accelerator Coprocessor for General Matrix Multiplication (GEMM).
//
// Key Superscalar Enhancements:
//   1. Ping-Pong Double-Buffered SRAMs:
//      - Dual 1 KB SRAM banks for Tile A (mat_a_sram[0..1][0..255])
//      - Dual 1 KB SRAM banks for Tile B (mat_b_sram[0..1][0..255])
//      - Dual 1 KB SRAM banks for Tile C (mat_c_sram[0..1][0..255])
//      - Enables 100% latency hiding: while MAC array computes on active_bank,
//        CPU/DMA streams next tile into shadow_bank (~active_bank).
//   2. Concurrent Dual-Channel Access:
//      - Independent Port 0 and Port 1 MMIO interfaces.
//      - Allows simultaneous multi-bank streaming (e.g. load_a on Port 0
//        and load_b on Port 1 in the exact same clock cycle).
//   3. Non-Blocking 4-Entry Command & Dispatch FIFO:
//      - CPU enqueues commands (START_GEMM, SWAP_BANKS, AUTO_SWAP) and
//        immediately resumes execution without spin-lock polling.
//      - Hardware automatically dispatches next command when idle.
//
// Memory Map (Base Address >= 0x8000_0000):
//   0x8000_0000: NPU_DIM_M      (R/W, 5 bits, default 16)
//   0x8000_0004: NPU_DIM_K      (R/W, 5 bits, default 16)
//   0x8000_0008: NPU_DIM_N      (R/W, 5 bits, default 16)
//   0x8000_000C: NPU_TRIGGER    (W, write bit 0 = 1 enqueues/starts GEMM)
//   0x8000_0010: NPU_RESET      (W, write bit 0 = 1 soft resets NPU)
//   0x8000_0014: NPU_CMD_FIFO   (W, pushes 32-bit command word)
//   0x8000_0018: NPU_STATUS     (R: bit 0=done, bit 1=busy, bit 2=fifo_full,
//                                   bit 3=fifo_empty, bit 4=active_bank, bit 5=irq)
//   0x8000_001C: NPU_CTRL       (R/W: bit 0=manual swap, bit 1=auto_shadow_mode,
//                                     bit 2=auto_swap_on_done)
//   0x8000_0020: NPU_CYCLES     (R: cycle latency accumulator)
//   0x8000_0024: NPU_FIFO_COUNT (R: current FIFO depth 0..4)
//
//   0x8000_0100 - 0x8000_04FC: mat_a_sram (256x32-bit words)
//   0x8000_0500 - 0x8000_08FC: mat_b_sram (256x32-bit words)
//   0x8000_0900 - 0x8000_0CFC: mat_c_sram (256x32-bit words)
//   Explicit bank selection via addr[12] (0 = Bank 0, 1 = Bank 1), or
//   automatic shadow streaming via auto_shadow_mode.
// =============================================================================

`timescale 1ns / 1ps

module npu_top_superscalar (
    input  logic        clk,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // Port 0 Interface (Slot 0 / Pipe 0)
    // -------------------------------------------------------------------------
    input  logic        we0,
    input  logic        re0,
    input  logic [31:0] addr0,
    input  logic [31:0] write_data0,
    output logic [31:0] read_data0,

    // -------------------------------------------------------------------------
    // Port 1 Interface (Slot 1 / Pipe 1)
    // -------------------------------------------------------------------------
    input  logic        we1,
    input  logic        re1,
    input  logic [31:0] addr1,
    input  logic [31:0] write_data1,
    output logic [31:0] read_data1,

    // -------------------------------------------------------------------------
    // Hardware Interrupt & Status Telemetry
    // -------------------------------------------------------------------------
    output logic        irq,
    output logic        busy,
    output logic        done,
    output logic [31:0] cycle_count_out,
    output logic        active_bank_out
);

    // =========================================================================
    // Command Opcodes
    // =========================================================================
    localparam [3:0] CMD_NOP                  = 4'd0;
    localparam [3:0] CMD_START_GEMM           = 4'd1;
    localparam [3:0] CMD_SWAP_BANKS           = 4'd2;
    localparam [3:0] CMD_START_GEMM_AUTO_SWAP = 4'd3;
    localparam [3:0] CMD_SOFT_RESET           = 4'd4;

    // =========================================================================
    // Control, Status & Configuration Registers
    // =========================================================================
    logic [4:0]  dim_m;
    logic [4:0]  dim_k;
    logic [4:0]  dim_n;
    logic        fsm_done;
    logic        fsm_busy;
    logic        irq_reg;
    logic [31:0] cycle_count;

    logic        active_bank;        // Compute engine operates on active_bank
    logic        auto_shadow_mode;   // 1: MMIO writes to A/B steer to ~active_bank
    logic        auto_swap_on_done;  // 1: automatically flip active_bank on GEMM finish

    assign busy            = fsm_busy;
    assign done            = fsm_done;
    assign irq             = irq_reg;
    assign cycle_count_out = cycle_count;
    assign active_bank_out = active_bank;

    // =========================================================================
    // Ping-Pong Double-Buffered SRAMs (2 x 1 KB each)
    // =========================================================================
    // Bank 0 and Bank 1 for Matrix A, B, and C
    logic signed [31:0] mat_a_sram [0:1][0:255];
    logic signed [31:0] mat_b_sram [0:1][0:255];
    logic signed [31:0] mat_c_sram [0:1][0:255];

    // =========================================================================
    // 4-Entry Non-Blocking Command & Dispatch FIFO
    // =========================================================================
    logic [31:0] cmd_fifo [0:3];
    logic [1:0]  fifo_wr_ptr;
    logic [1:0]  fifo_rd_ptr;
    logic [2:0]  fifo_count;
    logic        fifo_full;
    logic        fifo_empty;

    assign fifo_full  = (fifo_count == 3'd4);
    assign fifo_empty = (fifo_count == 3'd0);

    // =========================================================================
    // Compute Engine FSM & Datapath
    // =========================================================================
    typedef enum logic [1:0] {
        STATE_IDLE = 2'd0,
        STATE_CALC = 2'd1,
        STATE_DONE = 2'd2
    } state_t;

    state_t state;

    logic [4:0] idx_i;
    logic [4:0] idx_j;
    logic [4:0] idx_k;
    logic signed [31:0] accum;
    logic       current_cmd_auto_swap;

    // Internal SRAM addressing during calculation
    logic [7:0] a_calc_idx;
    logic [7:0] b_calc_idx;
    logic [7:0] c_calc_idx;

    assign a_calc_idx = {idx_i[3:0], idx_k[3:0]}; // (idx_i * 16) + idx_k
    assign b_calc_idx = {idx_k[3:0], idx_j[3:0]}; // (idx_k * 16) + idx_j
    assign c_calc_idx = {idx_i[3:0], idx_j[3:0]}; // (idx_i * 16) + idx_j

    logic signed [31:0] op_a;
    logic signed [31:0] op_b;
    logic signed [31:0] prod;
    logic signed [31:0] current_accum;

    assign op_a = mat_a_sram[active_bank][a_calc_idx];
    assign op_b = mat_b_sram[active_bank][b_calc_idx];
    assign prod = op_a * op_b;
    assign current_accum = (idx_k == 5'd0 ? 32'sd0 : accum) + prod;

    // =========================================================================
    // MMIO Address Decoding Functions
    // =========================================================================
    function automatic logic is_reg(input logic [31:0] a);
        return (a[11:8] == 4'h0 && a[12] == 1'b0);
    endfunction

    function automatic logic is_sram_a(input logic [31:0] a);
        return (a[11:8] >= 4'h1 && a[11:8] <= 4'h4);
    endfunction

    function automatic logic is_sram_b(input logic [31:0] a);
        return (a[11:8] >= 4'h5 && a[11:8] <= 4'h8);
    endfunction

    function automatic logic is_sram_c(input logic [31:0] a);
        return (a[11:8] >= 4'h9 && a[11:8] <= 4'hC);
    endfunction

    function automatic logic resolve_bank(input logic [31:0] a, input logic is_c);
        if (a[12]) begin
            return 1'b1; // Explicit Bank 1 access
        end else if (auto_shadow_mode) begin
            if (!is_c) begin
                return ~active_bank; // Streaming to/from shadow bank
            end else begin
                return active_bank;  // Reading completed result bank
            end
        end else begin
            return 1'b0; // Default Bank 0
        end
    endfunction

    // Word indices within SRAM
    wire [11:0] diff_a0 = addr0[11:0] - 12'h100;
    wire [11:0] diff_b0 = addr0[11:0] - 12'h500;
    wire [11:0] diff_c0 = addr0[11:0] - 12'h900;

    wire [7:0] sram_a_idx0 = diff_a0[9:2];
    wire [7:0] sram_b_idx0 = diff_b0[9:2];
    wire [7:0] sram_c_idx0 = diff_c0[9:2];

    wire [11:0] diff_a1 = addr1[11:0] - 12'h100;
    wire [11:0] diff_b1 = addr1[11:0] - 12'h500;
    wire [11:0] diff_c1 = addr1[11:0] - 12'h900;

    wire [7:0] sram_a_idx1 = diff_a1[9:2];
    wire [7:0] sram_b_idx1 = diff_b1[9:2];
    wire [7:0] sram_c_idx1 = diff_c1[9:2];

    wire bank_a0 = resolve_bank(addr0, 1'b0);
    wire bank_b0 = resolve_bank(addr0, 1'b0);
    wire bank_c0 = resolve_bank(addr0, 1'b1);

    wire bank_a1 = resolve_bank(addr1, 1'b0);
    wire bank_b1 = resolve_bank(addr1, 1'b0);
    wire bank_c1 = resolve_bank(addr1, 1'b1);

    // =========================================================================
    // Combinational Read Multiplexers (Dual Ports)
    // =========================================================================
    always_comb begin
        read_data0 = 32'd0;
        if (re0) begin
            if (is_reg(addr0)) begin
                case (addr0[7:0])
                    8'h00: read_data0 = {27'd0, dim_m};
                    8'h04: read_data0 = {27'd0, dim_k};
                    8'h08: read_data0 = {27'd0, dim_n};
                    8'h18: read_data0 = {26'd0, irq_reg, active_bank, fifo_empty, fifo_full, fsm_busy, fsm_done};
                    8'h1C: read_data0 = {29'd0, auto_swap_on_done, auto_shadow_mode, active_bank};
                    8'h20: read_data0 = cycle_count;
                    8'h24: read_data0 = {29'd0, fifo_count};
                    default: read_data0 = 32'd0;
                endcase
            end else if (is_sram_a(addr0)) begin
                read_data0 = mat_a_sram[bank_a0][sram_a_idx0];
            end else if (is_sram_b(addr0)) begin
                read_data0 = mat_b_sram[bank_b0][sram_b_idx0];
            end else if (is_sram_c(addr0)) begin
                read_data0 = mat_c_sram[bank_c0][sram_c_idx0];
            end
        end
    end

    always_comb begin
        read_data1 = 32'd0;
        if (re1) begin
            if (is_reg(addr1)) begin
                case (addr1[7:0])
                    8'h00: read_data1 = {27'd0, dim_m};
                    8'h04: read_data1 = {27'd0, dim_k};
                    8'h08: read_data1 = {27'd0, dim_n};
                    8'h18: read_data1 = {26'd0, irq_reg, active_bank, fifo_empty, fifo_full, fsm_busy, fsm_done};
                    8'h1C: read_data1 = {29'd0, auto_swap_on_done, auto_shadow_mode, active_bank};
                    8'h20: read_data1 = cycle_count;
                    8'h24: read_data1 = {29'd0, fifo_count};
                    default: read_data1 = 32'd0;
                endcase
            end else if (is_sram_a(addr1)) begin
                read_data1 = mat_a_sram[bank_a1][sram_a_idx1];
            end else if (is_sram_b(addr1)) begin
                read_data1 = mat_b_sram[bank_b1][sram_b_idx1];
            end else if (is_sram_c(addr1)) begin
                read_data1 = mat_c_sram[bank_c1][sram_c_idx1];
            end
        end
    end

    // =========================================================================
    // Command FIFO Push / Pop Logic
    // =========================================================================
    logic fifo_push;
    logic [31:0] fifo_push_data;
    logic fifo_pop;
    logic [31:0] next_cmd;

    always_comb begin
        fifo_push      = 1'b0;
        fifo_push_data = 32'd0;

        // Port 1 write has age-priority over Port 0
        if (we1 && is_reg(addr1)) begin
            if (addr1[7:0] == 8'h14) begin
                fifo_push      = !fifo_full;
                fifo_push_data = write_data1;
            end else if (addr1[7:0] == 8'h0C && write_data1[0]) begin
                fifo_push      = !fifo_full;
                fifo_push_data = {28'd0, CMD_START_GEMM};
            end
        end else if (we0 && is_reg(addr0)) begin
            if (addr0[7:0] == 8'h14) begin
                fifo_push      = !fifo_full;
                fifo_push_data = write_data0;
            end else if (addr0[7:0] == 8'h0C && write_data0[0]) begin
                fifo_push      = !fifo_full;
                fifo_push_data = {28'd0, CMD_START_GEMM};
            end
        end
    end

    assign next_cmd = cmd_fifo[fifo_rd_ptr];
    assign fifo_pop = (state == STATE_IDLE && !fifo_empty);

    // =========================================================================
    // Main Sequential Block: Registers, SRAMs, FIFO, and Compute Engine
    // =========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state                 <= STATE_IDLE;
            dim_m                 <= 5'd16;
            dim_k                 <= 5'd16;
            dim_n                 <= 5'd16;
            fsm_done              <= 1'b0;
            fsm_busy              <= 1'b0;
            irq_reg               <= 1'b0;
            cycle_count           <= 32'd0;
            active_bank           <= 1'b0;
            auto_shadow_mode      <= 1'b0;
            auto_swap_on_done     <= 1'b0;
            fifo_wr_ptr           <= 2'd0;
            fifo_rd_ptr           <= 2'd0;
            fifo_count            <= 3'd0;
            idx_i                 <= 5'd0;
            idx_j                 <= 5'd0;
            idx_k                 <= 5'd0;
            accum                 <= 32'sd0;
            current_cmd_auto_swap <= 1'b0;
        end else begin
            // -----------------------------------------------------------------
            // 1. Host Register Writes (Port 0 processed, Port 1 overwrites on collision)
            // -----------------------------------------------------------------
            if (we0 && is_reg(addr0)) begin
                case (addr0[7:0])
                    8'h00: dim_m <= (write_data0[4:0] == 5'd0) ? 5'd16 : write_data0[4:0];
                    8'h04: dim_k <= (write_data0[4:0] == 5'd0) ? 5'd16 : write_data0[4:0];
                    8'h08: dim_n <= (write_data0[4:0] == 5'd0) ? 5'd16 : write_data0[4:0];
                    8'h1C: begin
                        if (write_data0[0]) active_bank       <= ~active_bank;
                        auto_shadow_mode  <= write_data0[1];
                        auto_swap_on_done <= write_data0[2];
                    end
                    default: ;
                endcase
            end

            if (we1 && is_reg(addr1)) begin
                case (addr1[7:0])
                    8'h00: dim_m <= (write_data1[4:0] == 5'd0) ? 5'd16 : write_data1[4:0];
                    8'h04: dim_k <= (write_data1[4:0] == 5'd0) ? 5'd16 : write_data1[4:0];
                    8'h08: dim_n <= (write_data1[4:0] == 5'd0) ? 5'd16 : write_data1[4:0];
                    8'h1C: begin
                        if (write_data1[0]) active_bank       <= ~active_bank;
                        auto_shadow_mode  <= write_data1[1];
                        auto_swap_on_done <= write_data1[2];
                    end
                    default: ;
                endcase
            end

            // -----------------------------------------------------------------
            // 2. Dual SRAM Host Writes (Multi-Bank Concurrent Streaming)
            // -----------------------------------------------------------------
            // Port 0 SRAM writes
            if (we0) begin
                if (is_sram_a(addr0))      mat_a_sram[bank_a0][sram_a_idx0] <= write_data0;
                else if (is_sram_b(addr0)) mat_b_sram[bank_b0][sram_b_idx0] <= write_data0;
                else if (is_sram_c(addr0)) mat_c_sram[bank_c0][sram_c_idx0] <= write_data0;
            end

            // Port 1 SRAM writes (Port 1 overwrites Port 0 if writing exact same bank & word)
            if (we1) begin
                if (is_sram_a(addr1))      mat_a_sram[bank_a1][sram_a_idx1] <= write_data1;
                else if (is_sram_b(addr1)) mat_b_sram[bank_b1][sram_b_idx1] <= write_data1;
                else if (is_sram_c(addr1)) mat_c_sram[bank_c1][sram_c_idx1] <= write_data1;
            end

            // -----------------------------------------------------------------
            // 3. FIFO Push & Pop Management
            // -----------------------------------------------------------------
            if (fifo_push && !fifo_pop) begin
                cmd_fifo[fifo_wr_ptr] <= fifo_push_data;
                fifo_wr_ptr           <= fifo_wr_ptr + 2'd1;
                fifo_count            <= fifo_count + 3'd1;
            end else if (!fifo_push && fifo_pop) begin
                fifo_rd_ptr           <= fifo_rd_ptr + 2'd1;
                fifo_count            <= fifo_count - 3'd1;
            end else if (fifo_push && fifo_pop) begin
                cmd_fifo[fifo_wr_ptr] <= fifo_push_data;
                fifo_wr_ptr           <= fifo_wr_ptr + 2'd1;
                fifo_rd_ptr           <= fifo_rd_ptr + 2'd1;
            end

            // -----------------------------------------------------------------
            // 4. Compute Engine FSM & Autonomous Dispatch
            // -----------------------------------------------------------------
            case (state)
                STATE_IDLE: begin
                    if (!fifo_empty) begin
                        case (next_cmd[3:0])
                            CMD_START_GEMM: begin
                                state                 <= STATE_CALC;
                                fsm_busy              <= 1'b1;
                                fsm_done              <= 1'b0;
                                irq_reg               <= 1'b0;
                                cycle_count           <= 32'd0;
                                idx_i                 <= 5'd0;
                                idx_j                 <= 5'd0;
                                idx_k                 <= 5'd0;
                                accum                 <= 32'sd0;
                                current_cmd_auto_swap <= 1'b0;
                            end

                            CMD_START_GEMM_AUTO_SWAP: begin
                                state                 <= STATE_CALC;
                                fsm_busy              <= 1'b1;
                                fsm_done              <= 1'b0;
                                irq_reg               <= 1'b0;
                                cycle_count           <= 32'd0;
                                idx_i                 <= 5'd0;
                                idx_j                 <= 5'd0;
                                idx_k                 <= 5'd0;
                                accum                 <= 32'sd0;
                                current_cmd_auto_swap <= 1'b1;
                            end

                            CMD_SWAP_BANKS: begin
                                active_bank <= ~active_bank;
                            end

                            CMD_SOFT_RESET: begin
                                fsm_busy    <= 1'b0;
                                fsm_done    <= 1'b0;
                                irq_reg     <= 1'b0;
                                cycle_count <= 32'd0;
                                active_bank <= 1'b0;
                            end

                            default: ;
                        endcase
                    end
                end

                STATE_CALC: begin
                    cycle_count <= cycle_count + 32'd1;

                    if (idx_k == (dim_k - 5'd1)) begin
                        // Element C[i, j] finished accumulation
                        mat_c_sram[active_bank][c_calc_idx] <= current_accum;
                        accum                               <= 32'sd0;
                        idx_k                               <= 5'd0;

                        if (idx_j == (dim_n - 5'd1)) begin
                            idx_j <= 5'd0;
                            if (idx_i == (dim_m - 5'd1)) begin
                                // Full M x N matrix multiplication complete!
                                state    <= STATE_DONE;
                                fsm_done <= 1'b1;
                                fsm_busy <= 1'b0;
                                irq_reg  <= 1'b1;

                                if (auto_swap_on_done || current_cmd_auto_swap) begin
                                    active_bank <= ~active_bank;
                                end
                            end else begin
                                idx_i <= idx_i + 5'd1;
                            end
                        end else begin
                            idx_j <= idx_j + 5'd1;
                        end
                    end else begin
                        accum <= current_accum;
                        idx_k <= idx_k + 5'd1;
                    end
                end

                STATE_DONE: begin
                    // Auto-transition to IDLE if next command is waiting in FIFO
                    if (!fifo_empty) begin
                        state    <= STATE_IDLE;
                        fsm_done <= 1'b0;
                    end
                end

                default: state <= STATE_IDLE;
            endcase

            // Soft reset handling from host write
            if ((we0 && is_reg(addr0) && addr0[7:0] == 8'h10 && write_data0[0]) ||
                (we1 && is_reg(addr1) && addr1[7:0] == 8'h10 && write_data1[0])) begin
                state             <= STATE_IDLE;
                fsm_done          <= 1'b0;
                fsm_busy          <= 1'b0;
                irq_reg           <= 1'b0;
                cycle_count       <= 32'd0;
                fifo_wr_ptr       <= 2'd0;
                fifo_rd_ptr       <= 2'd0;
                fifo_count        <= 3'd0;
                active_bank       <= 1'b0;
                auto_shadow_mode  <= 1'b0;
                auto_swap_on_done <= 1'b0;
            end
        end
    end

endmodule
