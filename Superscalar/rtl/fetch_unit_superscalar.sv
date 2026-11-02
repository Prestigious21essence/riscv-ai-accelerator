// =============================================================================
// Module: fetch_unit_superscalar
// Description: Complete Instruction Fetch Unit for 2-Way Superscalar Core.
//              - Integrates pc_superscalar, instruction_memory_64, and btb_128.
//              - Implements dynamic unaligned word steering logic:
//                  * Aligned (pc[2]==0): slot0 <= word0, slot1 <= word1, both valid
//                  * Unaligned (pc[2]==1): slot0 <= word1, slot1 <= NOP, only slot0 valid
//              - Directs speculative branch redirects from BTB.
//              - Feeds Slot 0 and Slot 1 to IF/ID pipeline registers.
// =============================================================================

`timescale 1ns/1ps

module fetch_unit_superscalar #(
    parameter MEM_WORDS = 1024
)(
    input  logic        clk,
    input  logic        rst,

    // Pipeline Control & Issue Status
    input  logic        stall,               // 1 to freeze fetch
    input  logic [1:0]  issue_count,         // Number of instructions issued from ID (0, 1, or 2)

    // Architectural Branch / Jump Redirect from EX Stage
    input  logic        redirect_valid,      // Target override from EX (mispredict or taken branch/jump)
    input  logic [31:0] redirect_target,     // Correct target address

    // BTB Update Interface from EX Stage
    input  logic        branch_resolved,     // 1 if an instruction in EX was a branch
    input  logic [31:0] branch_source_pc,    // Address of the branch instruction
    input  logic [31:0] branch_actual_target,// Evaluated branch destination
    input  logic        branch_taken,        // 1 if branch was taken, 0 if fell through

    // Outputs to IF/ID Pipeline Register
    output logic [31:0] slot0_pc,
    output logic [31:0] slot1_pc,
    output logic [31:0] slot0_instr,
    output logic [31:0] slot1_instr,
    output logic        slot0_valid,
    output logic        slot1_valid,
    output logic        slot0_pred_taken,
    output logic [31:0] slot0_pred_target,

    // Telemetry / Status Outputs
    output logic [31:0] current_pc,
    output logic [31:0] next_pc,
    output logic        unaligned_fetch
);

    // Internal wires
    logic [31:0] pc;
    logic [31:0] pc_plus4;
    logic [31:0] pc_plus8;
    logic [31:0] raw_word0;
    logic [31:0] raw_word1;
    logic [63:0] raw_data_64;

    logic        btb_pred_taken;
    logic [31:0] btb_pred_target;
    logic        slot0_is_branch;

    assign current_pc      = pc;
    assign unaligned_fetch = pc[2];

    // -------------------------------------------------------------------------
    // 1. 64-bit Dual-Word Instruction Memory
    // -------------------------------------------------------------------------
    instruction_memory_64 #(.MEM_WORDS(MEM_WORDS)) imem_64 (
        .addr        (pc),
        .raw_word0   (raw_word0),
        .raw_word1   (raw_word1),
        .raw_data_64 (raw_data_64)
    );

    // -------------------------------------------------------------------------
    // 2. 128-entry Branch Target Buffer (BTB) & Prediction Logic
    // -------------------------------------------------------------------------
    btb_128 btb_inst (
        .clk           (clk),
        .rst           (rst),
        .query_pc      (pc),
        .predict_taken (btb_pred_taken),
        .predict_target(btb_pred_target),
        .update_en     (branch_resolved),
        .update_pc     (branch_source_pc),
        .update_target (branch_actual_target),
        .actual_taken  (branch_taken)
    );

    // Detect if Slot 0 instruction is a control-transfer instruction:
    // - Branch (opcode 7'b1100011 = 0x63: BEQ, BNE, BLT, BGE, BLTU, BGEU)
    // - JAL    (opcode 7'b1101111 = 0x6F: Jump and Link)
    // - JALR   (opcode 7'b1100111 = 0x67: Jump and Link Register)
    wire [6:0] slot0_raw_opcode = (!pc[2]) ? raw_word0[6:0] : raw_word1[6:0];
    assign slot0_is_branch      = (slot0_raw_opcode == 7'b1100011);
    wire       slot0_is_jal     = (slot0_raw_opcode == 7'b1101111);
    wire       slot0_is_jalr    = (slot0_raw_opcode == 7'b1100111);
    wire       slot0_is_ctrl    = slot0_is_branch || slot0_is_jal || slot0_is_jalr;

    assign slot0_pred_taken     = slot0_is_branch && btb_pred_taken;
    assign slot0_pred_target    = btb_pred_target;

    // -------------------------------------------------------------------------
    // 3. Dynamic Unaligned Word Steering & Dead-Path Squashing Logic
    // -------------------------------------------------------------------------
    always_comb begin
        if (!pc[2]) begin
            // 64-bit aligned: Slot 0 gets raw_word0
            slot0_instr = raw_word0;
            slot0_pc    = pc;
            slot0_valid = 1'b1;

            if (slot0_is_ctrl) begin
                // Any Control Transfer (Branch, JAL, JALR) in Slot 0 closes the dual-issue packet!
                // Slot 1 (pc + 4) is in the branch/jump shadow and is SQUASHED with hardware NOP!
                slot1_instr = 32'h00000013; // Padded with hardware NOP: addi x0, x0, 0
                slot1_pc    = pc + 32'd4;
                slot1_valid = 1'b0;         // Invalidated
            end else begin
                // Non-control: both words valid in program order
                slot1_instr = raw_word1;
                slot1_pc    = pc + 32'd4;
                slot1_valid = 1'b1;
            end
        end else begin
            // Unaligned (pc[2] == 1): branch/jump landed on odd word.
            // raw_word0 belongs to previous block -> discarded.
            // raw_word1 is target instruction -> steered to Slot 0.
            slot0_instr = raw_word1;
            slot1_instr = 32'h00000013; // Padded with NOP: addi x0, x0, 0
            slot0_pc    = pc;
            slot1_pc    = pc + 32'd4;
            slot0_valid = 1'b1;
            slot1_valid = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 4. Program Counter Generation Unit
    // -------------------------------------------------------------------------
    pc_superscalar pc_inst (
        .clk               (clk),
        .rst               (rst),
        .stall             (stall),
        .issue_count       (issue_count),
        .redirect_valid    (redirect_valid),
        .redirect_target   (redirect_target),
        .btb_predict_taken (slot0_pred_taken),
        .btb_predict_target(slot0_pred_target),
        .pc                (pc),
        .next_pc           (next_pc),
        .pc_plus4          (pc_plus4),
        .pc_plus8          (pc_plus8)
    );

endmodule

