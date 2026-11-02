// =============================================================================
// Testbench: tb_execution_superscalar
// Description: Comprehensive self-checking verification for Phase 3:
//              - Dual Execution ALUs (alu_superscalar.sv)
//              - Branch & Jump Evaluator (branch_evaluator.sv)
//              - Full 4x6 Crossbar Forwarding Unit with intra-cycle bypass (forwarding_unit_superscalar.sv)
//              - Dual Pipeline Registers (pipeline_regs_superscalar.sv)
// =============================================================================

`timescale 1ns/1ps

module tb_execution_superscalar;
    logic clk = 0;
    logic rst = 1;
    int   errors = 0;

    always #5 clk = ~clk; // 100MHz clock

    task check(string name, logic condition);
        if (!condition) begin
            $display("FAIL: %s", name);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    // -------------------------------------------------------------------------
    // Signals for Dual ALUs
    // -------------------------------------------------------------------------
    logic [31:0] alu0_a, alu0_b, alu1_a, alu1_b;
    logic [3:0]  alu0_op, alu1_op;
    logic [31:0] alu0_result, alu1_result;
    logic        alu0_zero, alu1_zero;

    alu_superscalar u_dual_alu (
        .alu0_a(alu0_a), .alu0_b(alu0_b), .alu0_op(alu0_op), .alu0_result(alu0_result), .alu0_zero(alu0_zero),
        .alu1_a(alu1_a), .alu1_b(alu1_b), .alu1_op(alu1_op), .alu1_result(alu1_result), .alu1_zero(alu1_zero)
    );

    // -------------------------------------------------------------------------
    // Signals for Branch Evaluator
    // -------------------------------------------------------------------------
    logic        br_branch, br_jal, br_jalr;
    logic [2:0]  br_funct3;
    logic [31:0] br_pc, br_imm, br_rs1_val, br_rs2_val;
    logic        br_pred_taken;
    logic [31:0] br_pred_target;
    logic        br_actual_taken, br_ex_redirect, br_btb_update, br_btb_update_taken;
    logic [31:0] br_target_pc, br_redirect_target, br_btb_update_pc, br_btb_update_target;

    branch_evaluator u_branch_eval (
        .branch(br_branch), .jal(br_jal), .jalr(br_jalr), .funct3(br_funct3),
        .pc(br_pc), .imm(br_imm), .rs1_val(br_rs1_val), .rs2_val(br_rs2_val),
        .pred_taken(br_pred_taken), .pred_target(br_pred_target),
        .actual_taken(br_actual_taken), .target_pc(br_target_pc),
        .ex_redirect(br_ex_redirect), .redirect_target(br_redirect_target),
        .btb_update(br_btb_update), .btb_update_pc(br_btb_update_pc),
        .btb_update_target(br_btb_update_target), .btb_update_taken(br_btb_update_taken)
    );

    // -------------------------------------------------------------------------
    // Signals for Forwarding Unit
    // -------------------------------------------------------------------------
    logic [4:0]  fwd_id_ex0_rs1, fwd_id_ex0_rs2;
    logic        fwd_id_ex0_uses_rs1, fwd_id_ex0_uses_rs2;
    logic [31:0] fwd_id_ex0_rs1_data, fwd_id_ex0_rs2_data;

    logic [4:0]  fwd_id_ex1_rs1, fwd_id_ex1_rs2;
    logic        fwd_id_ex1_uses_rs1, fwd_id_ex1_uses_rs2;
    logic [31:0] fwd_id_ex1_rs1_data, fwd_id_ex1_rs2_data;

    logic        fwd_ex0_reg_write, fwd_ex0_mem_read;
    logic [4:0]  fwd_ex0_rd;
    logic [31:0] fwd_ex0_alu_result;

    logic        fwd_ex_mem0_reg_write;
    logic [4:0]  fwd_ex_mem0_rd;
    logic [31:0] fwd_ex_mem0_result;
    logic        fwd_ex_mem1_reg_write;
    logic [4:0]  fwd_ex_mem1_rd;
    logic [31:0] fwd_ex_mem1_result;

    logic        fwd_mem_wb0_reg_write;
    logic [4:0]  fwd_mem_wb0_rd;
    logic [31:0] fwd_mem_wb0_result;
    logic        fwd_mem_wb1_reg_write;
    logic [4:0]  fwd_mem_wb1_rd;
    logic [31:0] fwd_mem_wb1_result;

    logic [31:0] fwd_out_alu0_a, fwd_out_alu0_b, fwd_out_store0;
    logic [31:0] fwd_out_alu1_a, fwd_out_alu1_b, fwd_out_store1;
    logic [2:0]  fwd0_a_src, fwd0_b_src, fwd1_a_src, fwd1_b_src;
    logic        intra_cycle_fwd_a, intra_cycle_fwd_b;

    forwarding_unit_superscalar u_fwd (
        .id_ex0_rs1(fwd_id_ex0_rs1), .id_ex0_rs2(fwd_id_ex0_rs2),
        .id_ex0_uses_rs1(fwd_id_ex0_uses_rs1), .id_ex0_uses_rs2(fwd_id_ex0_uses_rs2),
        .id_ex0_rs1_data(fwd_id_ex0_rs1_data), .id_ex0_rs2_data(fwd_id_ex0_rs2_data),
        .id_ex1_rs1(fwd_id_ex1_rs1), .id_ex1_rs2(fwd_id_ex1_rs2),
        .id_ex1_uses_rs1(fwd_id_ex1_uses_rs1), .id_ex1_uses_rs2(fwd_id_ex1_uses_rs2),
        .id_ex1_rs1_data(fwd_id_ex1_rs1_data), .id_ex1_rs2_data(fwd_id_ex1_rs2_data),

        .ex0_reg_write(fwd_ex0_reg_write), .ex0_mem_read(fwd_ex0_mem_read),
        .ex0_rd(fwd_ex0_rd), .ex0_alu_result(fwd_ex0_alu_result),

        .ex_mem0_reg_write(fwd_ex_mem0_reg_write), .ex_mem0_rd(fwd_ex_mem0_rd), .ex_mem0_result(fwd_ex_mem0_result),
        .ex_mem1_reg_write(fwd_ex_mem1_reg_write), .ex_mem1_rd(fwd_ex_mem1_rd), .ex_mem1_result(fwd_ex_mem1_result),

        .mem_wb0_reg_write(fwd_mem_wb0_reg_write), .mem_wb0_rd(fwd_mem_wb0_rd), .mem_wb0_result(fwd_mem_wb0_result),
        .mem_wb1_reg_write(fwd_mem_wb1_reg_write), .mem_wb1_rd(fwd_mem_wb1_rd), .mem_wb1_result(fwd_mem_wb1_result),

        .forwarded_alu0_a(fwd_out_alu0_a), .forwarded_alu0_b(fwd_out_alu0_b), .forwarded_store0(fwd_out_store0),
        .forwarded_alu1_a(fwd_out_alu1_a), .forwarded_alu1_b(fwd_out_alu1_b), .forwarded_store1(fwd_out_store1),
        .fwd0_a_src(fwd0_a_src), .fwd0_b_src(fwd0_b_src), .fwd1_a_src(fwd1_a_src), .fwd1_b_src(fwd1_b_src),
        .intra_cycle_fwd_a(intra_cycle_fwd_a), .intra_cycle_fwd_b(intra_cycle_fwd_b)
    );

    // -------------------------------------------------------------------------
    // Signals for Pipeline Registers
    // -------------------------------------------------------------------------
    logic if_id_flush, if_id_write_en;
    logic [31:0] p_if_pc0, p_if_instr0, p_if_pc1, p_if_instr1;
    logic        p_if_valid0, p_if_valid1, p_if_pred_taken0;
    logic [31:0] p_if_pred_target0;
    logic [31:0] p_id_pc0, p_id_instr0, p_id_pc1, p_id_instr1;
    logic        p_id_valid0, p_id_valid1, p_id_pred_taken0;
    logic [31:0] p_id_pred_target0;

    if_id_superscalar_reg u_if_id_reg (
        .clk(clk), .rst(rst), .flush(if_id_flush), .write_en(if_id_write_en),
        .if_slot0_pc(p_if_pc0), .if_slot0_instr(p_if_instr0), .if_slot0_valid(p_if_valid0),
        .if_slot0_pred_taken(p_if_pred_taken0), .if_slot0_pred_target(p_if_pred_target0),
        .if_slot1_pc(p_if_pc1), .if_slot1_instr(p_if_instr1), .if_slot1_valid(p_if_valid1),
        .id_slot0_pc(p_id_pc0), .id_slot0_instr(p_id_instr0), .id_slot0_valid(p_id_valid0),
        .id_slot0_pred_taken(p_id_pred_taken0), .id_slot0_pred_target(p_id_pred_target0),
        .id_slot1_pc(p_id_pc1), .id_slot1_instr(p_id_instr1), .id_slot1_valid(p_id_valid1)
    );

    initial begin
        $display("\n=======================================================");
        $display("STARTING PHASE 3 SUPERSCALAR EXECUTION TESTBENCH");
        $display("=======================================================\n");

        // ---------------------------------------------------------------------
        // Test 1: Dual ALU Parallel Operations
        // ---------------------------------------------------------------------
        // Slot 0: ADD 15 + 25 = 40; Slot 1: SUB 100 - 30 = 70
        alu0_a = 32'd15; alu0_b = 32'd25; alu0_op = 4'b0000; // ADD
        alu1_a = 32'd100; alu1_b = 32'd30; alu1_op = 4'b0001; // SUB
        #1;
        check("Test 1a: ALU0 computes ADD (15 + 25 = 40)", alu0_result == 32'd40);
        check("Test 1b: ALU1 computes SUB (100 - 30 = 70)", alu1_result == 32'd70);

        // Slot 0: SLL 1 << 4 = 16; Slot 1: XOR 0xFF ^ 0x0F = 0xF0
        alu0_a = 32'd1; alu0_b = 32'd4; alu0_op = 4'b0101; // SLL
        alu1_a = 32'h000000FF; alu1_b = 32'h0000000F; alu1_op = 4'b0100; // XOR
        #1;
        check("Test 1c: ALU0 computes SLL (1 << 4 = 16)", alu0_result == 32'd16);
        check("Test 1d: ALU1 computes XOR (0xFF ^ 0x0F = 0xF0)", alu1_result == 32'h000000F0);

        // Slot 0: SLT signed (-5 < 5); Slot 1: SLTU unsigned (5 < -5)
        alu0_a = -32'd5; alu0_b = 32'd5; alu0_op = 4'b1000; // SLT
        alu1_a = 32'd5; alu1_b = -32'd5; alu1_op = 4'b1001; // SLTU
        #1;
        check("Test 1e: ALU0 signed compare SLT (-5 < 5)", alu0_result == 32'd1);
        check("Test 1f: ALU1 unsigned compare SLTU (5 < 0xFFFFFFFB)", alu1_result == 32'd1);

        // ---------------------------------------------------------------------
        // Test 2: Branch Evaluator Conditions (BEQ, BNE, BLT, BGE)
        // ---------------------------------------------------------------------
        br_branch = 1; br_jal = 0; br_jalr = 0;
        br_pc = 32'h00000100; br_imm = 32'd16;
        br_pred_taken = 0; br_pred_target = 32'd0;

        // 2a: BEQ Equal (Taken)
        br_funct3 = 3'b000; br_rs1_val = 32'd42; br_rs2_val = 32'd42;
        #1;
        check("Test 2a: BEQ taken when rs1 == rs2", br_actual_taken && (br_target_pc == 32'h00000110));
        check("Test 2b: Mispredict asserted (predicted NOT taken, actually TAKEN)", br_ex_redirect && (br_redirect_target == 32'h00000110));

        // 2b: BEQ Not Equal (Not Taken, predicted Taken -> Mispredict to PC+4)
        br_pred_taken = 1; br_pred_target = 32'h00000110;
        br_rs1_val = 32'd42; br_rs2_val = 32'd99;
        #1;
        check("Test 2c: BEQ not taken when rs1 != rs2", !br_actual_taken);
        check("Test 2d: Redirect to PC+4 on mispredicted taken branch", br_ex_redirect && (br_redirect_target == 32'h00000104));

        // 2c: BNE Correctly Predicted Taken (No redirect!)
        br_funct3 = 3'b001; br_rs1_val = 32'd1; br_rs2_val = 32'd2;
        br_pred_taken = 1; br_pred_target = 32'h00000110;
        #1;
        check("Test 2e: BNE taken when rs1 != rs2", br_actual_taken);
        check("Test 2f: Zero redirect bubble when prediction matches", !br_ex_redirect);

        // ---------------------------------------------------------------------
        // Test 3: JAL and JALR Target Evaluation
        // ---------------------------------------------------------------------
        br_branch = 0; br_jal = 1; br_jalr = 0;
        br_pc = 32'h00000200; br_imm = 32'h00000080;
        br_pred_taken = 0; // Not predicted
        #1;
        check("Test 3a: JAL target calculated (PC + imm = 0x00000280)", br_target_pc == 32'h00000280);
        check("Test 3b: JAL redirects when not predicted", br_ex_redirect && (br_redirect_target == 32'h00000280));

        // JALR: target = (rs1 + imm) & ~1
        br_jal = 0; br_jalr = 1;
        br_rs1_val = 32'h00001001; br_imm = 32'd4;
        #1;
        check("Test 3c: JALR target calculated with LSB cleared (0x00001004)", br_target_pc == 32'h00001004);
        check("Test 3d: JALR always redirects to target", br_ex_redirect && (br_redirect_target == 32'h00001004));

        // ---------------------------------------------------------------------
        // Test 4: Crossbar Forwarding - EX/MEM Stage to Slot 0
        // ---------------------------------------------------------------------
        // Clear all inputs
        fwd_id_ex0_rs1 = 5'd1; fwd_id_ex0_rs2 = 5'd2;
        fwd_id_ex0_uses_rs1 = 1; fwd_id_ex0_uses_rs2 = 1;
        fwd_id_ex0_rs1_data = 32'h1111_1111; fwd_id_ex0_rs2_data = 32'h2222_2222;

        fwd_id_ex1_rs1 = 5'd3; fwd_id_ex1_rs2 = 5'd4;
        fwd_id_ex1_uses_rs1 = 1; fwd_id_ex1_uses_rs2 = 1;
        fwd_id_ex1_rs1_data = 32'h3333_3333; fwd_id_ex1_rs2_data = 32'h4444_4444;

        fwd_ex0_reg_write = 0; fwd_ex0_mem_read = 0; fwd_ex0_rd = 5'd0; fwd_ex0_alu_result = 32'd0;
        fwd_ex_mem0_reg_write = 0; fwd_ex_mem0_rd = 5'd0; fwd_ex_mem0_result = 32'd0;
        fwd_ex_mem1_reg_write = 0; fwd_ex_mem1_rd = 5'd0; fwd_ex_mem1_result = 32'd0;
        fwd_mem_wb0_reg_write = 0; fwd_mem_wb0_rd = 5'd0; fwd_mem_wb0_result = 32'd0;
        fwd_mem_wb1_reg_write = 0; fwd_mem_wb1_rd = 5'd0; fwd_mem_wb1_result = 32'd0;
        #1;
        check("Test 4a: Default regfile data when no hazards", (fwd_out_alu0_a == 32'h1111_1111) && (fwd_out_alu0_b == 32'h2222_2222));

        // Forward from EX/MEM0 to Slot 0 rs1 (rd=1)
        fwd_ex_mem0_reg_write = 1; fwd_ex_mem0_rd = 5'd1; fwd_ex_mem0_result = 32'hAAAA_0001;
        #1;
        check("Test 4b: Forward EX/MEM0 to Slot 0 rs1", fwd_out_alu0_a == 32'hAAAA_0001);

        // Forward from EX/MEM1 to Slot 0 rs2 (rd=2)
        fwd_ex_mem1_reg_write = 1; fwd_ex_mem1_rd = 5'd2; fwd_ex_mem1_result = 32'hBBBB_0002;
        #1;
        check("Test 4c: Forward EX/MEM1 to Slot 0 rs2", fwd_out_alu0_b == 32'hBBBB_0002);

        // ---------------------------------------------------------------------
        // Test 5: Forwarding Age Priority (EX/MEM1 overrides EX/MEM0 on same rd)
        // ---------------------------------------------------------------------
        // Both EX/MEM0 and EX/MEM1 write to x1. Slot 1 is younger in program order!
        fwd_ex_mem0_reg_write = 1; fwd_ex_mem0_rd = 5'd1; fwd_ex_mem0_result = 32'hAAAA_0001;
        fwd_ex_mem1_reg_write = 1; fwd_ex_mem1_rd = 5'd1; fwd_ex_mem1_result = 32'hBBBB_0001;
        #1;
        check("Test 5: EX/MEM1 takes priority over EX/MEM0 on identical rd", fwd_out_alu0_a == 32'hBBBB_0001);

        // ---------------------------------------------------------------------
        // Test 6: Intra-Cycle ALU0 -> ALU1 Bypassing (Breaking Pointer Bottleneck)
        // ---------------------------------------------------------------------
        // Slot 0 in EX computes a5 = a5 + 64 (rd=5). Slot 1 in EX reads a5 (rs1=5).
        fwd_id_ex1_rs1 = 5'd5; fwd_id_ex1_uses_rs1 = 1;
        fwd_ex0_reg_write = 1; fwd_ex0_mem_read = 0; fwd_ex0_rd = 5'd5;
        fwd_ex0_alu_result = 32'h0000_1040;
        #1;
        check("Test 6a: Intra-cycle ALU0 result forwarded to ALU1 operand A", fwd_out_alu1_a == 32'h0000_1040);
        check("Test 6b: Intra-cycle telemetry flag asserted", intra_cycle_fwd_a == 1'b1);

        // Intra-cycle forwarding to store data (rs2=5)
        fwd_id_ex1_rs2 = 5'd5; fwd_id_ex1_uses_rs2 = 1;
        #1;
        check("Test 6c: Intra-cycle ALU0 result forwarded to Slot 1 store data", fwd_out_store1 == 32'h0000_1040);
        check("Test 6d: Intra-cycle telemetry flag for operand B asserted", intra_cycle_fwd_b == 1'b1);

        // ---------------------------------------------------------------------
        // Test 7: Register x0 Forwarding Suppression
        // ---------------------------------------------------------------------
        fwd_id_ex0_rs1 = 5'd0; fwd_id_ex0_uses_rs1 = 1; fwd_id_ex0_rs1_data = 32'd0;
        fwd_ex_mem0_reg_write = 1; fwd_ex_mem0_rd = 5'd0; fwd_ex_mem0_result = 32'hFFFF_FFFF;
        #1;
        check("Test 7: x0 write does NOT forward, remains zero", fwd_out_alu0_a == 32'd0);

        // ---------------------------------------------------------------------
        // Test 8: Pipeline Register Synchronous Latching, Stalling, and Flushing
        // ---------------------------------------------------------------------
        @(negedge clk);
        rst = 1; if_id_flush = 0; if_id_write_en = 1;
        @(negedge clk);
        rst = 0;
        p_if_pc0 = 32'h0000_0010; p_if_instr0 = 32'h00100093; p_if_valid0 = 1;
        p_if_pc1 = 32'h0000_0014; p_if_instr1 = 32'h00200113; p_if_valid1 = 1;
        p_if_pred_taken0 = 0; p_if_pred_target0 = 32'd0;

        @(negedge clk);
        check("Test 8a: IF/ID latches Slot 0 instruction", (p_id_pc0 == 32'h0000_0010) && (p_id_instr0 == 32'h00100093) && p_id_valid0);
        check("Test 8b: IF/ID latches Slot 1 instruction", (p_id_pc1 == 32'h0000_0014) && (p_id_instr1 == 32'h00200113) && p_id_valid1);

        // Pipeline stall: write_en = 0
        if_id_write_en = 0;
        p_if_pc0 = 32'h0000_0018; p_if_instr0 = 32'h00300193;
        @(negedge clk);
        check("Test 8c: IF/ID freezes contents during pipeline stall", p_id_pc0 == 32'h0000_0010);

        // Pipeline flush: insert NOPs
        if_id_write_en = 1; if_id_flush = 1;
        @(negedge clk);
        check("Test 8d: IF/ID flushes to NOP (32'h00000013, valid=0) on flush", (p_id_instr0 == 32'h00000013) && (!p_id_valid0));

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n=======================================================");
            $display("ALL PHASE 3 EXECUTION & FORWARDING CHECKS PASSED (0 ERRORS)");
            $display("=======================================================\n");
        end else begin
            $display("\nFAILED: %0d errors detected in Phase 3.\n", errors);
        end
        $finish;
    end
endmodule

