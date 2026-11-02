// =============================================================================
// Module: hazard_unit_superscalar
// Description: Dynamic Hazard Detection & Issue Control Unit for 2-Way
//              Superscalar RV32I Processor.
//              - Implements hardware hazard_scan() deciding issue_count (0, 1, or 2)
//              - Detects Intra-Packet RAW hazards (Slot 0 writes -> Slot 1 reads)
//              - Resolves Control hazards (JAL/JALR ends window; predicted branch
//                squashes Slot 1)
//              - Resolves Structural Memory hazards via MemClass conflict rules:
//                  * Two stores conflict (single write port)
//                  * Two loads to same NPU bank conflict
//                  * Store + Bank Load do NOT conflict (different ports)
//                  * Bank A Load + Bank B Load do NOT conflict
//                  * ALU (MEM_NONE) never conflicts with memory
//              - Detects Inter-Stage Load-Use hazards from EX stage:
//                  * Dependency on Slot 0 -> Full pipeline stall (m = 0)
//                  * Dependency on Slot 1 -> Slot 0 issues (m = 1), Slot 1 stalls
//              - Manages EX branch misprediction flushes (flush IF/ID and ID/EX)
// =============================================================================

`timescale 1ns/1ps

module hazard_unit_superscalar (
    // -------------------------------------------------------------------------
    // ID Stage Instruction Fields - Slot 0
    // -------------------------------------------------------------------------
    input  logic        id_slot0_valid,
    input  logic [4:0]  id_slot0_rs1,
    input  logic [4:0]  id_slot0_rs2,
    input  logic [4:0]  id_slot0_rd,
    input  logic        id_slot0_uses_rs1,
    input  logic        id_slot0_uses_rs2,
    input  logic        id_slot0_reg_write,
    input  logic        id_slot0_mem_read,
    input  logic        id_slot0_mem_write,
    input  logic        id_slot0_branch,
    input  logic        id_slot0_jal,
    input  logic        id_slot0_jalr,
    input  logic        id_slot0_pred_taken, // BTB predicted taken in IF
    input  logic [1:0]  id_slot0_mem_class,

    // -------------------------------------------------------------------------
    // ID Stage Instruction Fields - Slot 1
    // -------------------------------------------------------------------------
    input  logic        id_slot1_valid,
    input  logic [4:0]  id_slot1_rs1,
    input  logic [4:0]  id_slot1_rs2,
    input  logic [4:0]  id_slot1_rd,
    input  logic        id_slot1_uses_rs1,
    input  logic        id_slot1_uses_rs2,
    input  logic        id_slot1_reg_write,
    input  logic        id_slot1_mem_read,
    input  logic        id_slot1_mem_write,
    input  logic        id_slot1_branch,
    input  logic        id_slot1_jal,
    input  logic        id_slot1_jalr,
    input  logic [1:0]  id_slot1_mem_class,

    // -------------------------------------------------------------------------
    // EX Stage Fields (for Load-Use Hazard Detection)
    // -------------------------------------------------------------------------
    input  logic        ex0_mem_read,
    input  logic        ex0_reg_write,
    input  logic [4:0]  ex0_rd,

    input  logic        ex1_mem_read,
    input  logic        ex1_reg_write,
    input  logic [4:0]  ex1_rd,

    // -------------------------------------------------------------------------
    // Control Hazard Input (from EX Branch/Jump Resolution)
    // -------------------------------------------------------------------------
    input  logic        ex_redirect,         // Asserted on branch mispredict or taken branch/jump

    // -------------------------------------------------------------------------
    // Outputs: Pipeline Issue & Flow Controls
    // -------------------------------------------------------------------------
    output logic [1:0]  issue_count,         // 0: stall, 1: issue Slot 0 only, 2: dual issue
    output logic        slot0_issue_en,      // Enable Slot 0 dispatch to EX
    output logic        slot1_issue_en,      // Enable Slot 1 dispatch to EX
    output logic        pc_write,            // Enable PC update
    output logic        if_id_write,         // Enable IF/ID register update
    output logic        flush_if_id,         // Synchronous flush of IF/ID register
    output logic        flush_id_ex,         // Synchronous flush of ID/EX register (bubble insertion)

    // Telemetry Hazard Status Flags
    output logic        raw_hazard_0_to_1,
    output logic        waw_collision,
    output logic        load_use_hazard_0,
    output logic        load_use_hazard_1,
    output logic        mem_class_conflict
);

    // -------------------------------------------------------------------------
    // 1. Intra-Packet RAW Hazard Detection (Slot 0 -> Slot 1)
    // -------------------------------------------------------------------------
    // True data dependency: Slot 1 reads the register that Slot 0 writes.
    // Register x0 is never a hazard.
    assign raw_hazard_0_to_1 = id_slot0_valid && id_slot1_valid &&
                               id_slot0_reg_write && (id_slot0_rd != 5'd0) &&
                               ((id_slot1_uses_rs1 && (id_slot1_rs1 == id_slot0_rd)) ||
                                (id_slot1_uses_rs2 && (id_slot1_rs2 == id_slot0_rd)));

    // -------------------------------------------------------------------------
    // 2. Intra-Packet Output Hazard (WAW Collision)
    // -------------------------------------------------------------------------
    assign waw_collision = id_slot0_valid && id_slot1_valid &&
                           id_slot0_reg_write && id_slot1_reg_write &&
                           (id_slot0_rd == id_slot1_rd) && (id_slot0_rd != 5'd0);

    // -------------------------------------------------------------------------
    // 3. Intra-Packet Memory Class Structural Conflict
    // -------------------------------------------------------------------------
    // Conflict occurs if both instructions access the SAME non-zero MemClass:
    // - Two stores (2'b01 == 2'b01) conflict
    // - Two loads to Bank A (2'b10 == 2'b10) conflict
    // - Two loads to Bank B (2'b11 == 2'b11) conflict
    // Non-conflicts:
    // - Store (2'b01) and Bank Load (2'b10 or 2'b11) -> different classes!
    // - Bank A (2'b10) and Bank B (2'b11) -> different classes!
    // - ALU / Branch (2'b00) never conflicts with any class.
    assign mem_class_conflict = id_slot0_valid && id_slot1_valid &&
                                (id_slot0_mem_class != 2'b00) &&
                                (id_slot0_mem_class == id_slot1_mem_class);

    // -------------------------------------------------------------------------
    // 4. Inter-Stage Load-Use Hazard Detection (EX Stage Load -> ID Stage)
    // -------------------------------------------------------------------------
    // Check if Slot 0 in ID reads from an in-flight EX load
    wire ex0_load_to_id0 = ex0_mem_read && (ex0_rd != 5'd0) &&
                           ((id_slot0_uses_rs1 && (id_slot0_rs1 == ex0_rd)) ||
                            (id_slot0_uses_rs2 && (id_slot0_rs2 == ex0_rd)));

    wire ex1_load_to_id0 = ex1_mem_read && (ex1_rd != 5'd0) &&
                           ((id_slot0_uses_rs1 && (id_slot0_rs1 == ex1_rd)) ||
                            (id_slot0_uses_rs2 && (id_slot0_rs2 == ex1_rd)));

    assign load_use_hazard_0 = id_slot0_valid && (ex0_load_to_id0 || ex1_load_to_id0);

    // Check if Slot 1 in ID reads from an in-flight EX load
    wire ex0_load_to_id1 = ex0_mem_read && (ex0_rd != 5'd0) &&
                           ((id_slot1_uses_rs1 && (id_slot1_rs1 == ex0_rd)) ||
                            (id_slot1_uses_rs2 && (id_slot1_rs2 == ex0_rd)));

    wire ex1_load_to_id1 = ex1_mem_read && (ex1_rd != 5'd0) &&
                           ((id_slot1_uses_rs1 && (id_slot1_rs1 == ex1_rd)) ||
                            (id_slot1_uses_rs2 && (id_slot1_rs2 == ex1_rd)));

    assign load_use_hazard_1 = id_slot1_valid && (ex0_load_to_id1 || ex1_load_to_id1);

    // -------------------------------------------------------------------------
    // 5. Intra-Packet Issue Decision Logic (hazard_scan)
    // -------------------------------------------------------------------------
    // Can Slot 1 issue alongside Slot 0?
    // Slot 1 is blocked if:
    // 1. Slot 1 is invalid (e.g., from unaligned fetch)
    // 2. Intra-packet RAW dependency exists
    // 3. Slot 0 is an unconditional jump (JAL or JALR)
    // 4. Slot 0 is a branch that is predicted taken by BTB
    // 5. Memory port structural conflict exists
    // 6. Slot 1 has an unresolved load-use dependency
    logic slot1_can_coissue;
    assign slot1_can_coissue = id_slot1_valid &&
                               !raw_hazard_0_to_1 &&
                               !id_slot0_jal &&
                               !id_slot0_jalr &&
                               !id_slot0_branch &&
                               !mem_class_conflict &&
                               !load_use_hazard_1;

    // -------------------------------------------------------------------------
    // 6. Pipeline Flow Control & Arbitration
    // -------------------------------------------------------------------------
    always_comb begin
        if (ex_redirect) begin
            // Highest priority: Control Redirect from EX stage (mispredict or jump)
            // Redirect takes effect on PC; pipeline stages IF and ID are flushed.
            pc_write       = 1'b1;
            if_id_write    = 1'b1;
            flush_if_id    = 1'b1;
            flush_id_ex    = 1'b1;
            issue_count    = 2'd0;
            slot0_issue_en = 1'b0;
            slot1_issue_en = 1'b0;
        end else if (load_use_hazard_0) begin
            // Full Load-Use Stall: Slot 0 cannot execute until load completes.
            // Freeze PC and IF/ID; insert bubble into ID/EX.
            pc_write       = 1'b0;
            if_id_write    = 1'b0;
            flush_if_id    = 1'b0;
            flush_id_ex    = 1'b1;
            issue_count    = 2'd0;
            slot0_issue_en = 1'b0;
            slot1_issue_en = 1'b0;
        end else if (slot1_can_coissue) begin
            // Dual-Issue: Both Slot 0 and Slot 1 advance to EX stage.
            // PC advances by +8 on next clock edge.
            pc_write       = 1'b1;
            if_id_write    = 1'b1;
            flush_if_id    = 1'b0;
            flush_id_ex    = 1'b0;
            issue_count    = 2'd2;
            slot0_issue_en = 1'b1;
            slot1_issue_en = 1'b1;
        end else begin
            // Single-Issue: Only Slot 0 advances to EX stage.
            // Slot 1 is deferred/held; PC advances by +4.
            pc_write       = 1'b1;
            if_id_write    = 1'b1;
            flush_if_id    = 1'b0;
            flush_id_ex    = 1'b0;
            issue_count    = 2'd1;
            slot0_issue_en = 1'b1;
            slot1_issue_en = 1'b0;
        end
    end

endmodule

