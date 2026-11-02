// =============================================================================
// Module: branch_evaluator
// Description: Branch & Jump Evaluation Unit for 2-Way Superscalar RV32I Core.
//              - Evaluates branch conditions in EX stage (Slot 0).
//              - Computes branch target (pc + imm) and JALR target ((rs1 + imm) & ~1).
//              - Compares actual branch resolution with BTB speculative prediction.
//              - Generates ex_redirect and redirect_target on mispredictions.
//              - Emits training signals for the 128-entry BTB.
// =============================================================================

`timescale 1ns/1ps

module branch_evaluator (
    // Control Flags
    input  logic        branch,
    input  logic        jal,
    input  logic        jalr,
    input  logic [2:0]  funct3,

    // Operands and Program Counter
    input  logic [31:0] pc,
    input  logic [31:0] imm,
    input  logic [31:0] rs1_val,
    input  logic [31:0] rs2_val,

    // Speculative Frontend BTB Prediction Inputs
    input  logic        pred_taken,
    input  logic [31:0] pred_target,

    // Resolution & Flow Control Outputs
    output logic        actual_taken,
    output logic [31:0] target_pc,
    output logic        ex_redirect,
    output logic [31:0] redirect_target,

    // BTB Training Outputs
    output logic        btb_update,
    output logic [31:0] btb_update_pc,
    output logic [31:0] btb_update_target,
    output logic        btb_update_taken
);

    // -------------------------------------------------------------------------
    // 1. Branch Condition Evaluation
    // -------------------------------------------------------------------------
    logic condition_met;

    always_comb begin
        case (funct3)
            3'b000:  condition_met = (rs1_val == rs2_val);                               // BEQ
            3'b001:  condition_met = (rs1_val != rs2_val);                               // BNE
            3'b100:  condition_met = ($signed(rs1_val) < $signed(rs2_val));              // BLT
            3'b101:  condition_met = ($signed(rs1_val) >= $signed(rs2_val));             // BGE
            3'b110:  condition_met = (rs1_val < rs2_val);                                // BLTU
            3'b111:  condition_met = (rs1_val >= rs2_val);                               // BGEU
            default: condition_met = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // 2. Target Address Calculation
    // -------------------------------------------------------------------------
    always_comb begin
        if (jalr) begin
            // JALR: target is (rs1 + imm) with least significant bit cleared
            target_pc = (rs1_val + imm) & ~32'd1;
        end else begin
            // Branch or JAL: PC-relative target
            target_pc = pc + imm;
        end
    end

    // Actual branch/jump direction
    assign actual_taken = (branch && condition_met) || jal || jalr;

    // -------------------------------------------------------------------------
    // 3. Speculative Misprediction Detection & Redirect Generation
    // -------------------------------------------------------------------------
    always_comb begin
        ex_redirect     = 1'b0;
        redirect_target = 32'd0;

        if (branch) begin
            if (actual_taken != pred_taken) begin
                // Direction misprediction (e.g., predicted taken, actually not taken, or vice versa)
                ex_redirect     = 1'b1;
                redirect_target = actual_taken ? target_pc : (pc + 32'd4);
            end else if (actual_taken && (target_pc != pred_target)) begin
                // Target address mismatch despite matching direction
                ex_redirect     = 1'b1;
                redirect_target = target_pc;
            end
        end else if (jal) begin
            if (!pred_taken || (target_pc != pred_target)) begin
                ex_redirect     = 1'b1;
                redirect_target = target_pc;
            end
        end else if (jalr) begin
            // JALR depends on register value; always redirects to calculated target
            ex_redirect     = 1'b1;
            redirect_target = target_pc;
        end
    end

    // -------------------------------------------------------------------------
    // 4. BTB Update Telemetry
    // -------------------------------------------------------------------------
    assign btb_update        = branch || jal;
    assign btb_update_pc     = pc;
    assign btb_update_target = target_pc;
    assign btb_update_taken  = actual_taken;

endmodule

