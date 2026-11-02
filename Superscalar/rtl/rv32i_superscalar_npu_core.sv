// =============================================================================
// RISC-V AI Accelerator - 2-Way Superscalar RV32I Core & NPU Top Integration
// File: rv32i_superscalar_npu_core.sv
//
// Description:
//   Complete, synthesizable top-level integration of the 2-Way In-Order
//   Dual-Issue Superscalar RV32I Processor with the Concurrent Double-Buffered
//   MMIO Neural Processing Unit (NPU) Accelerator.
//
// Pipeline Architecture (5 Dual Stages):
//   1. IF  : 64-bit Dual Fetch + 128-entry BTB + Dynamic Odd-Word Steering
//   2. ID  : Dual Decoders + 4R/2W RegFile + Dynamic Hazard & Issue Unit
//   3. EX  : Dual ALUs + Branch Evaluator + 4x6 Crossbar Forwarding Matrix
//   4. MEM : True Dual-Port Data RAM + MemClass Arbiter + Double-Buffered NPU
//   5. WB  : Dual Commit with Age-Priority (Slot 1 overwrites Slot 0 on WAW)
// =============================================================================

`timescale 1ns / 1ps

module rv32i_superscalar_npu_core #(
    parameter IMEM_WORDS = 1024,
    parameter DMEM_WORDS = 1024
)(
    input  logic        clk,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // Execution & Commit Telemetry Ports
    // -------------------------------------------------------------------------
    output logic [31:0] slot0_wb_pc,
    output logic [31:0] slot1_wb_pc,
    output logic [31:0] slot0_wb_data,
    output logic [31:0] slot1_wb_data,
    output logic [4:0]  slot0_wb_rd,
    output logic [4:0]  slot1_wb_rd,
    output logic        slot0_wb_valid,
    output logic        slot1_wb_valid,

    // -------------------------------------------------------------------------
    // NPU Accelerator Status & Telemetry
    // -------------------------------------------------------------------------
    output logic        npu_busy,
    output logic        npu_done,
    output logic        npu_irq,
    output logic [31:0] npu_cycle_count,
    output logic        npu_active_bank,

    // -------------------------------------------------------------------------
    // Pipeline Diagnostics
    // -------------------------------------------------------------------------
    output logic [1:0]  issue_count_diag,
    output logic        load_use_stall_diag,
    output logic        ex_redirect_diag
);

    // =========================================================================
    // Stage Interconnect & Flow Control Wires
    // =========================================================================

    // Hazard & Flow Control Wires
    logic [1:0]  hazard_issue_count;
    logic        slot0_issue_en;
    logic        slot1_issue_en;
    logic        pc_write;
    logic        if_id_write;
    logic        flush_if_id;
    logic        flush_id_ex;
    logic        pipeline_stall;
    logic        raw_hazard_0_to_1;
    logic        waw_collision;
    logic        load_use_hazard_0;
    logic        load_use_hazard_1;
    logic        mem_class_conflict;

    assign issue_count_diag    = hazard_issue_count;
    assign load_use_stall_diag = load_use_hazard_0 || load_use_hazard_1;

    // Branch / Redirect Wires from EX Stage
    logic        ex_redirect;
    logic [31:0] ex_redirect_target;
    logic        ex_branch_resolved;
    logic [31:0] ex_branch_pc;
    logic [31:0] ex_branch_actual_target;
    logic        ex_branch_actual_taken;

    assign ex_redirect_diag = ex_redirect;

    // =========================================================================
    // 1. INSTRUCTION FETCH (IF) STAGE
    // =========================================================================
    logic [31:0] if_slot0_pc;
    logic [31:0] if_slot1_pc;
    logic [31:0] if_slot0_instr;
    logic [31:0] if_slot1_instr;
    logic        if_slot0_valid;
    logic        if_slot1_valid;
    logic        if_slot0_pred_taken;
    logic [31:0] if_slot0_pred_target;
    logic [31:0] if_current_pc;
    logic [31:0] if_next_pc;
    logic        if_unaligned_fetch;

    assign pipeline_stall = !pc_write;

    fetch_unit_superscalar #(.MEM_WORDS(IMEM_WORDS)) fetch_inst (
        .clk                  (clk),
        .rst                  (rst),
        .stall                (pipeline_stall),
        .issue_count          (hazard_issue_count),
        .redirect_valid       (ex_redirect),
        .redirect_target      (ex_redirect_target),
        .branch_resolved      (ex_branch_resolved),
        .branch_source_pc     (ex_branch_pc),
        .branch_actual_target (ex_branch_actual_target),
        .branch_taken         (ex_branch_actual_taken),
        .slot0_pc             (if_slot0_pc),
        .slot1_pc             (if_slot1_pc),
        .slot0_instr          (if_slot0_instr),
        .slot1_instr          (if_slot1_instr),
        .slot0_valid          (if_slot0_valid),
        .slot1_valid          (if_slot1_valid),
        .slot0_pred_taken     (if_slot0_pred_taken),
        .slot0_pred_target    (if_slot0_pred_target),
        .current_pc           (if_current_pc),
        .next_pc              (if_next_pc),
        .unaligned_fetch      (if_unaligned_fetch)
    );

    // =========================================================================
    // IF/ID DUAL PIPELINE REGISTER
    // =========================================================================
    logic [31:0] id0_pc;
    logic [31:0] id0_instr;
    logic        id0_valid;
    logic        id0_pred_taken;
    logic [31:0] id0_pred_target;

    logic [31:0] id1_pc;
    logic [31:0] id1_instr;
    logic        id1_valid;

    if_id_superscalar_reg if_id_reg_inst (
        .clk                 (clk),
        .rst                 (rst),
        .flush               (flush_if_id || ex_redirect),
        .write_en            (if_id_write),
        .if_slot0_pc         (if_slot0_pc),
        .if_slot0_instr      (if_slot0_instr),
        .if_slot0_valid      (if_slot0_valid),
        .if_slot0_pred_taken (if_slot0_pred_taken),
        .if_slot0_pred_target(if_slot0_pred_target),
        .if_slot1_pc         (if_slot1_pc),
        .if_slot1_instr      (if_slot1_instr),
        .if_slot1_valid      (if_slot1_valid),
        .id_slot0_pc         (id0_pc),
        .id_slot0_instr      (id0_instr),
        .id_slot0_valid      (id0_valid),
        .id_slot0_pred_taken (id0_pred_taken),
        .id_slot0_pred_target(id0_pred_target),
        .id_slot1_pc         (id1_pc),
        .id_slot1_instr      (id1_instr),
        .id_slot1_valid      (id1_valid)
    );

    // =========================================================================
    // 2. INSTRUCTION DECODE (ID) STAGE
    // =========================================================================
    // Slot 0 Controls
    logic [6:0]  id0_opcode, id0_funct7;
    logic [2:0]  id0_funct3;
    logic [4:0]  id0_rd, id0_rs1, id0_rs2;
    logic        id0_uses_rs1, id0_uses_rs2;
    logic        id0_reg_write, id0_mem_read, id0_mem_write, id0_mem_to_reg, id0_alu_src;
    logic        id0_branch, id0_lui, id0_jal, id0_jalr, id0_auipc;
    logic [3:0]  id0_alu_op;
    logic [1:0]  id0_mem_class;
    logic        id0_is_npu_op;
    logic [31:0] id0_imm;

    // Slot 1 Controls
    logic [6:0]  id1_opcode, id1_funct7;
    logic [2:0]  id1_funct3;
    logic [4:0]  id1_rd, id1_rs1, id1_rs2;
    logic        id1_uses_rs1, id1_uses_rs2;
    logic        id1_reg_write, id1_mem_read, id1_mem_write, id1_mem_to_reg, id1_alu_src;
    logic        id1_branch, id1_lui, id1_jal, id1_jalr, id1_auipc;
    logic [3:0]  id1_alu_op;
    logic [1:0]  id1_mem_class;
    logic        id1_is_npu_op;
    logic [31:0] id1_imm;

    control_superscalar ctrl_inst (
        .slot0_instr     (id0_instr),
        .slot0_opcode    (id0_opcode),
        .slot0_funct3    (id0_funct3),
        .slot0_funct7    (id0_funct7),
        .slot0_rd        (id0_rd),
        .slot0_rs1       (id0_rs1),
        .slot0_rs2       (id0_rs2),
        .slot0_uses_rs1  (id0_uses_rs1),
        .slot0_uses_rs2  (id0_uses_rs2),
        .slot0_reg_write (id0_reg_write),
        .slot0_mem_read  (id0_mem_read),
        .slot0_mem_write (id0_mem_write),
        .slot0_mem_to_reg(id0_mem_to_reg),
        .slot0_alu_src   (id0_alu_src),
        .slot0_branch    (id0_branch),
        .slot0_lui       (id0_lui),
        .slot0_jal       (id0_jal),
        .slot0_jalr      (id0_jalr),
        .slot0_auipc     (id0_auipc),
        .slot0_alu_op    (id0_alu_op),
        .slot0_mem_class (id0_mem_class),
        .slot0_is_npu_op (id0_is_npu_op),

        .slot1_instr     (id1_instr),
        .slot1_opcode    (id1_opcode),
        .slot1_funct3    (id1_funct3),
        .slot1_funct7    (id1_funct7),
        .slot1_rd        (id1_rd),
        .slot1_rs1       (id1_rs1),
        .slot1_rs2       (id1_rs2),
        .slot1_uses_rs1  (id1_uses_rs1),
        .slot1_uses_rs2  (id1_uses_rs2),
        .slot1_reg_write (id1_reg_write),
        .slot1_mem_read  (id1_mem_read),
        .slot1_mem_write (id1_mem_write),
        .slot1_mem_to_reg(id1_mem_to_reg),
        .slot1_alu_src   (id1_alu_src),
        .slot1_branch    (id1_branch),
        .slot1_lui       (id1_lui),
        .slot1_jal       (id1_jal),
        .slot1_jalr      (id1_jalr),
        .slot1_auipc     (id1_auipc),
        .slot1_alu_op    (id1_alu_op),
        .slot1_mem_class (id1_mem_class),
        .slot1_is_npu_op (id1_is_npu_op)
    );

    imm_gen_superscalar imm_gen_inst (
        .slot0_instr(id0_instr),
        .slot0_imm  (id0_imm),
        .slot1_instr(id1_instr),
        .slot1_imm  (id1_imm)
    );

    // 4-Read / 2-Write Port Register File
    logic [31:0] rf_rs1_data0, rf_rs2_data0;
    logic [31:0] rf_rs1_data1, rf_rs2_data1;
    logic [31:0] wb0_final_data, wb1_final_data;
    logic [4:0]  wb0_rd, wb1_rd;
    logic        wb0_reg_write, wb1_reg_write;
    logic        wb0_valid, wb1_valid;

    register_file_4r2w regfile_inst (
        .clk      (clk),
        .rst      (rst),
        .rs1_addr0(id0_rs1),
        .rs2_addr0(id0_rs2),
        .rs1_data0(rf_rs1_data0),
        .rs2_data0(rf_rs2_data0),
        .rs1_addr1(id1_rs1),
        .rs2_addr1(id1_rs2),
        .rs1_data1(rf_rs1_data1),
        .rs2_data1(rf_rs2_data1),
        .we0      (wb0_reg_write && wb0_valid),
        .rd_addr0 (wb0_rd),
        .rd_data0 (wb0_final_data),
        .we1      (wb1_reg_write && wb1_valid),
        .rd_addr1 (wb1_rd),
        .rd_data1 (wb1_final_data)
    );

    // Forward declarations from EX stage for load-use hazard detection
    logic        ex0_mem_read, ex1_mem_read;
    logic        ex0_reg_write, ex1_reg_write;
    logic [4:0]  ex0_rd, ex1_rd;

    hazard_unit_superscalar hazard_inst (
        .id_slot0_valid     (id0_valid),
        .id_slot0_rs1       (id0_rs1),
        .id_slot0_rs2       (id0_rs2),
        .id_slot0_rd        (id0_rd),
        .id_slot0_uses_rs1  (id0_uses_rs1),
        .id_slot0_uses_rs2  (id0_uses_rs2),
        .id_slot0_reg_write (id0_reg_write),
        .id_slot0_mem_read  (id0_mem_read),
        .id_slot0_mem_write (id0_mem_write),
        .id_slot0_branch    (id0_branch),
        .id_slot0_jal       (id0_jal),
        .id_slot0_jalr      (id0_jalr),
        .id_slot0_pred_taken(id0_pred_taken),
        .id_slot0_mem_class (id0_mem_class),

        .id_slot1_valid     (id1_valid),
        .id_slot1_rs1       (id1_rs1),
        .id_slot1_rs2       (id1_rs2),
        .id_slot1_rd        (id1_rd),
        .id_slot1_uses_rs1  (id1_uses_rs1),
        .id_slot1_uses_rs2  (id1_uses_rs2),
        .id_slot1_reg_write (id1_reg_write),
        .id_slot1_mem_read  (id1_mem_read),
        .id_slot1_mem_write (id1_mem_write),
        .id_slot1_branch    (id1_branch),
        .id_slot1_jal       (id1_jal),
        .id_slot1_jalr      (id1_jalr),
        .id_slot1_mem_class (id1_mem_class),

        .ex0_mem_read       (ex0_mem_read),
        .ex0_reg_write      (ex0_reg_write),
        .ex0_rd             (ex0_rd),
        .ex1_mem_read       (ex1_mem_read),
        .ex1_reg_write      (ex1_reg_write),
        .ex1_rd             (ex1_rd),

        .ex_redirect        (ex_redirect),

        .issue_count        (hazard_issue_count),
        .slot0_issue_en     (slot0_issue_en),
        .slot1_issue_en     (slot1_issue_en),
        .pc_write           (pc_write),
        .if_id_write        (if_id_write),
        .flush_if_id        (flush_if_id),
        .flush_id_ex        (flush_id_ex),
        .raw_hazard_0_to_1  (raw_hazard_0_to_1),
        .waw_collision      (waw_collision),
        .load_use_hazard_0  (load_use_hazard_0),
        .load_use_hazard_1  (load_use_hazard_1),
        .mem_class_conflict (mem_class_conflict)
    );

    // =========================================================================
    // ID/EX DUAL PIPELINE REGISTER
    // =========================================================================
    // Gated valid signals according to dynamic issue
    logic id0_valid_gated, id1_valid_gated;
    assign id0_valid_gated = id0_valid && slot0_issue_en;
    assign id1_valid_gated = id1_valid && slot1_issue_en;

    // EX Stage Slot 0 Signals
    logic [31:0] ex0_pc, ex0_rs1_data, ex0_rs2_data, ex0_imm;
    logic [4:0]  ex0_rs1, ex0_rs2;
    logic        ex0_uses_rs1, ex0_uses_rs2;
    logic [2:0]  ex0_funct3;
    logic [3:0]  ex0_alu_op;
    logic        ex0_alu_src, ex0_mem_to_reg, ex0_mem_write;
    logic        ex0_branch, ex0_jal, ex0_jalr, ex0_lui, ex0_auipc;
    logic [1:0]  ex0_mem_class;
    logic        ex0_pred_taken;
    logic [31:0] ex0_pred_target;
    logic        ex0_valid;

    // EX Stage Slot 1 Signals
    logic [31:0] ex1_pc, ex1_rs1_data, ex1_rs2_data, ex1_imm;
    logic [4:0]  ex1_rs1, ex1_rs2;
    logic        ex1_uses_rs1, ex1_uses_rs2;
    logic [2:0]  ex1_funct3;
    logic [3:0]  ex1_alu_op;
    logic        ex1_alu_src, ex1_mem_to_reg, ex1_mem_write;
    logic        ex1_branch, ex1_jal, ex1_jalr, ex1_lui, ex1_auipc;
    logic [1:0]  ex1_mem_class;
    logic        ex1_valid;

    id_ex_superscalar_reg id_ex_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .flush          (flush_id_ex || ex_redirect),
        .write_en       (1'b1),

        .id0_pc         (id0_pc),
        .id0_rs1_data   (rf_rs1_data0),
        .id0_rs2_data   (rf_rs2_data0),
        .id0_imm        (id0_imm),
        .id0_rd         (id0_rd),
        .id0_rs1        (id0_rs1),
        .id0_rs2        (id0_rs2),
        .id0_uses_rs1   (id0_uses_rs1),
        .id0_uses_rs2   (id0_uses_rs2),
        .id0_funct3     (id0_funct3),
        .id0_alu_op     (id0_alu_op),
        .id0_alu_src    (id0_alu_src),
        .id0_reg_write  (id0_reg_write),
        .id0_mem_read   (id0_mem_read),
        .id0_mem_write  (id0_mem_write),
        .id0_mem_to_reg (id0_mem_to_reg),
        .id0_branch     (id0_branch),
        .id0_jal        (id0_jal),
        .id0_jalr       (id0_jalr),
        .id0_lui        (id0_lui),
        .id0_auipc      (id0_auipc),
        .id0_mem_class  (id0_mem_class),
        .id0_pred_taken (id0_pred_taken),
        .id0_pred_target(id0_pred_target),
        .id0_valid      (id0_valid_gated),

        .id1_pc         (id1_pc),
        .id1_rs1_data   (rf_rs1_data1),
        .id1_rs2_data   (rf_rs2_data1),
        .id1_imm        (id1_imm),
        .id1_rd         (id1_rd),
        .id1_rs1        (id1_rs1),
        .id1_rs2        (id1_rs2),
        .id1_uses_rs1   (id1_uses_rs1),
        .id1_uses_rs2   (id1_uses_rs2),
        .id1_funct3     (id1_funct3),
        .id1_alu_op     (id1_alu_op),
        .id1_alu_src    (id1_alu_src),
        .id1_reg_write  (id1_reg_write),
        .id1_mem_read   (id1_mem_read),
        .id1_mem_write  (id1_mem_write),
        .id1_mem_to_reg (id1_mem_to_reg),
        .id1_branch     (id1_branch),
        .id1_jal        (id1_jal),
        .id1_jalr       (id1_jalr),
        .id1_lui        (id1_lui),
        .id1_auipc      (id1_auipc),
        .id1_mem_class  (id1_mem_class),
        .id1_valid      (id1_valid_gated),

        .ex0_pc         (ex0_pc),
        .ex0_rs1_data   (ex0_rs1_data),
        .ex0_rs2_data   (ex0_rs2_data),
        .ex0_imm        (ex0_imm),
        .ex0_rd         (ex0_rd),
        .ex0_rs1        (ex0_rs1),
        .ex0_rs2        (ex0_rs2),
        .ex0_uses_rs1   (ex0_uses_rs1),
        .ex0_uses_rs2   (ex0_uses_rs2),
        .ex0_funct3     (ex0_funct3),
        .ex0_alu_op     (ex0_alu_op),
        .ex0_alu_src    (ex0_alu_src),
        .ex0_reg_write  (ex0_reg_write),
        .ex0_mem_read   (ex0_mem_read),
        .ex0_mem_write  (ex0_mem_write),
        .ex0_mem_to_reg (ex0_mem_to_reg),
        .ex0_branch     (ex0_branch),
        .ex0_jal        (ex0_jal),
        .ex0_jalr       (ex0_jalr),
        .ex0_lui        (ex0_lui),
        .ex0_auipc      (ex0_auipc),
        .ex0_mem_class  (ex0_mem_class),
        .ex0_pred_taken (ex0_pred_taken),
        .ex0_pred_target(ex0_pred_target),
        .ex0_valid      (ex0_valid),

        .ex1_pc         (ex1_pc),
        .ex1_rs1_data   (ex1_rs1_data),
        .ex1_rs2_data   (ex1_rs2_data),
        .ex1_imm        (ex1_imm),
        .ex1_rd         (ex1_rd),
        .ex1_rs1        (ex1_rs1),
        .ex1_rs2        (ex1_rs2),
        .ex1_uses_rs1   (ex1_uses_rs1),
        .ex1_uses_rs2   (ex1_uses_rs2),
        .ex1_funct3     (ex1_funct3),
        .ex1_alu_op     (ex1_alu_op),
        .ex1_alu_src    (ex1_alu_src),
        .ex1_reg_write  (ex1_reg_write),
        .ex1_mem_read   (ex1_mem_read),
        .ex1_mem_write  (ex1_mem_write),
        .ex1_mem_to_reg (ex1_mem_to_reg),
        .ex1_branch     (ex1_branch),
        .ex1_jal        (ex1_jal),
        .ex1_jalr       (ex1_jalr),
        .ex1_lui        (ex1_lui),
        .ex1_auipc      (ex1_auipc),
        .ex1_mem_class  (ex1_mem_class),
        .ex1_valid      (ex1_valid)
    );

    // =========================================================================
    // 3. EXECUTION (EX) STAGE & FORWARDING NETWORK
    // =========================================================================
    // Forward declarations from MEM and WB stages
    logic [4:0]  mem0_rd, mem1_rd;
    logic        mem0_reg_write, mem1_reg_write;
    logic        mem0_valid, mem1_valid;
    logic [31:0] mem0_alu_result, mem1_alu_result;

    logic [31:0] forwarded_alu0_a, forwarded_alu0_b, forwarded_store0;
    logic [31:0] forwarded_alu1_a, forwarded_alu1_b, forwarded_store1;
    logic [31:0] ex0_alu_final_result, ex1_alu_final_result;

    forwarding_unit_superscalar fwd_inst (
        .id_ex0_rs1        (ex0_rs1),
        .id_ex0_rs2        (ex0_rs2),
        .id_ex0_uses_rs1   (ex0_uses_rs1),
        .id_ex0_uses_rs2   (ex0_uses_rs2),
        .id_ex0_rs1_data   (ex0_rs1_data),
        .id_ex0_rs2_data   (ex0_rs2_data),

        .id_ex1_rs1        (ex1_rs1),
        .id_ex1_rs2        (ex1_rs2),
        .id_ex1_uses_rs1   (ex1_uses_rs1),
        .id_ex1_uses_rs2   (ex1_uses_rs2),
        .id_ex1_rs1_data   (ex1_rs1_data),
        .id_ex1_rs2_data   (ex1_rs2_data),

        // Intra-cycle EX0 -> EX1 bypass
        .ex0_reg_write     (ex0_reg_write && ex0_valid),
        .ex0_mem_read      (ex0_mem_read),
        .ex0_rd            (ex0_rd),
        .ex0_alu_result    (ex0_alu_final_result),

        // EX/MEM stage inputs
        .ex_mem0_reg_write (mem0_reg_write && mem0_valid),
        .ex_mem0_rd        (mem0_rd),
        .ex_mem0_result    (mem0_alu_result),
        .ex_mem1_reg_write (mem1_reg_write && mem1_valid),
        .ex_mem1_rd        (mem1_rd),
        .ex_mem1_result    (mem1_alu_result),

        // MEM/WB stage inputs
        .mem_wb0_reg_write (wb0_reg_write && wb0_valid),
        .mem_wb0_rd        (wb0_rd),
        .mem_wb0_result    (wb0_final_data),
        .mem_wb1_reg_write (wb1_reg_write && wb1_valid),
        .mem_wb1_rd        (wb1_rd),
        .mem_wb1_result    (wb1_final_data),

        .forwarded_alu0_a  (forwarded_alu0_a),
        .forwarded_alu0_b  (forwarded_alu0_b),
        .forwarded_store0  (forwarded_store0),
        .forwarded_alu1_a  (forwarded_alu1_a),
        .forwarded_alu1_b  (forwarded_alu1_b),
        .forwarded_store1  (forwarded_store1),

        .fwd0_a_src        (),
        .fwd0_b_src        (),
        .fwd1_a_src        (),
        .fwd1_b_src        (),
        .intra_cycle_fwd_a (),
        .intra_cycle_fwd_b ()
    );

    // ALU input multiplexers
    logic [31:0] alu0_in_a, alu0_in_b;
    assign alu0_in_a = ex0_auipc ? ex0_pc : (ex0_lui ? 32'd0 : forwarded_alu0_a);
    assign alu0_in_b = ex0_alu_src ? ex0_imm : forwarded_alu0_b;

    logic [31:0] alu1_in_a, alu1_in_b;
    assign alu1_in_a = ex1_auipc ? ex1_pc : (ex1_lui ? 32'd0 : forwarded_alu1_a);
    assign alu1_in_b = ex1_alu_src ? ex1_imm : forwarded_alu1_b;

    // Dual ALU execution
    logic [31:0] raw_alu0_result, raw_alu1_result;
    logic        raw_alu0_zero, raw_alu1_zero;

    alu_superscalar alu_inst (
        .alu0_a      (alu0_in_a),
        .alu0_b      (alu0_in_b),
        .alu0_op     (ex0_alu_op),
        .alu0_result (raw_alu0_result),
        .alu0_zero   (raw_alu0_zero),

        .alu1_a      (alu1_in_a),
        .alu1_b      (alu1_in_b),
        .alu1_op     (ex1_alu_op),
        .alu1_result (raw_alu1_result),
        .alu1_zero   (raw_alu1_zero)
    );

    // If JAL or JALR, link address is PC + 4
    assign ex0_alu_final_result = (ex0_jal || ex0_jalr) ? (ex0_pc + 32'd4) : raw_alu0_result;
    assign ex1_alu_final_result = (ex1_jal || ex1_jalr) ? (ex1_pc + 32'd4) : raw_alu1_result;

    // Branch and Jump Evaluator
    branch_evaluator branch_eval_inst (
        .branch           (ex0_branch && ex0_valid),
        .jal              (ex0_jal && ex0_valid),
        .jalr             (ex0_jalr && ex0_valid),
        .funct3           (ex0_funct3),
        .pc               (ex0_pc),
        .imm              (ex0_imm),
        .rs1_val          (forwarded_alu0_a),
        .rs2_val          (forwarded_alu0_b),
        .pred_taken       (ex0_pred_taken),
        .pred_target      (ex0_pred_target),
        .actual_taken     (ex_branch_actual_taken),
        .target_pc        (ex_branch_actual_target),
        .ex_redirect      (ex_redirect),
        .redirect_target  (ex_redirect_target),
        .btb_update       (ex_branch_resolved),
        .btb_update_pc    (ex_branch_pc),
        .btb_update_target(),
        .btb_update_taken ()
    );

    // =========================================================================
    // EX/MEM DUAL PIPELINE REGISTER
    // =========================================================================
    logic [31:0] mem0_pc, mem1_pc;
    logic [31:0] mem0_store_data, mem1_store_data;
    logic        mem0_mem_read, mem1_mem_read;
    logic        mem0_mem_write, mem1_mem_write;
    logic        mem0_mem_to_reg, mem1_mem_to_reg;
    logic [2:0]  mem0_funct3, mem1_funct3;
    logic [1:0]  mem0_mem_class, mem1_mem_class;

    ex_mem_superscalar_reg ex_mem_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .flush          (1'b0),
        .write_en       (1'b1),

        .ex0_pc         (ex0_pc),
        .ex0_alu_result (ex0_alu_final_result),
        .ex0_store_data (forwarded_store0),
        .ex0_rd         (ex0_rd),
        .ex0_reg_write  (ex0_reg_write),
        .ex0_mem_read   (ex0_mem_read),
        .ex0_mem_write  (ex0_mem_write),
        .ex0_mem_to_reg (ex0_mem_to_reg),
        .ex0_funct3     (ex0_funct3),
        .ex0_mem_class  (ex0_mem_class),
        .ex0_valid      (ex0_valid),

        .ex1_pc         (ex1_pc),
        .ex1_alu_result (ex1_alu_final_result),
        .ex1_store_data (forwarded_store1),
        .ex1_rd         (ex1_rd),
        .ex1_reg_write  (ex1_reg_write),
        .ex1_mem_read   (ex1_mem_read),
        .ex1_mem_write  (ex1_mem_write),
        .ex1_mem_to_reg (ex1_mem_to_reg),
        .ex1_funct3     (ex1_funct3),
        .ex1_mem_class  (ex1_mem_class),
        .ex1_valid      (ex1_valid),

        .mem0_pc        (mem0_pc),
        .mem0_alu_result(mem0_alu_result),
        .mem0_store_data(mem0_store_data),
        .mem0_rd        (mem0_rd),
        .mem0_reg_write (mem0_reg_write),
        .mem0_mem_read  (mem0_mem_read),
        .mem0_mem_write (mem0_mem_write),
        .mem0_mem_to_reg(mem0_mem_to_reg),
        .mem0_funct3    (mem0_funct3),
        .mem0_mem_class (mem0_mem_class),
        .mem0_valid     (mem0_valid),

        .mem1_pc        (mem1_pc),
        .mem1_alu_result(mem1_alu_result),
        .mem1_store_data(mem1_store_data),
        .mem1_rd        (mem1_rd),
        .mem1_reg_write (mem1_reg_write),
        .mem1_mem_read  (mem1_mem_read),
        .mem1_mem_write (mem1_mem_write),
        .mem1_mem_to_reg(mem1_mem_to_reg),
        .mem1_funct3    (mem1_funct3),
        .mem1_mem_class (mem1_mem_class),
        .mem1_valid     (mem1_valid)
    );

    // =========================================================================
    // 4. MEMORY (MEM) STAGE, ARBITER & NPU COPROCESSOR
    // =========================================================================
    // Dual-Port RAM connections
    logic        ram_write0, ram_write1;
    logic [31:0] ram_addr0, ram_addr1;
    logic [31:0] ram_write_data0, ram_write_data1;
    logic [2:0]  ram_funct3_0, ram_funct3_1;
    logic [31:0] ram_read_data0, ram_read_data1;

    // NPU MMIO connections
    logic        npu_write0, npu_write1;
    logic        npu_read0, npu_read1;
    logic [31:0] npu_addr0, npu_addr1;
    logic [31:0] npu_write_data0, npu_write_data1;
    logic [31:0] npu_read_data0, npu_read_data1;

    // Final multiplexed load data
    logic [31:0] final_read_data0, final_read_data1;

    mem_class_arbiter arbiter_inst (
        .slot0_valid           (mem0_valid),
        .slot0_mem_read        (mem0_mem_read),
        .slot0_mem_write       (mem0_mem_write),
        .slot0_addr            (mem0_alu_result),
        .slot0_write_data      (mem0_store_data),
        .slot0_funct3          (mem0_funct3),
        .slot0_mem_class       (mem0_mem_class),

        .slot1_valid           (mem1_valid),
        .slot1_mem_read        (mem1_mem_read),
        .slot1_mem_write       (mem1_mem_write),
        .slot1_addr            (mem1_alu_result),
        .slot1_write_data      (mem1_store_data),
        .slot1_funct3          (mem1_funct3),
        .slot1_mem_class       (mem1_mem_class),

        .ram_read_data0        (ram_read_data0),
        .ram_read_data1        (ram_read_data1),
        .npu_read_data0        (npu_read_data0),
        .npu_read_data1        (npu_read_data1),

        .ram_write0            (ram_write0),
        .ram_addr0             (ram_addr0),
        .ram_write_data0       (ram_write_data0),
        .ram_funct3_0          (ram_funct3_0),

        .ram_write1            (ram_write1),
        .ram_addr1             (ram_addr1),
        .ram_write_data1       (ram_write_data1),
        .ram_funct3_1          (ram_funct3_1),

        .npu_write0            (npu_write0),
        .npu_read0             (npu_read0),
        .npu_addr0             (npu_addr0),
        .npu_write_data0       (npu_write_data0),

        .npu_write1            (npu_write1),
        .npu_read1             (npu_read1),
        .npu_addr1             (npu_addr1),
        .npu_write_data1       (npu_write_data1),

        .final_read_data0      (final_read_data0),
        .final_read_data1      (final_read_data1),

        .is_npu_addr0          (),
        .is_npu_addr1          (),
        .mem_collision_detected(),
        .store_to_load_fwd     ()
    );

    // True Dual-Port Data RAM (< 0x8000_0000)
    data_memory_dualport #(.MEM_WORDS(DMEM_WORDS)) dmem_inst (
        .clk        (clk),
        .mem_write0 (ram_write0),
        .addr0      (ram_addr0),
        .write_data0(ram_write_data0),
        .funct3_0   (ram_funct3_0),
        .read_data0 (ram_read_data0),

        .mem_write1 (ram_write1),
        .addr1      (ram_addr1),
        .write_data1(ram_write_data1),
        .funct3_1   (ram_funct3_1),
        .read_data1 (ram_read_data1)
    );

    // Concurrent Double-Buffered NPU Coprocessor (>= 0x8000_0000)
    npu_top_superscalar npu_inst (
        .clk             (clk),
        .rst             (rst),
        .we0             (npu_write0),
        .re0             (npu_read0),
        .addr0           (npu_addr0),
        .write_data0     (npu_write_data0),
        .read_data0      (npu_read_data0),

        .we1             (npu_write1),
        .re1             (npu_read1),
        .addr1           (npu_addr1),
        .write_data1     (npu_write_data1),
        .read_data1      (npu_read_data1),

        .irq             (npu_irq),
        .busy            (npu_busy),
        .done            (npu_done),
        .cycle_count_out (npu_cycle_count),
        .active_bank_out (npu_active_bank)
    );

    // =========================================================================
    // MEM/WB DUAL PIPELINE REGISTER
    // =========================================================================
    logic [31:0] wb0_pc, wb1_pc;
    logic [31:0] wb0_alu_result, wb1_alu_result;
    logic [31:0] wb0_read_data, wb1_read_data;
    logic        wb0_mem_to_reg, wb1_mem_to_reg;

    mem_wb_superscalar_reg mem_wb_reg_inst (
        .clk            (clk),
        .rst            (rst),
        .flush          (1'b0),
        .write_en       (1'b1),

        .mem0_pc        (mem0_pc),
        .mem0_alu_result(mem0_alu_result),
        .mem0_read_data (final_read_data0),
        .mem0_rd        (mem0_rd),
        .mem0_reg_write (mem0_reg_write),
        .mem0_mem_to_reg(mem0_mem_to_reg),
        .mem0_valid     (mem0_valid),

        .mem1_pc        (mem1_pc),
        .mem1_alu_result(mem1_alu_result),
        .mem1_read_data (final_read_data1),
        .mem1_rd        (mem1_rd),
        .mem1_reg_write (mem1_reg_write),
        .mem1_mem_to_reg(mem1_mem_to_reg),
        .mem1_valid     (mem1_valid),

        .wb0_pc         (wb0_pc),
        .wb0_alu_result (wb0_alu_result),
        .wb0_read_data  (wb0_read_data),
        .wb0_rd         (wb0_rd),
        .wb0_reg_write  (wb0_reg_write),
        .wb0_mem_to_reg (wb0_mem_to_reg),
        .wb0_valid      (wb0_valid),

        .wb1_pc         (wb1_pc),
        .wb1_alu_result (wb1_alu_result),
        .wb1_read_data  (wb1_read_data),
        .wb1_rd         (wb1_rd),
        .wb1_reg_write  (wb1_reg_write),
        .wb1_mem_to_reg (wb1_mem_to_reg),
        .wb1_valid      (wb1_valid)
    );

    // =========================================================================
    // 5. WRITEBACK (WB) STAGE & COMMIT
    // =========================================================================
    assign wb0_final_data = wb0_mem_to_reg ? wb0_read_data : wb0_alu_result;
    assign wb1_final_data = wb1_mem_to_reg ? wb1_read_data : wb1_alu_result;

    assign slot0_wb_pc    = wb0_pc;
    assign slot0_wb_data  = wb0_final_data;
    assign slot0_wb_rd    = wb0_rd;
    assign slot0_wb_valid = wb0_valid;

    assign slot1_wb_pc    = wb1_pc;
    assign slot1_wb_data  = wb1_final_data;
    assign slot1_wb_rd    = wb1_rd;
    assign slot1_wb_valid = wb1_valid;

endmodule
