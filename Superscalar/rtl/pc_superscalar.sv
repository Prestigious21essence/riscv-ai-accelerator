// =============================================================================
// Module: pc_superscalar
// Description: Program Counter and Next-PC Generation Unit for 2-Way Superscalar
//              RV32I Core.
//              - Supports dual-instruction advancement (+8), single-instruction
//                advancement (+4), pipeline freeze (stall), speculative branch
//                redirection (BTB), and architectural branch/jump resolution.
// =============================================================================

`timescale 1ns/1ps

module pc_superscalar (
    input  logic        clk,
    input  logic        rst,

    // Pipeline control
    input  logic        stall,               // 1 to freeze PC (load-use or structural stall)
    input  logic [1:0]  issue_count,         // 0: stall, 1: issue 1 instr (+4), 2: issue 2 instrs (+8)

    // Branch / Jump Redirect from Execution Stage (Architectural Truth)
    input  logic        redirect_valid,      // Asserted when branch taken or JAL/JALR target resolved
    input  logic [31:0] redirect_target,     // Target PC from EX stage

    // Speculative Branch Prediction from Frontend BTB
    input  logic        btb_predict_taken,   // Asserted if BTB predicts branch taken in IF stage
    input  logic [31:0] btb_predict_target,  // Predicted target PC

    // Outputs
    output logic [31:0] pc,                  // Current Program Counter
    output logic [31:0] next_pc,             // Next PC evaluated combinationally
    output logic [31:0] pc_plus4,            // pc + 4
    output logic [31:0] pc_plus8             // pc + 8
);

    assign pc_plus4 = pc + 32'd4;
    assign pc_plus8 = pc + 32'd8;

    // Next PC selection logic with priority arbitration:
    // 1. Architectural EX redirect (highest priority: mispredict recovery or branch/jump target)
    // 2. Speculative IF BTB prediction
    // 3. Pipeline stall (freeze)
    // 4. Dual-issue advance (+8)
    // 5. Single-issue advance (+4)
    always_comb begin
        if (redirect_valid) begin
            next_pc = redirect_target;
        end else if (btb_predict_taken) begin
            next_pc = btb_predict_target;
        end else if (stall) begin
            next_pc = pc;
        end else begin
            case (issue_count)
                2'd2:    next_pc = pc[2] ? pc_plus4 : pc_plus8;
                2'd1:    next_pc = pc_plus4;
                default: next_pc = pc;
            endcase
        end
    end

    // Sequential PC register
    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= 32'h00000000;
        end else begin
            pc <= next_pc;
        end
    end

endmodule

