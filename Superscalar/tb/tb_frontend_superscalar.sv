// =============================================================================
// Testbench: tb_frontend_superscalar
// Description: Comprehensive self-checking verification for fetch_unit_superscalar.
//              Verifies:
//              1. Aligned 64-bit dual-instruction fetch (Slot 0 and Slot 1 valid)
//              2. Dual-issue program counter advance (+8)
//              3. Single-issue program counter advance (+4)
//              4. Dynamic unaligned word steering logic (odd-word target steered
//                 to Slot 0, Slot 1 padded with NOP, unaligned_fetch asserted)
//              5. Pipeline freeze on stall (PC holds value)
//              6. Architectural branch/jump redirect from execution stage
//              7. BTB branch target buffer learning and speculative redirection
// =============================================================================

`timescale 1ns/1ps

module tb_frontend_superscalar;
    logic        clk = 0;
    logic        rst = 1;

    // Pipeline Control & Status
    logic        stall = 0;
    logic [1:0]  issue_count = 2'd2; // default: 2 instructions issue per cycle

    // Architectural Branch / Jump Redirect from EX Stage
    logic        redirect_valid = 0;
    logic [31:0] redirect_target = 32'd0;

    // BTB Update Interface
    logic        branch_resolved = 0;
    logic [31:0] branch_source_pc = 32'd0;
    logic [31:0] branch_actual_target = 32'd0;
    logic        branch_taken = 0;

    // Outputs from DUT
    logic [31:0] slot0_pc;
    logic [31:0] slot1_pc;
    logic [31:0] slot0_instr;
    logic [31:0] slot1_instr;
    logic        slot0_valid;
    logic        slot1_valid;
    logic        slot0_pred_taken;
    logic [31:0] slot0_pred_target;
    logic [31:0] current_pc;
    logic [31:0] next_pc;
    logic        unaligned_fetch;

    int errors = 0;
    always #5 clk = ~clk; // 100MHz clock

    fetch_unit_superscalar #(.MEM_WORDS(1024)) dut (
        .clk(clk),
        .rst(rst),
        .stall(stall),
        .issue_count(issue_count),
        .redirect_valid(redirect_valid),
        .redirect_target(redirect_target),
        .branch_resolved(branch_resolved),
        .branch_source_pc(branch_source_pc),
        .branch_actual_target(branch_actual_target),
        .branch_taken(branch_taken),
        .slot0_pc(slot0_pc),
        .slot1_pc(slot1_pc),
        .slot0_instr(slot0_instr),
        .slot1_instr(slot1_instr),
        .slot0_valid(slot0_valid),
        .slot1_valid(slot1_valid),
        .slot0_pred_taken(slot0_pred_taken),
        .slot0_pred_target(slot0_pred_target),
        .current_pc(current_pc),
        .next_pc(next_pc),
        .unaligned_fetch(unaligned_fetch)
    );

    task check(string name, logic condition);
        if (!condition) begin
            $display("FAIL: %s", name);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        $display("\n=======================================================");
        $display("STARTING SUPERSCALAR FRONTEND SELF-CHECKING TESTBENCH");
        $display("=======================================================\n");

        @(negedge clk);
        rst = 1;
        issue_count = 2'd2;
        stall = 0;
        redirect_valid = 0;
        branch_resolved = 0;

        @(negedge clk);
        rst = 0;

        // ---------------------------------------------------------------------
        // Test 1: Aligned 64-bit dual fetch at PC 0x00000000
        // Expected:
        //   slot0_pc = 0x00, slot0_instr = 32'h00100093 (addi x1, x0, 1)
        //   slot1_pc = 0x04, slot1_instr = 32'h00200113 (addi x2, x0, 2)
        //   both valid, unaligned_fetch = 0
        // ---------------------------------------------------------------------
        #1;
        check("Test 1a: PC is 0x00000000 after reset", current_pc == 32'h00000000);
        check("Test 1b: Unaligned flag is 0", unaligned_fetch == 1'b0);
        check("Test 1c: Slot 0 PC is 0x00", slot0_pc == 32'h00000000);
        check("Test 1d: Slot 1 PC is 0x04", slot1_pc == 32'h00000004);
        check("Test 1e: Slot 0 instruction matches word 0", slot0_instr == 32'h00100093);
        check("Test 1f: Slot 1 instruction matches word 1", slot1_instr == 32'h00200113);
        check("Test 1g: Both slots valid on aligned fetch", slot0_valid == 1'b1 && slot1_valid == 1'b1);

        // ---------------------------------------------------------------------
        // Test 2: Dual-issue advance (+8) to PC 0x00000008
        // ---------------------------------------------------------------------
        @(negedge clk);
        #1;
        check("Test 2a: PC advanced +8 to 0x00000008", current_pc == 32'h00000008);
        check("Test 2b: Slot 0 instruction matches word 2 (0x08)", slot0_instr == 32'h00300193);
        check("Test 2c: Slot 1 instruction matches word 3 (0x0C)", slot1_instr == 32'h00400213);
        check("Test 2d: Both slots valid", slot0_valid == 1'b1 && slot1_valid == 1'b1);

        // ---------------------------------------------------------------------
        // Test 3: Single-issue advance (+4) to PC 0x0000000C (creates unaligned state)
        // ---------------------------------------------------------------------
        issue_count = 2'd1; // only 1 instruction issued this cycle!
        @(negedge clk);
        #1;
        check("Test 3a: PC advanced +4 to 0x0000000C", current_pc == 32'h0000000C);
        check("Test 3b: Unaligned flag asserted for pc[2] == 1", unaligned_fetch == 1'b1);
        check("Test 3c: Slot 0 steered to word at 0x0C", slot0_instr == 32'h00400213);
        check("Test 3d: Slot 1 steered to NOP (addi x0, x0, 0)", slot1_instr == 32'h00000013);
        check("Test 3e: Slot 0 valid, Slot 1 INVALID on unaligned fetch", slot0_valid == 1'b1 && slot1_valid == 1'b0);

        // ---------------------------------------------------------------------
        // Test 4: Dynamic Re-alignment from unaligned fetch
        // Single issue from 0x0C advances PC to 0x10 (aligned again!)
        // ---------------------------------------------------------------------
        issue_count = 2'd1;
        @(negedge clk);
        #1;
        check("Test 4a: PC advanced +4 to 0x00000010 (aligned boundary)", current_pc == 32'h00000010);
        check("Test 4b: Unaligned flag cleared", unaligned_fetch == 1'b0);
        check("Test 4c: Slot 0 instruction matches word 4 (0x10)", slot0_instr == 32'h00500293);
        check("Test 4d: Slot 1 instruction matches word 5 (0x14)", slot1_instr == 32'h00600313);
        check("Test 4e: Both slots valid again", slot0_valid == 1'b1 && slot1_valid == 1'b1);

        // ---------------------------------------------------------------------
        // Test 5: Pipeline Stall (freeze)
        // ---------------------------------------------------------------------
        stall = 1;
        @(negedge clk);
        #1;
        check("Test 5a: PC froze at 0x00000010 during stall", current_pc == 32'h00000010);
        check("Test 5b: Next PC equals current PC during stall", next_pc == 32'h00000010);
        @(negedge clk);
        #1;
        check("Test 5c: PC still 0x00000010 on cycle 2 of stall", current_pc == 32'h00000010);
        stall = 0;
        issue_count = 2'd2;

        // ---------------------------------------------------------------------
        // Test 6: Architectural Branch / Jump Redirect from EX Stage
        // Redirect PC directly to 0x00000040 (branch instruction in hex)
        // ---------------------------------------------------------------------
        redirect_valid = 1;
        redirect_target = 32'h00000040;
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 6a: Redirect took effect immediately, PC = 0x00000040", current_pc == 32'h00000040);
        check("Test 6b: Slot 0 fetched branch instruction (0x04000063)", slot0_instr == 32'h04000063);
        check("Test 6c: Untrained BTB does NOT predict branch taken initially", slot0_pred_taken == 1'b0);

        // ---------------------------------------------------------------------
        // Test 7: Train BTB on branch at 0x40 -> target 0x80 (Taken)
        // ---------------------------------------------------------------------
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 1;

        // Train twice to transition saturating counter to Strong Taken
        @(negedge clk);
        @(negedge clk);
        branch_resolved = 0;

        // Redirect PC back to 0x00000040 to test speculative prediction
        redirect_valid = 1;
        redirect_target = 32'h00000040;
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 7a: PC at branch address 0x00000040", current_pc == 32'h00000040);
        check("Test 7b: BTB predicts taken for trained branch", slot0_pred_taken == 1'b1);
        check("Test 7c: BTB predicted target matches 0x00000080", slot0_pred_target == 32'h00000080);
        check("Test 7d: Next PC combinationally redirected to 0x00000080", next_pc == 32'h00000080);
        check("Test 7e: Slot 1 is squashed (valid == 0) when Slot 0 branch predicted taken", slot1_valid == 1'b0);
        check("Test 7f: Slot 1 padded with NOP when Slot 0 branch predicted taken", slot1_instr == 32'h00000013);

        // Verify clock edge advances speculatively to predicted target
        @(negedge clk);
        #1;
        check("Test 7g: PC speculatively jumped to 0x00000080 on clock edge", current_pc == 32'h00000080);
        check("Test 7h: Slot 0 instruction at target is word at 0x80 (0x00700393)", slot0_instr == 32'h00700393);

        // ---------------------------------------------------------------------
        // Test 8: Branch in Slot 0 closes issue packet (Slot 1 squashed with NOP)
        // Even when predicted NOT TAKEN, Slot 1 must not issue after Slot 0 branch
        // ---------------------------------------------------------------------
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 0; // Evaluated NOT TAKEN

        // Train 3 times: 11 -> 10 -> 01 -> 00 (Strongly Not Taken)
        @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        branch_resolved = 0;

        redirect_valid = 1;
        redirect_target = 32'h00000040;
        issue_count = 2'd1; // Slot 0 branch closes issue window
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 8a: PC at branch address 0x00000040", current_pc == 32'h00000040);
        check("Test 8b: Branch predicted NOT TAKEN when counter is 00", slot0_pred_taken == 1'b0);
        check("Test 8c: Slot 1 is SQUASHED (valid == 0) after Slot 0 branch", slot1_valid == 1'b0);
        check("Test 8d: Slot 1 padded with NOP (0x00000013)", slot1_instr == 32'h00000013);
        check("Test 8e: Next PC advances +4 single-step to 0x00000044", next_pc == 32'h00000044);
        issue_count = 2'd2; // Restore default

        // ---------------------------------------------------------------------
        // Test 9: Branch with Unaligned Target Address (0x00000084, pc[2] == 1)
        // ---------------------------------------------------------------------
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000084; // Odd word target!
        branch_taken = 1;
        @(negedge clk);
        @(negedge clk); // Train back to Strongly Taken
        branch_resolved = 0;

        redirect_valid = 1;
        redirect_target = 32'h00000040;
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 9a: BTB predicts taken for branch with unaligned target", slot0_pred_taken == 1'b1);
        check("Test 9b: Next PC redirected to unaligned target 0x00000084", next_pc == 32'h00000084);
        @(negedge clk);
        #1;
        check("Test 9c: PC lands at unaligned target 0x00000084", current_pc == 32'h00000084);
        check("Test 9d: unaligned_fetch asserted for odd word", unaligned_fetch == 1'b1);
        check("Test 9e: Slot 0 dynamically steered to word at 0x84 (0x00800413)", slot0_instr == 32'h00800413);
        check("Test 9f: Slot 1 padded with NOP on unaligned fetch", slot1_valid == 1'b0 && slot1_instr == 32'h00000013);
        check("Test 9g: Next PC realigns by +4 to 0x00000088", next_pc == 32'h00000088);
        @(negedge clk);
        #1;
        check("Test 9h: PC realigned to 0x00000088", current_pc == 32'h00000088);
        check("Test 9i: unaligned_fetch deasserted", unaligned_fetch == 1'b0);

        // ---------------------------------------------------------------------
        // Test 10: Non-Branch Opcode Gating at BTB-Occupied Address
        // Address 0x00000010 contains addi (opcode 0x13, not 0x63)
        // Even if trained in BTB, non-branch must NOT predict taken!
        // ---------------------------------------------------------------------
        branch_resolved = 1;
        branch_source_pc = 32'h00000010;
        branch_actual_target = 32'h00000090;
        branch_taken = 1;
        @(negedge clk);
        @(negedge clk);
        branch_resolved = 0;

        redirect_valid = 1;
        redirect_target = 32'h00000010;
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 10a: PC at 0x00000010", current_pc == 32'h00000010);
        check("Test 10b: Slot 0 instruction is non-branch addi", slot0_instr[6:0] == 7'b0010011);
        check("Test 10c: Opcode gating prevents BTB prediction for non-branch", slot0_pred_taken == 1'b0);
        check("Test 10d: Both slots remain valid", slot0_valid == 1'b1 && slot1_valid == 1'b1);
        check("Test 10e: Next PC advances +8 sequential stream to 0x00000018", next_pc == 32'h00000018);

        // ---------------------------------------------------------------------
        // Test 11: Direct-Mapped BTB Tag Matching & Aliasing Collision
        // Branch A: 0x00000040 (index 0x10, tag 23'd0)
        // Branch B: 0x00000240 (index 0x10, tag 23'd1) -> same index, different tag!
        // ---------------------------------------------------------------------
        // 1. Train Branch A at 0x00000040 to target 0x00000080
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 1;
        @(negedge clk);
        @(negedge clk);
        branch_resolved = 0;

        // 2. Query Branch B at 0x00000240
        redirect_valid = 1;
        redirect_target = 32'h00000240;
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 11a: PC at aliased branch address 0x00000240", current_pc == 32'h00000240);
        check("Test 11b: Tag mismatch causes BTB MISS on Branch B", slot0_pred_taken == 1'b0);

        // 3. Train Branch B at 0x00000240 to target 0x00000280
        branch_resolved = 1;
        branch_source_pc = 32'h00000240;
        branch_actual_target = 32'h00000280;
        branch_taken = 1;
        @(negedge clk);
        @(negedge clk);
        branch_resolved = 0;

        redirect_valid = 1;
        redirect_target = 32'h00000240;
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 11c: Branch B now hits and predicts target 0x00000280", slot0_pred_taken == 1'b1 && slot0_pred_target == 32'h00000280);

        // 4. Query Branch A at 0x00000040 (should now miss because evicted by B)
        redirect_valid = 1;
        redirect_target = 32'h00000040;
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 11d: Branch A was evicted by Branch B (Tag mismatch -> MISS)", slot0_pred_taken == 1'b0);

        // ---------------------------------------------------------------------
        // Test 12: Saturating Counter Hysteresis (01 -> 10 -> 11 -> 10 -> 01 -> 00)
        // ---------------------------------------------------------------------
        // Clamp PC to 0x00000040 using redirect to observe predictions in real time
        redirect_valid = 1;
        redirect_target = 32'h00000040;
        @(negedge clk);

        // Step 1: Weakly Not-Taken (01) -> Taken -> Weakly Taken (10)
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 1;
        @(negedge clk);
        branch_resolved = 0;
        #1;
        check("Test 12a: 01 -> 10 predicts TAKEN", slot0_pred_taken == 1'b1);

        // Step 2: 10 -> Taken -> 11 (Strongly Taken)
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 1;
        @(negedge clk);
        branch_resolved = 0;
        #1;
        check("Test 12b: 10 -> 11 predicts TAKEN", slot0_pred_taken == 1'b1);

        // Step 3: 11 -> Taken -> 11 (Saturated)
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 1;
        @(negedge clk);
        branch_resolved = 0;
        #1;
        check("Test 12c: 11 -> 11 saturates at Strongly Taken", slot0_pred_taken == 1'b1);

        // Step 4: 11 -> Not Taken -> 10 (Hysteresis! Still predicts Taken)
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 0;
        @(negedge clk);
        branch_resolved = 0;
        #1;
        check("Test 12d: 11 -> 10 hysteresis still predicts TAKEN", slot0_pred_taken == 1'b1);

        // Step 5: 10 -> Not Taken -> 01 (Weakly Not Taken -> predicts NOT Taken)
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 0;
        @(negedge clk);
        branch_resolved = 0;
        #1;
        check("Test 12e: 10 -> 01 transitions to NOT TAKEN", slot0_pred_taken == 1'b0);

        // Step 6: 01 -> Not Taken -> 00 (Strongly Not Taken)
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 0;
        @(negedge clk);
        branch_resolved = 0;
        #1;
        check("Test 12f: 01 -> 00 transitions to Strongly Not-Taken", slot0_pred_taken == 1'b0);

        // Step 7: 00 -> Not Taken -> 00 (Saturated)
        branch_resolved = 1;
        branch_source_pc = 32'h00000040;
        branch_actual_target = 32'h00000080;
        branch_taken = 0;
        @(negedge clk);
        branch_resolved = 0;
        #1;
        check("Test 12g: 00 -> 00 saturates at Strongly Not-Taken", slot0_pred_taken == 1'b0);

        redirect_valid = 0; // Release redirect clamp

        // ---------------------------------------------------------------------
        // Test 13: Dynamic Single-Instruction Issue Step (issue_count == 1)
        // ---------------------------------------------------------------------
        redirect_valid = 1;
        redirect_target = 32'h00000020; // Aligned boundary
        @(negedge clk);
        redirect_valid = 0;
        issue_count = 2'd1; // Force single-issue
        #1;
        check("Test 13a: Single-issue step asserts next_pc = pc + 4", next_pc == 32'h00000024);
        @(negedge clk);
        #1;
        check("Test 13b: PC advanced to 0x00000024 (unaligned boundary)", current_pc == 32'h00000024);
        check("Test 13c: unaligned_fetch asserted on pc[2] == 1", unaligned_fetch == 1'b1);
        issue_count = 2'd2; // Restore dual-issue

        // ---------------------------------------------------------------------
        // Test 14: EX Redirect Priority Over Pipeline Stall
        // ---------------------------------------------------------------------
        stall = 1;
        redirect_valid = 1;
        redirect_target = 32'h00000030;
        #1;
        check("Test 14a: Redirect has strict priority over stall", next_pc == 32'h00000030);
        @(negedge clk);
        redirect_valid = 0;
        stall = 0;
        #1;
        check("Test 14b: PC took redirect despite concurrent stall", current_pc == 32'h00000030);

        // ---------------------------------------------------------------------
        // Test 15: Slot 0 JAL closes issue packet (Slot 1 squashed with NOP)
        // ---------------------------------------------------------------------
        dut.imem_64.mem[32'h00000050 >> 2] = 32'h008000EF; // JAL x1, +8 (opcode 0x6F)
        dut.imem_64.mem[(32'h00000050 >> 2) + 1] = 32'h00100093; // ADDI x1, x0, 1 (fallthrough)

        redirect_valid = 1;
        redirect_target = 32'h00000050; // Aligned 64-bit boundary
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 15a: PC at JAL address 0x00000050", current_pc == 32'h00000050);
        check("Test 15b: Slot 0 instruction is JAL (0x008000EF)", slot0_instr == 32'h008000EF);
        check("Test 15c: Slot 0 is valid", slot0_valid == 1'b1);
        check("Test 15d: Slot 1 is SQUASHED (valid == 0) on Slot 0 JAL", slot1_valid == 1'b0);
        check("Test 15e: Slot 1 is padded with hardware NOP (0x00000013)", slot1_instr == 32'h00000013);

        // ---------------------------------------------------------------------
        // Test 16: Slot 0 JALR closes issue packet (Slot 1 squashed with NOP)
        // ---------------------------------------------------------------------
        dut.imem_64.mem[32'h00000060 >> 2] = 32'h000080E7; // JALR x1, 0(x1) (opcode 0x67)
        dut.imem_64.mem[(32'h00000060 >> 2) + 1] = 32'h00200113; // ADDI x2, x0, 2 (fallthrough)

        redirect_valid = 1;
        redirect_target = 32'h00000060; // Aligned 64-bit boundary
        @(negedge clk);
        redirect_valid = 0;
        #1;
        check("Test 16a: PC at JALR address 0x00000060", current_pc == 32'h00000060);
        check("Test 16b: Slot 0 instruction is JALR (0x000080E7)", slot0_instr == 32'h000080E7);
        check("Test 16c: Slot 0 is valid", slot0_valid == 1'b1);
        check("Test 16d: Slot 1 is SQUASHED (valid == 0) on Slot 0 JALR", slot1_valid == 1'b0);
        check("Test 16e: Slot 1 is padded with hardware NOP (0x00000013)", slot1_instr == 32'h00000013);

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n=======================================================");
            $display("ALL SUPERSCALAR FRONTEND CHECKS PASSED (0 ERRORS)");
            $display("=======================================================\n");
        end else begin
            $display("\nFAILED: %0d errors detected in frontend testbench.\n", errors);
        end
        $finish;
    end
endmodule

