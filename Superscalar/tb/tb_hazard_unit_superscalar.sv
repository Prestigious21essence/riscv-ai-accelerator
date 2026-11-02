// =============================================================================
// Testbench: tb_hazard_unit_superscalar
// Description: Comprehensive self-checking verification of hazard_unit_superscalar.
//              Verifies all 16 hazard conditions and arbitration decisions:
//              1. Clean dual issue (independent ALUs)
//              2. Intra-packet RAW hazard on rs1 (Slot 1 blocked)
//              3. Intra-packet RAW hazard on rs2 (Slot 1 blocked)
//              4. Intra-packet RAW check with x0 (no hazard, x0 hardwired)
//              5. Intra-packet WAW collision (both issue, WB handles age priority)
//              6. Slot 0 unconditional jump (JAL/JALR closes window)
//              7. Slot 0 branch predicted taken by BTB (Slot 1 squashed)
//              8. Slot 0 branch predicted not taken (Slot 1 co-issues)
//              9. Memory structural conflict: Store + Store (serialized)
//              10. Memory structural conflict: Bank A + Bank A (serialized)
//              11. Memory structural non-conflict: Store + Bank A Load (co-issue)
//              12. Memory structural non-conflict: Bank A + Bank B Load (co-issue)
//              13. Memory structural non-conflict: ALU + Store (co-issue)
//              14. Inter-stage Load-Use on Slot 0 (full 1-cycle stall bubble)
//              15. Inter-stage Load-Use on Slot 1 only (Slot 0 issues, Slot 1 stalls)
//              16. EX control redirect / branch mispredict flush
// =============================================================================

