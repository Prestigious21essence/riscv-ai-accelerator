// =============================================================================
// RISC-V AI Accelerator - Neural Processing Unit (NPU) Top Module
// File: npu_top.sv
//
// Description:
//   Memory-Mapped I/O (MMIO) hardware accelerator coprocessor for general
//   matrix multiplication (GEMM) and tensor compute.
//   Mapped at physical address space 0x8000_0000 - 0x8000_0FFF.
//
// Memory Map:
//   0x8000_0000: NPU_DIM_M    (R/W, 5 bits, default 16)
//   0x8000_0004: NPU_DIM_K    (R/W, 5 bits, default 16)
//   0x8000_0008: NPU_DIM_N    (R/W, 5 bits, default 16)
//   0x8000_000C: NPU_TRIGGER  (W, write bit 0 = 1 starts computation)
//   0x8000_0010: NPU_RESET    (W, write bit 0 = 1 soft resets FSM/registers)
//   0x8000_0018: NPU_STATUS   (R, bit 0 = done, bit 1 = busy)
//   0x8000_0020: NPU_CYCLES   (R, cycle latency accumulator)
//
//   0x8000_0100 - 0x8000_04FC: mat_a_sram (256x32-bit words, Tile A: i*16 + k)
//   0x8000_0500 - 0x8000_08FC: mat_b_sram (256x32-bit words, Tile B: k*16 + j)
//   0x8000_0900 - 0x8000_0CFC: mat_c_sram (256x32-bit words, Tile C: i*16 + j)
// =============================================================================

