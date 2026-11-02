// =============================================================================
// Module: forwarding_unit_superscalar
// Description: Full 4x6 Crossbar Forwarding Matrix with Intra-Cycle ALU0->ALU1
//              Bypass for 2-Way Superscalar RV32I Core.
//              - Resolves data hazards for 4 execution operands concurrently:
//                  * Pipe 0: rs1 (alu0_a), rs2 (alu0_b / store_data0)
//                  * Pipe 1: rs1 (alu1_a), rs2 (alu1_b / store_data1)
//              - Program-order priority:
//                  1. Intra-cycle EX0 -> EX1 bypass (youngest in current cycle)
//                  2. EX/MEM Slot 1 (youngest in EX/MEM stage)
//                  3. EX/MEM Slot 0 (older in EX/MEM stage)
//                  4. MEM/WB Slot 1 (youngest in MEM/WB stage)
//                  5. MEM/WB Slot 0 (older in MEM/WB stage)
//                  6. Register file read data (no hazard)
//              - Register x0 is never forwarded.
// =============================================================================

`timescale 1ns/1ps

module forwarding_unit_superscalar (
    // -------------------------------------------------------------------------
    // ID/EX Stage Source Register Identifiers & Read Data
    // -------------------------------------------------------------------------
    input  logic [4:0]  id_ex0_rs1,
    input  logic [4:0]  id_ex0_rs2,
    input  logic        id_ex0_uses_rs1,
    input  logic        id_ex0_uses_rs2,
    input  logic [31:0] id_ex0_rs1_data,
    input  logic [31:0] id_ex0_rs2_data,

    input  logic [4:0]  id_ex1_rs1,
    input  logic [4:0]  id_ex1_rs2,
    input  logic        id_ex1_uses_rs1,
    input  logic        id_ex1_uses_rs2,
    input  logic [31:0] id_ex1_rs1_data,
    input  logic [31:0] id_ex1_rs2_data,

    // -------------------------------------------------------------------------
    // Intra-Cycle EX0 Stage Bypass Inputs (Pipe 0 -> Pipe 1)
    // -------------------------------------------------------------------------
    input  logic        ex0_reg_write,
    input  logic        ex0_mem_read,
    input  logic [4:0]  ex0_rd,
    input  logic [31:0] ex0_alu_result,

    // -------------------------------------------------------------------------
    // EX/MEM Stage Forwarding Inputs
    // -------------------------------------------------------------------------
    input  logic        ex_mem0_reg_write,
    input  logic [4:0]  ex_mem0_rd,
    input  logic [31:0] ex_mem0_result,

    input  logic        ex_mem1_reg_write,
    input  logic [4:0]  ex_mem1_rd,
    input  logic [31:0] ex_mem1_result,

    // -------------------------------------------------------------------------
    // MEM/WB Stage Forwarding Inputs
    // -------------------------------------------------------------------------
    input  logic        mem_wb0_reg_write,
    input  logic [4:0]  mem_wb0_rd,
    input  logic [31:0] mem_wb0_result,

    input  logic        mem_wb1_reg_write,
    input  logic [4:0]  mem_wb1_rd,
    input  logic [31:0] mem_wb1_result,

    // -------------------------------------------------------------------------
    // Forwarded Outputs for Execution ALUs and Store Data
    // -------------------------------------------------------------------------
    output logic [31:0] forwarded_alu0_a,
    output logic [31:0] forwarded_alu0_b,
    output logic [31:0] forwarded_store0,

    output logic [31:0] forwarded_alu1_a,
    output logic [31:0] forwarded_alu1_b,
    output logic [31:0] forwarded_store1,

    // -------------------------------------------------------------------------
    // Forwarding Telemetry & Source Selection Flags (for debugging/visualizer)
    // 0: REGFILE, 1: MEM_WB0, 2: MEM_WB1, 3: EX_MEM0, 4: EX_MEM1, 5: INTRA_EX0
    // -------------------------------------------------------------------------
    output logic [2:0]  fwd0_a_src,
    output logic [2:0]  fwd0_b_src,
    output logic [2:0]  fwd1_a_src,
    output logic [2:0]  fwd1_b_src,
    output logic        intra_cycle_fwd_a,
    output logic        intra_cycle_fwd_b
);

    localparam FWD_REGFILE   = 3'd0;
    localparam FWD_MEM_WB0   = 3'd1;
    localparam FWD_MEM_WB1   = 3'd2;
    localparam FWD_EX_MEM0   = 3'd3;
    localparam FWD_EX_MEM1   = 3'd4;
    localparam FWD_INTRA_EX0 = 3'd5;

    // =========================================================================
    // Pipe 0 - Operand A (rs1) Forwarding Logic
    // Priority: EX/MEM1 -> EX/MEM0 -> MEM/WB1 -> MEM/WB0 -> Register File
    // =========================================================================
    always_comb begin
        if (id_ex0_uses_rs1 && (id_ex0_rs1 != 5'd0)) begin
            if (ex_mem1_reg_write && (ex_mem1_rd == id_ex0_rs1)) begin
                forwarded_alu0_a = ex_mem1_result;
                fwd0_a_src       = FWD_EX_MEM1;
            end else if (ex_mem0_reg_write && (ex_mem0_rd == id_ex0_rs1)) begin
                forwarded_alu0_a = ex_mem0_result;
                fwd0_a_src       = FWD_EX_MEM0;
            end else if (mem_wb1_reg_write && (mem_wb1_rd == id_ex0_rs1)) begin
                forwarded_alu0_a = mem_wb1_result;
                fwd0_a_src       = FWD_MEM_WB1;
            end else if (mem_wb0_reg_write && (mem_wb0_rd == id_ex0_rs1)) begin
                forwarded_alu0_a = mem_wb0_result;
                fwd0_a_src       = FWD_MEM_WB0;
            end else begin
                forwarded_alu0_a = id_ex0_rs1_data;
                fwd0_a_src       = FWD_REGFILE;
            end
        end else begin
            forwarded_alu0_a = id_ex0_rs1_data;
            fwd0_a_src       = FWD_REGFILE;
        end
    end

    // =========================================================================
    // Pipe 0 - Operand B (rs2) Forwarding Logic
    // Forwarded to both ALU0 input B and Store Data 0
    // =========================================================================
    always_comb begin
        if (id_ex0_uses_rs2 && (id_ex0_rs2 != 5'd0)) begin
            if (ex_mem1_reg_write && (ex_mem1_rd == id_ex0_rs2)) begin
                forwarded_alu0_b = ex_mem1_result;
                forwarded_store0 = ex_mem1_result;
                fwd0_b_src       = FWD_EX_MEM1;
            end else if (ex_mem0_reg_write && (ex_mem0_rd == id_ex0_rs2)) begin
                forwarded_alu0_b = ex_mem0_result;
                forwarded_store0 = ex_mem0_result;
                fwd0_b_src       = FWD_EX_MEM0;
            end else if (mem_wb1_reg_write && (mem_wb1_rd == id_ex0_rs2)) begin
                forwarded_alu0_b = mem_wb1_result;
                forwarded_store0 = mem_wb1_result;
                fwd0_b_src       = FWD_MEM_WB1;
            end else if (mem_wb0_reg_write && (mem_wb0_rd == id_ex0_rs2)) begin
                forwarded_alu0_b = mem_wb0_result;
                forwarded_store0 = mem_wb0_result;
                fwd0_b_src       = FWD_MEM_WB0;
            end else begin
                forwarded_alu0_b = id_ex0_rs2_data;
                forwarded_store0 = id_ex0_rs2_data;
                fwd0_b_src       = FWD_REGFILE;
            end
        end else begin
            forwarded_alu0_b = id_ex0_rs2_data;
            forwarded_store0 = id_ex0_rs2_data;
            fwd0_b_src       = FWD_REGFILE;
        end
    end

    // =========================================================================
    // Pipe 1 - Operand A (rs1) Forwarding Logic
    // Priority: Intra-cycle EX0 -> EX/MEM1 -> EX/MEM0 -> MEM/WB1 -> MEM/WB0 -> Reg
    // =========================================================================
    always_comb begin
        intra_cycle_fwd_a = 1'b0;
        if (id_ex1_uses_rs1 && (id_ex1_rs1 != 5'd0)) begin
            // 1. Intra-cycle ALU0 -> ALU1 bypass (Slot 0 is older in current cycle)
            if (ex0_reg_write && !ex0_mem_read && (ex0_rd == id_ex1_rs1)) begin
                forwarded_alu1_a  = ex0_alu_result;
                fwd1_a_src        = FWD_INTRA_EX0;
                intra_cycle_fwd_a = 1'b1;
            end else if (ex_mem1_reg_write && (ex_mem1_rd == id_ex1_rs1)) begin
                forwarded_alu1_a  = ex_mem1_result;
                fwd1_a_src        = FWD_EX_MEM1;
            end else if (ex_mem0_reg_write && (ex_mem0_rd == id_ex1_rs1)) begin
                forwarded_alu1_a  = ex_mem0_result;
                fwd1_a_src        = FWD_EX_MEM0;
            end else if (mem_wb1_reg_write && (mem_wb1_rd == id_ex1_rs1)) begin
                forwarded_alu1_a  = mem_wb1_result;
                fwd1_a_src        = FWD_MEM_WB1;
            end else if (mem_wb0_reg_write && (mem_wb0_rd == id_ex1_rs1)) begin
                forwarded_alu1_a  = mem_wb0_result;
                fwd1_a_src        = FWD_MEM_WB0;
            end else begin
                forwarded_alu1_a  = id_ex1_rs1_data;
                fwd1_a_src        = FWD_REGFILE;
            end
        end else begin
            forwarded_alu1_a  = id_ex1_rs1_data;
            fwd1_a_src        = FWD_REGFILE;
        end
    end

    // =========================================================================
    // Pipe 1 - Operand B (rs2) Forwarding Logic
    // Forwarded to both ALU1 input B and Store Data 1
    // =========================================================================
    always_comb begin
        intra_cycle_fwd_b = 1'b0;
        if (id_ex1_uses_rs2 && (id_ex1_rs2 != 5'd0)) begin
            // 1. Intra-cycle ALU0 -> ALU1 bypass (Slot 0 is older in current cycle)
            if (ex0_reg_write && !ex0_mem_read && (ex0_rd == id_ex1_rs2)) begin
                forwarded_alu1_b  = ex0_alu_result;
                forwarded_store1  = ex0_alu_result;
                fwd1_b_src        = FWD_INTRA_EX0;
                intra_cycle_fwd_b = 1'b1;
            end else if (ex_mem1_reg_write && (ex_mem1_rd == id_ex1_rs2)) begin
                forwarded_alu1_b  = ex_mem1_result;
                forwarded_store1  = ex_mem1_result;
                fwd1_b_src        = FWD_EX_MEM1;
            end else if (ex_mem0_reg_write && (ex_mem0_rd == id_ex1_rs2)) begin
                forwarded_alu1_b  = ex_mem0_result;
                forwarded_store1  = ex_mem0_result;
                fwd1_b_src        = FWD_EX_MEM0;
            end else if (mem_wb1_reg_write && (mem_wb1_rd == id_ex1_rs2)) begin
                forwarded_alu1_b  = mem_wb1_result;
                forwarded_store1  = mem_wb1_result;
                fwd1_b_src        = FWD_MEM_WB1;
            end else if (mem_wb0_reg_write && (mem_wb0_rd == id_ex1_rs2)) begin
                forwarded_alu1_b  = mem_wb0_result;
                forwarded_store1  = mem_wb0_result;
                fwd1_b_src        = FWD_MEM_WB0;
            end else begin
                forwarded_alu1_b  = id_ex1_rs2_data;
                forwarded_store1  = id_ex1_rs2_data;
                fwd1_b_src        = FWD_REGFILE;
            end
        end else begin
            forwarded_alu1_b  = id_ex1_rs2_data;
            forwarded_store1  = id_ex1_rs2_data;
            fwd1_b_src        = FWD_REGFILE;
        end
    end

endmodule