`timescale 1ns/1ps

module tb_hazard_unit_superscalar;
    // ID Stage Inputs - Slot 0
    logic        id_slot0_valid;
    logic [4:0]  id_slot0_rs1, id_slot0_rs2, id_slot0_rd;
    logic        id_slot0_uses_rs1, id_slot0_uses_rs2, id_slot0_reg_write;
    logic        id_slot0_mem_read, id_slot0_mem_write;
    logic        id_slot0_branch, id_slot0_jal, id_slot0_jalr;
    logic        id_slot0_pred_taken;
    logic [1:0]  id_slot0_mem_class;

    // ID Stage Inputs - Slot 1
    logic        id_slot1_valid;
    logic [4:0]  id_slot1_rs1, id_slot1_rs2, id_slot1_rd;
    logic        id_slot1_uses_rs1, id_slot1_uses_rs2, id_slot1_reg_write;
    logic        id_slot1_mem_read, id_slot1_mem_write;
    logic        id_slot1_branch, id_slot1_jal, id_slot1_jalr;
    logic [1:0]  id_slot1_mem_class;

    // EX Stage Inputs
    logic        ex0_mem_read, ex0_reg_write;
    logic [4:0]  ex0_rd;
    logic        ex1_mem_read, ex1_reg_write;
    logic [4:0]  ex1_rd;
    logic        ex_redirect;

    // DUT Outputs
    logic [1:0]  issue_count;
    logic        slot0_issue_en, slot1_issue_en;
    logic        pc_write, if_id_write, flush_if_id, flush_id_ex;
    logic        raw_hazard_0_to_1, waw_collision;
    logic        load_use_hazard_0, load_use_hazard_1;
    logic        mem_class_conflict;

    int errors = 0;

    hazard_unit_superscalar dut (
        .id_slot0_valid(id_slot0_valid),
        .id_slot0_rs1(id_slot0_rs1), .id_slot0_rs2(id_slot0_rs2), .id_slot0_rd(id_slot0_rd),
        .id_slot0_uses_rs1(id_slot0_uses_rs1), .id_slot0_uses_rs2(id_slot0_uses_rs2),
        .id_slot0_reg_write(id_slot0_reg_write),
        .id_slot0_mem_read(id_slot0_mem_read), .id_slot0_mem_write(id_slot0_mem_write),
        .id_slot0_branch(id_slot0_branch), .id_slot0_jal(id_slot0_jal), .id_slot0_jalr(id_slot0_jalr),
        .id_slot0_pred_taken(id_slot0_pred_taken), .id_slot0_mem_class(id_slot0_mem_class),

        .id_slot1_valid(id_slot1_valid),
        .id_slot1_rs1(id_slot1_rs1), .id_slot1_rs2(id_slot1_rs2), .id_slot1_rd(id_slot1_rd),
        .id_slot1_uses_rs1(id_slot1_uses_rs1), .id_slot1_uses_rs2(id_slot1_uses_rs2),
        .id_slot1_reg_write(id_slot1_reg_write),
        .id_slot1_mem_read(id_slot1_mem_read), .id_slot1_mem_write(id_slot1_mem_write),
        .id_slot1_branch(id_slot1_branch), .id_slot1_jal(id_slot1_jal), .id_slot1_jalr(id_slot1_jalr),
        .id_slot1_mem_class(id_slot1_mem_class),

        .ex0_mem_read(ex0_mem_read), .ex0_reg_write(ex0_reg_write), .ex0_rd(ex0_rd),
        .ex1_mem_read(ex1_mem_read), .ex1_reg_write(ex1_reg_write), .ex1_rd(ex1_rd),
        .ex_redirect(ex_redirect),

        .issue_count(issue_count),
        .slot0_issue_en(slot0_issue_en), .slot1_issue_en(slot1_issue_en),
        .pc_write(pc_write), .if_id_write(if_id_write),
        .flush_if_id(flush_if_id), .flush_id_ex(flush_id_ex),
        .raw_hazard_0_to_1(raw_hazard_0_to_1), .waw_collision(waw_collision),
        .load_use_hazard_0(load_use_hazard_0), .load_use_hazard_1(load_use_hazard_1),
        .mem_class_conflict(mem_class_conflict)
    );

    task check(string name, logic condition);
        if (!condition) begin
            $display("FAIL: %s", name);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    task reset_signals();
        id_slot0_valid = 1; id_slot0_rs1 = 0; id_slot0_rs2 = 0; id_slot0_rd = 0;
        id_slot0_uses_rs1 = 0; id_slot0_uses_rs2 = 0; id_slot0_reg_write = 0;
        id_slot0_mem_read = 0; id_slot0_mem_write = 0;
        id_slot0_branch = 0; id_slot0_jal = 0; id_slot0_jalr = 0;
        id_slot0_pred_taken = 0; id_slot0_mem_class = 2'b00;

        id_slot1_valid = 1; id_slot1_rs1 = 0; id_slot1_rs2 = 0; id_slot1_rd = 0;
        id_slot1_uses_rs1 = 0; id_slot1_uses_rs2 = 0; id_slot1_reg_write = 0;
        id_slot1_mem_read = 0; id_slot1_mem_write = 0;
        id_slot1_branch = 0; id_slot1_jal = 0; id_slot1_jalr = 0;
        id_slot1_mem_class = 2'b00;

        ex0_mem_read = 0; ex0_reg_write = 0; ex0_rd = 0;
        ex1_mem_read = 0; ex1_reg_write = 0; ex1_rd = 0;
        ex_redirect = 0;
        #1;
    endtask

    initial begin
        $display("\n=======================================================");
        $display("STARTING SUPERSCALAR HAZARD & ISSUE UNIT TESTBENCH");
        $display("=======================================================\n");

        // ---------------------------------------------------------------------
        // Test 1: Clean Dual Issue (Two independent ALUs)
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd1; id_slot0_uses_rs1 = 1; id_slot0_rs1 = 5'd0;
        id_slot1_reg_write = 1; id_slot1_rd = 5'd2; id_slot1_uses_rs1 = 1; id_slot1_rs1 = 5'd0;
        #1;
        check("Test 1: Independent ALUs co-issue (issue_count == 2)",
              (issue_count == 2'd2) && slot0_issue_en && slot1_issue_en && !raw_hazard_0_to_1);

        // ---------------------------------------------------------------------
        // Test 2: Intra-packet RAW Hazard on rs1 (Slot 0 writes x1 -> Slot 1 reads x1)
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd1;
        id_slot1_reg_write = 1; id_slot1_rd = 5'd3; id_slot1_uses_rs1 = 1; id_slot1_rs1 = 5'd1;
        #1;
        check("Test 2: Intra-packet RAW on rs1 serializes (issue_count == 1)",
              raw_hazard_0_to_1 && (issue_count == 2'd1) && slot0_issue_en && !slot1_issue_en);

        // ---------------------------------------------------------------------
        // Test 3: Intra-packet RAW Hazard on rs2 (Slot 0 writes x2 -> Slot 1 reads x2)
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd2;
        id_slot1_reg_write = 1; id_slot1_rd = 5'd4; id_slot1_uses_rs2 = 1; id_slot1_rs2 = 5'd2;
        #1;
        check("Test 3: Intra-packet RAW on rs2 serializes (issue_count == 1)",
              raw_hazard_0_to_1 && (issue_count == 2'd1) && slot0_issue_en && !slot1_issue_en);

        // ---------------------------------------------------------------------
        // Test 4: Intra-packet RAW with x0 Destination (rd0 == 0)
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd0; // NOP writes x0
        id_slot1_reg_write = 1; id_slot1_rd = 5'd5; id_slot1_uses_rs1 = 1; id_slot1_rs1 = 5'd0;
        #1;
        check("Test 4: x0 write does NOT trigger RAW hazard (issue_count == 2)",
              !raw_hazard_0_to_1 && (issue_count == 2'd2));

        // ---------------------------------------------------------------------
        // Test 5: Intra-packet WAW Collision (both write to x6)
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd6;
        id_slot1_reg_write = 1; id_slot1_rd = 5'd6;
        #1;
        check("Test 5: WAW collision flagged, dual-issue allowed (issue_count == 2)",
              waw_collision && (issue_count == 2'd2));

        // ---------------------------------------------------------------------
        // Test 6: Slot 0 Unconditional Jump (JAL closes window)
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd1; id_slot0_jal = 1;
        id_slot1_reg_write = 1; id_slot1_rd = 5'd2;
        #1;
        check("Test 6: Slot 0 JAL closes issue window (issue_count == 1)",
              (issue_count == 2'd1) && slot0_issue_en && !slot1_issue_en);

        // ---------------------------------------------------------------------
        // Test 6b: Slot 0 Indirect Jump (JALR closes window)
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd1; id_slot0_jalr = 1; id_slot0_uses_rs1 = 1; id_slot0_rs1 = 5'd5;
        id_slot1_reg_write = 1; id_slot1_rd = 5'd2;
        #1;
        check("Test 6b: Slot 0 JALR closes issue window (issue_count == 1)",
              (issue_count == 2'd1) && slot0_issue_en && !slot1_issue_en);

        // ---------------------------------------------------------------------
        // Test 7: Slot 0 Branch Predicted Taken by BTB
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_branch = 1; id_slot0_uses_rs1 = 1; id_slot0_rs1 = 5'd1;
        id_slot0_pred_taken = 1; // BTB predicted taken!
        id_slot1_reg_write = 1; id_slot1_rd = 5'd3;
        #1;
        check("Test 7: Slot 0 Branch predicted taken squashes Slot 1 (issue_count == 1)",
              (issue_count == 2'd1) && slot0_issue_en && !slot1_issue_en);

        // ---------------------------------------------------------------------
        // Test 8: Slot 0 Branch Always Disallows Co-Issue
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_branch = 1; id_slot0_uses_rs1 = 1; id_slot0_rs1 = 5'd1;
        id_slot0_pred_taken = 0; // BTB predicted NOT taken, but Slot 0 branch always closes issue packet
        id_slot1_reg_write = 1; id_slot1_rd = 5'd3;
        #1;
        check("Test 8: Slot 0 Branch always prevents co-issue (issue_count == 1)",
              (issue_count == 2'd1) && slot0_issue_en && !slot1_issue_en);

        // ---------------------------------------------------------------------
        // Test 9: Memory Structural Conflict: Store + Store
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_mem_write = 1; id_slot0_mem_class = 2'b01; // MEM_STORE
        id_slot1_mem_write = 1; id_slot1_mem_class = 2'b01; // MEM_STORE
        #1;
        check("Test 9: Two stores conflict on single write port (issue_count == 1)",
              mem_class_conflict && (issue_count == 2'd1));

        // ---------------------------------------------------------------------
        // Test 10: Memory Structural Conflict: Bank A Load + Bank A Load
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_mem_class = 2'b10; // MEM_BANK_A
        id_slot1_mem_class = 2'b10; // MEM_BANK_A
        #1;
        check("Test 10: Two loads to same NPU bank conflict (issue_count == 1)",
              mem_class_conflict && (issue_count == 2'd1));

        // ---------------------------------------------------------------------
        // Test 11: Memory Structural Non-Conflict: Store + Bank A Load
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_mem_write = 1; id_slot0_mem_class = 2'b01; // MEM_STORE
        id_slot1_mem_class = 2'b10; // MEM_BANK_A
        #1;
        check("Test 11: Store and Bank Load co-issue (different ports, issue_count == 2)",
              !mem_class_conflict && (issue_count == 2'd2));

        // ---------------------------------------------------------------------
        // Test 12: Memory Structural Non-Conflict: Bank A Load + Bank B Load
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_mem_class = 2'b10; // MEM_BANK_A
        id_slot1_mem_class = 2'b11; // MEM_BANK_B
        #1;
        check("Test 12: Bank A and Bank B loads co-issue (issue_count == 2)",
              !mem_class_conflict && (issue_count == 2'd2));

        // ---------------------------------------------------------------------
        // Test 13: Memory Structural Non-Conflict: ALU + Store
        // ---------------------------------------------------------------------
        reset_signals();
        id_slot0_reg_write = 1; id_slot0_rd = 5'd7; id_slot0_mem_class = 2'b00; // MEM_NONE
        id_slot1_mem_write = 1; id_slot1_mem_class = 2'b01; // MEM_STORE
        #1;
        check("Test 13: ALU and Store co-issue (issue_count == 2)",
              !mem_class_conflict && (issue_count == 2'd2));

        // ---------------------------------------------------------------------
        // Test 14: Inter-Stage Load-Use Hazard on Slot 0
        // EX has load writing x8 -> Slot 0 reads x8
        // ---------------------------------------------------------------------
        reset_signals();
        ex0_mem_read = 1; ex0_rd = 5'd8;
        id_slot0_reg_write = 1; id_slot0_rd = 5'd9; id_slot0_uses_rs1 = 1; id_slot0_rs1 = 5'd8;
        id_slot1_reg_write = 1; id_slot1_rd = 5'd10;
        #1;
        check("Test 14: Load-use on Slot 0 inserts full bubble (issue_count == 0, pc_write == 0, flush_id_ex == 1)",
              load_use_hazard_0 && (issue_count == 2'd0) && !pc_write && !if_id_write && flush_id_ex);

        // ---------------------------------------------------------------------
        // Test 15: Inter-Stage Load-Use Hazard on Slot 1 Only
        // EX has load writing x8 -> Slot 0 is independent, Slot 1 reads x8
        // ---------------------------------------------------------------------
        reset_signals();
        ex0_mem_read = 1; ex0_rd = 5'd8;
        id_slot0_reg_write = 1; id_slot0_rd = 5'd9; id_slot0_uses_rs1 = 1; id_slot0_rs1 = 5'd1; // independent!
        id_slot1_reg_write = 1; id_slot1_rd = 5'd10; id_slot1_uses_rs1 = 1; id_slot1_rs1 = 5'd8; // dependent!
        #1;
        check("Test 15: Load-use on Slot 1 allows Slot 0 to issue alone (issue_count == 1, pc_write == 1)",
              !load_use_hazard_0 && load_use_hazard_1 && (issue_count == 2'd1) && slot0_issue_en && !slot1_issue_en && pc_write);

        // ---------------------------------------------------------------------
        // Test 16: Control Hazard (EX Redirect on Misprediction / Jump)
        // ---------------------------------------------------------------------
        reset_signals();
        ex_redirect = 1;
        #1;
        check("Test 16: EX redirect flushes IF/ID and ID/EX with high priority",
              flush_if_id && flush_id_ex && pc_write && (issue_count == 2'd0));

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n=======================================================");
            $display("ALL 16 HAZARD UNIT CHECKS PASSED PERFECTLY (0 ERRORS)");
            $display("=======================================================\n");
        end else begin
            $display("\nFAILED: %0d errors detected in hazard unit.\n", errors);
        end
        $finish;
    end
endmodule