`timescale 1ns / 1ps

module npu_top (
    input  logic        clk,
    input  logic        rst,
    input  logic        we,
    input  logic        re,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);

    // =========================================================================
    // Control and Status Registers
    // =========================================================================
    logic [4:0]  dim_m;
    logic [4:0]  dim_k;
    logic [4:0]  dim_n;
    logic        done;
    logic        busy;
    logic [31:0] cycle_count;

    // =========================================================================
    // Internal SRAM Buffers (256 words x 32 bits = 1 KB each)
    // =========================================================================
    logic signed [31:0] mat_a_sram [0:255];
    logic signed [31:0] mat_b_sram [0:255];
    logic signed [31:0] mat_c_sram [0:255];

    // =========================================================================
    // Compute Engine FSM & Datapath Signals
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

    // Internal SRAM indices for computation
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

    assign op_a = mat_a_sram[a_calc_idx];
    assign op_b = mat_b_sram[b_calc_idx];
    assign prod = op_a * op_b;
    assign current_accum = (idx_k == 5'd0 ? 32'sd0 : accum) + prod;

    // =========================================================================
    // MMIO Address Decoding (Word Indices)
    // =========================================================================
    logic is_reg_access;
    logic is_sram_a_access;
    logic is_sram_b_access;
    logic is_sram_c_access;

    logic [11:0] diff_a, diff_b, diff_c;
    assign diff_a = addr[11:0] - 12'h100;
    assign diff_b = addr[11:0] - 12'h500;
    assign diff_c = addr[11:0] - 12'h900;

    logic [7:0] sram_a_word_idx;
    logic [7:0] sram_b_word_idx;
    logic [7:0] sram_c_word_idx;

    assign sram_a_word_idx = diff_a[9:2];
    assign sram_b_word_idx = diff_b[9:2];
    assign sram_c_word_idx = diff_c[9:2];

    assign is_reg_access    = (addr[11:8] == 4'h0);
    assign is_sram_a_access = (addr >= 32'h8000_0100 && addr <= 32'h8000_04FC);
    assign is_sram_b_access = (addr >= 32'h8000_0500 && addr <= 32'h8000_08FC);
    assign is_sram_c_access = (addr >= 32'h8000_0900 && addr <= 32'h8000_0CFC);

    // =========================================================================
    // Combinational Read Multiplexer
    // =========================================================================
    always_comb begin
        read_data = 32'd0;
        if (re) begin
            if (is_reg_access) begin
                case (addr[7:0])
                    8'h00: read_data = {27'd0, dim_m};
                    8'h04: read_data = {27'd0, dim_k};
                    8'h08: read_data = {27'd0, dim_n};
                    8'h18: read_data = {30'd0, busy, done};
                    8'h20: read_data = cycle_count;
                    default: read_data = 32'd0;
                endcase
            end else if (is_sram_a_access) begin
                read_data = mat_a_sram[sram_a_word_idx];
            end else if (is_sram_b_access) begin
                read_data = mat_b_sram[sram_b_word_idx];
            end else if (is_sram_c_access) begin
                read_data = mat_c_sram[sram_c_word_idx];
            end
        end
    end

    // =========================================================================
    // Sequential State Machine & Compute Logic
    // =========================================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= STATE_IDLE;
            dim_m       <= 5'd16;
            dim_k       <= 5'd16;
            dim_n       <= 5'd16;
            done        <= 1'b0;
            busy        <= 1'b0;
            cycle_count <= 32'd0;
            idx_i       <= 5'd0;
            idx_j       <= 5'd0;
            idx_k       <= 5'd0;
            accum       <= 32'sd0;
        end else begin
            // -----------------------------------------------------------------
            // Host Write Handling
            // -----------------------------------------------------------------
            if (we) begin
                if (is_reg_access) begin
                    case (addr[7:0])
                        8'h00: dim_m <= (write_data[4:0] == 5'd0) ? 5'd16 : write_data[4:0];
                        8'h04: dim_k <= (write_data[4:0] == 5'd0) ? 5'd16 : write_data[4:0];
                        8'h08: dim_n <= (write_data[4:0] == 5'd0) ? 5'd16 : write_data[4:0];
                        8'h0C: begin
                            if (write_data[0] && state == STATE_IDLE) begin
                                state       <= STATE_CALC;
                                busy        <= 1'b1;
                                done        <= 1'b0;
                                cycle_count <= 32'd0;
                                idx_i       <= 5'd0;
                                idx_j       <= 5'd0;
                                idx_k       <= 5'd0;
                                accum       <= 32'sd0;
                            end
                        end
                        8'h10: begin
                            if (write_data[0]) begin
                                // Soft reset
                                state       <= STATE_IDLE;
                                done        <= 1'b0;
                                busy        <= 1'b0;
                                cycle_count <= 32'd0;
                                idx_i       <= 5'd0;
                                idx_j       <= 5'd0;
                                idx_k       <= 5'd0;
                                accum       <= 32'sd0;
                            end
                        end
                        default: ;
                    endcase
                end else if (is_sram_a_access) begin
                    mat_a_sram[sram_a_word_idx] <= write_data;
                end else if (is_sram_b_access) begin
                    mat_b_sram[sram_b_word_idx] <= write_data;
                end else if (is_sram_c_access) begin
                    mat_c_sram[sram_c_word_idx] <= write_data;
                end
            end

            // -----------------------------------------------------------------
            // Compute Engine FSM
            // -----------------------------------------------------------------
            case (state)
                STATE_IDLE: begin
                    // Waiting for trigger write
                end

                STATE_CALC: begin
                    if (!(we && is_reg_access && (addr[7:0] == 8'h10) && write_data[0])) begin
                        cycle_count <= cycle_count + 32'd1;

                        if (idx_k == (dim_k - 5'd1)) begin
                            // Inner product for element C[i, j] finished
                            mat_c_sram[c_calc_idx] <= current_accum;
                            accum                  <= 32'sd0;
                            idx_k                  <= 5'd0;

                            if (idx_j == (dim_n - 5'd1)) begin
                                idx_j <= 5'd0;
                                if (idx_i == (dim_m - 5'd1)) begin
                                    // All M*N elements calculated
                                    state <= STATE_DONE;
                                    done  <= 1'b1;
                                    busy  <= 1'b0;
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
                end

                STATE_DONE: begin
                    // Calculation completed, status holds until next trigger or reset
                    if (we && is_reg_access && addr[7:0] == 8'h0C && write_data[0]) begin
                        state       <= STATE_CALC;
                        busy        <= 1'b1;
                        done        <= 1'b0;
                        cycle_count <= 32'd0;
                        idx_i       <= 5'd0;
                        idx_j       <= 5'd0;
                        idx_k       <= 5'd0;
                        accum       <= 32'sd0;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
