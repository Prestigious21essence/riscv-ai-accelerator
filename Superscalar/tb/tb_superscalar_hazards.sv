// =============================================================================
// RISC-V 2-Way Superscalar Core - Phase 6 Hazard Stress Suite
// File: tb_superscalar_hazards.sv
//
// Description:
//   Self-checking stress-testbench targeting the 6 most critical hazard
//   conditions in the 2-way superscalar architecture:
//     1. Intra-Packet RAW Dependency & Intra-Cycle ALU0 -> ALU1 Forwarding
//     2. Inter-Stage Load-Use Hazard & Dynamic Bubble Injection
//     3. WAW Register Output Hazard (Slot 1 Program-Order Age Priority)
//     4. Speculative Branch Misprediction & Synchronous Pipeline Flush
//     5. Intra-Stage Store-to-Load Forwarding (Matching Word Address)
//     6. Memory Class Structural Conflict & Store-Store Serialization
// =============================================================================

`timescale 1ns / 1ps

module tb_superscalar_hazards;

    logic clk;
    logic rst;

    // -------------------------------------------------------------------------
    // 1. Forwarding Unit Interface
    // -------------------------------------------------------------------------
    logic [4:0]  id_ex0_rs1, id_ex0_rs2;
    logic        id_ex0_uses_rs1, id_ex0_uses_rs2;
    logic [31:0] id_ex0_rs1_data, id_ex0_rs2_data;

    logic [4:0]  id_ex1_rs1, id_ex1_rs2;
    logic        id_ex1_uses_rs1, id_ex1_uses_rs2;
    logic [31:0] id_ex1_rs1_data, id_ex1_rs2_data;

    logic        ex0_reg_write, ex0_mem_read;
    logic [4:0]  ex0_rd;
    logic [31:0] ex0_alu_result;

    logic        ex_mem0_reg_write, ex_mem1_reg_write;
    logic [4:0]  ex_mem0_rd, ex_mem1_rd;
    logic [31:0] ex_mem0_result, ex_mem1_result;

    logic        mem_wb0_reg_write, mem_wb1_reg_write;
    logic [4:0]  mem_wb0_rd, mem_wb1_rd;
    logic [31:0] mem_wb0_result, mem_wb1_result;

    logic [31:0] fwd_alu0_a, fwd_alu0_b, fwd_store0;
    logic [31:0] fwd_alu1_a, fwd_alu1_b, fwd_store1;
    logic [2:0]  fwd0_a_src, fwd0_b_src, fwd1_a_src, fwd1_b_src;
    logic        intra_cycle_fwd_a, intra_cycle_fwd_b;

    forwarding_unit_superscalar fwd_dut (
        .id_ex0_rs1       (id_ex0_rs1),
        .id_ex0_rs2       (id_ex0_rs2),
        .id_ex0_uses_rs1  (id_ex0_uses_rs1),
        .id_ex0_uses_rs2  (id_ex0_uses_rs2),
        .id_ex0_rs1_data  (id_ex0_rs1_data),
        .id_ex0_rs2_data  (id_ex0_rs2_data),
        .id_ex1_rs1       (id_ex1_rs1),
        .id_ex1_rs2       (id_ex1_rs2),
        .id_ex1_uses_rs1  (id_ex1_uses_rs1),
        .id_ex1_uses_rs2  (id_ex1_uses_rs2),
        .id_ex1_rs1_data  (id_ex1_rs1_data),
        .id_ex1_rs2_data  (id_ex1_rs2_data),
        .ex0_reg_write    (ex0_reg_write),
        .ex0_mem_read     (ex0_mem_read),
        .ex0_rd           (ex0_rd),
        .ex0_alu_result   (ex0_alu_result),
        .ex_mem0_reg_write(ex_mem0_reg_write),
        .ex_mem0_rd       (ex_mem0_rd),
        .ex_mem0_result   (ex_mem0_result),
        .ex_mem1_reg_write(ex_mem1_reg_write),
        .ex_mem1_rd       (ex_mem1_rd),
        .ex_mem1_result   (ex_mem1_result),
        .mem_wb0_reg_write(mem_wb0_reg_write),
        .mem_wb0_rd       (mem_wb0_rd),
        .mem_wb0_result   (mem_wb0_result),
        .mem_wb1_reg_write(mem_wb1_reg_write),
        .mem_wb1_rd       (mem_wb1_rd),
        .mem_wb1_result   (mem_wb1_result),
        .forwarded_alu0_a (fwd_alu0_a),
        .forwarded_alu0_b (fwd_alu0_b),
        .forwarded_store0 (fwd_store0),
        .forwarded_alu1_a (fwd_alu1_a),
        .forwarded_alu1_b (fwd_alu1_b),
        .forwarded_store1 (fwd_store1),
        .fwd0_a_src       (fwd0_a_src),
        .fwd0_b_src       (fwd0_b_src),
        .fwd1_a_src       (fwd1_a_src),
        .fwd1_b_src       (fwd1_b_src),
        .intra_cycle_fwd_a(intra_cycle_fwd_a),
        .intra_cycle_fwd_b(intra_cycle_fwd_b)
    );

    // -------------------------------------------------------------------------
    // 2. Hazard Unit Interface
    // -------------------------------------------------------------------------
    logic        id_slot0_valid, id_slot1_valid;
    logic [4:0]  id_slot0_rs1, id_slot0_rs2, id_slot0_rd;
    logic        id_slot0_uses_rs1, id_slot0_uses_rs2, id_slot0_reg_write;
    logic        id_slot0_mem_read, id_slot0_mem_write;
    logic        id_slot0_branch, id_slot0_jal, id_slot0_jalr;
    logic        id_slot0_pred_taken;
    logic [1:0]  id_slot0_mem_class;

    logic [4:0]  id_slot1_rs1, id_slot1_rs2, id_slot1_rd;
    logic        id_slot1_uses_rs1, id_slot1_uses_rs2, id_slot1_reg_write;
    logic        id_slot1_mem_read, id_slot1_mem_write;
    logic        id_slot1_branch, id_slot1_jal, id_slot1_jalr;
    logic [1:0]  id_slot1_mem_class;

    logic        hz_ex0_mem_read, hz_ex0_reg_write;
    logic [4:0]  hz_ex0_rd;
    logic        hz_ex1_mem_read, hz_ex1_reg_write;
    logic [4:0]  hz_ex1_rd;
    logic        hz_ex_redirect;

    logic [1:0]  hz_issue_count;
    logic        hz_slot0_issue_en, hz_slot1_issue_en;
    logic        hz_pc_write, hz_if_id_write, hz_flush_if_id, hz_flush_id_ex;
    logic        hz_raw_hazard_0_to_1, hz_waw_collision;
    logic        hz_load_use_hazard_0, hz_load_use_hazard_1;
    logic        hz_mem_class_conflict;

    hazard_unit_superscalar hz_dut (
        .id_slot0_valid     (id_slot0_valid),
        .id_slot0_rs1       (id_slot0_rs1),
        .id_slot0_rs2       (id_slot0_rs2),
        .id_slot0_rd        (id_slot0_rd),
        .id_slot0_uses_rs1  (id_slot0_uses_rs1),
        .id_slot0_uses_rs2  (id_slot0_uses_rs2),
        .id_slot0_reg_write (id_slot0_reg_write),
        .id_slot0_mem_read  (id_slot0_mem_read),
        .id_slot0_mem_write (id_slot0_mem_write),
        .id_slot0_branch    (id_slot0_branch),
        .id_slot0_jal       (id_slot0_jal),
        .id_slot0_jalr      (id_slot0_jalr),
        .id_slot0_pred_taken(id_slot0_pred_taken),
        .id_slot0_mem_class (id_slot0_mem_class),

        .id_slot1_valid     (id_slot1_valid),
        .id_slot1_rs1       (id_slot1_rs1),
        .id_slot1_rs2       (id_slot1_rs2),
        .id_slot1_rd        (id_slot1_rd),
        .id_slot1_uses_rs1  (id_slot1_uses_rs1),
        .id_slot1_uses_rs2  (id_slot1_uses_rs2),
        .id_slot1_reg_write (id_slot1_reg_write),
        .id_slot1_mem_read  (id_slot1_mem_read),
        .id_slot1_mem_write (id_slot1_mem_write),
        .id_slot1_branch    (id_slot1_branch),
        .id_slot1_jal       (id_slot1_jal),
        .id_slot1_jalr      (id_slot1_jalr),
        .id_slot1_mem_class (id_slot1_mem_class),

        .ex0_mem_read       (hz_ex0_mem_read),
        .ex0_reg_write      (hz_ex0_reg_write),
        .ex0_rd             (hz_ex0_rd),
        .ex1_mem_read       (hz_ex1_mem_read),
        .ex1_reg_write      (hz_ex1_reg_write),
        .ex1_rd             (hz_ex1_rd),
        .ex_redirect        (hz_ex_redirect),

        .issue_count        (hz_issue_count),
        .slot0_issue_en     (hz_slot0_issue_en),
        .slot1_issue_en     (hz_slot1_issue_en),
        .pc_write           (hz_pc_write),
        .if_id_write        (hz_if_id_write),
        .flush_if_id        (hz_flush_if_id),
        .flush_id_ex        (hz_flush_id_ex),
        .raw_hazard_0_to_1  (hz_raw_hazard_0_to_1),
        .waw_collision      (hz_waw_collision),
        .load_use_hazard_0  (hz_load_use_hazard_0),
        .load_use_hazard_1  (hz_load_use_hazard_1),
        .mem_class_conflict (hz_mem_class_conflict)
    );

    // -------------------------------------------------------------------------
    // 3. 4R/2W Register File Interface
    // -------------------------------------------------------------------------
    logic [4:0]  rf_rs1_0, rf_rs2_0, rf_rs1_1, rf_rs2_1;
    logic [31:0] rf_rdata1_0, rf_rdata2_0, rf_rdata1_1, rf_rdata2_1;
    logic        rf_we0, rf_we1;
    logic [4:0]  rf_rd_addr0, rf_rd_addr1;
    logic [31:0] rf_rd_data0, rf_rd_data1;

    register_file_4r2w rf_dut (
        .clk      (clk),
        .rst      (rst),
        .rs1_addr0(rf_rs1_0),
        .rs2_addr0(rf_rs2_0),
        .rs1_data0(rf_rdata1_0),
        .rs2_data0(rf_rdata2_0),
        .rs1_addr1(rf_rs1_1),
        .rs2_addr1(rf_rs2_1),
        .rs1_data1(rf_rdata1_1),
        .rs2_data1(rf_rdata2_1),
        .we0      (rf_we0),
        .rd_addr0 (rf_rd_addr0),
        .rd_data0 (rf_rd_data0),
        .we1      (rf_we1),
        .rd_addr1 (rf_rd_addr1),
        .rd_data1 (rf_rd_data1)
    );

    // -------------------------------------------------------------------------
    // 4. MemClass Arbiter Interface
    // -------------------------------------------------------------------------
    logic        arb_s0_valid, arb_s1_valid;
    logic        arb_s0_read, arb_s0_write;
    logic [31:0] arb_s0_addr, arb_s0_wdata;
    logic [2:0]  arb_s0_funct3;
    logic [1:0]  arb_s0_class;

    logic        arb_s1_read, arb_s1_write;
    logic [31:0] arb_s1_addr, arb_s1_wdata;
    logic [2:0]  arb_s1_funct3;
    logic [1:0]  arb_s1_class;

    logic [31:0] arb_ram_rdata0, arb_ram_rdata1;
    logic [31:0] arb_npu_rdata0, arb_npu_rdata1;
    logic [31:0] arb_final_rdata0, arb_final_rdata1;
    logic        arb_collision, arb_s2l;

    mem_class_arbiter arb_dut (
        .slot0_valid           (arb_s0_valid),
        .slot0_mem_read        (arb_s0_read),
        .slot0_mem_write       (arb_s0_write),
        .slot0_addr            (arb_s0_addr),
        .slot0_write_data      (arb_s0_wdata),
        .slot0_funct3          (arb_s0_funct3),
        .slot0_mem_class       (arb_s0_class),

        .slot1_valid           (arb_s1_valid),
        .slot1_mem_read        (arb_s1_read),
        .slot1_mem_write       (arb_s1_write),
        .slot1_addr            (arb_s1_addr),
        .slot1_write_data      (arb_s1_wdata),
        .slot1_funct3          (arb_s1_funct3),
        .slot1_mem_class       (arb_s1_class),

        .ram_read_data0        (arb_ram_rdata0),
        .ram_read_data1        (arb_ram_rdata1),
        .npu_read_data0        (arb_npu_rdata0),
        .npu_read_data1        (arb_npu_rdata1),

        .ram_write0            (),
        .ram_addr0             (),
        .ram_write_data0       (),
        .ram_funct3_0          (),

        .ram_write1            (),
        .ram_addr1             (),
        .ram_write_data1       (),
        .ram_funct3_1          (),

        .npu_write0            (),
        .npu_read0             (),
        .npu_addr0             (),
        .npu_write_data0       (),

        .npu_write1            (),
        .npu_read1             (),
        .npu_addr1             (),
        .npu_write_data1       (),

        .final_read_data0      (arb_final_rdata0),
        .final_read_data1      (arb_final_rdata1),

        .is_npu_addr0          (),
        .is_npu_addr1          (),
        .mem_collision_detected(arb_collision),
        .store_to_load_fwd     (arb_s2l)
    );

    always #5 clk = ~clk;

    integer test_errors = 0;

    task check(input logic condition, input string test_name);
        if (!condition) begin
            $display("FAILED: %s", test_name);
            test_errors++;
        end else begin
            $display("PASS: %s", test_name);
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        #20;
        rst = 0;
        #10;

        $display("\n=======================================================");
        $display("STARTING PHASE 6: SUPERSCALAR HAZARD STRESS REGRESSION");
        $display("=======================================================\n");

        // ---------------------------------------------------------------------
        // STRESS TEST 1: Intra-Cycle ALU0 -> ALU1 Forwarding (RAW Dependency)
        // ---------------------------------------------------------------------
        $display("--> Stress Test 1: Intra-Cycle ALU0 -> ALU1 Forwarding...");
        ex0_reg_write = 1'b1;
        ex0_mem_read  = 1'b0;
        ex0_rd        = 5'd5;
        ex0_alu_result = 32'hAAAA_BBBB;

        ex_mem0_reg_write = 1'b0; ex_mem0_rd = 5'd0; ex_mem0_result = 32'd0;
        ex_mem1_reg_write = 1'b0; ex_mem1_rd = 5'd0; ex_mem1_result = 32'd0;
        mem_wb0_reg_write = 1'b0; mem_wb0_rd = 5'd0; mem_wb0_result = 32'd0;
        mem_wb1_reg_write = 1'b0; mem_wb1_rd = 5'd0; mem_wb1_result = 32'd0;

        id_ex0_rs1 = 5'd1; id_ex0_rs2 = 5'd2; id_ex0_uses_rs1 = 1'b1; id_ex0_uses_rs2 = 1'b1;
        id_ex1_rs1 = 5'd5; id_ex1_rs2 = 5'd3; id_ex1_uses_rs1 = 1'b1; id_ex1_uses_rs2 = 1'b1; // Slot 1 reads x5!
        id_ex0_rs1_data = 32'd0; id_ex0_rs2_data = 32'd0; id_ex1_rs1_data = 32'd0; id_ex1_rs2_data = 32'd0;
        #1;
        check(intra_cycle_fwd_a == 1'b1, "Stress 1a: Intra-cycle ALU0 -> ALU1 bypass flag asserted");
        check(fwd1_a_src == 3'd5,        "Stress 1b: Forwarding mux selects EX0 direct result (0xAAAA_BBBB)");
        check(fwd_alu1_a == 32'hAAAA_BBBB, "Stress 1c: Slot 1 receives ALU0 result immediately in same cycle");

        // ---------------------------------------------------------------------
        // STRESS TEST 2: Inter-Stage Load-Use Hazard & 1-Cycle Stall Bubble
        // ---------------------------------------------------------------------
        $display("\n--> Stress Test 2: Load-Use Hazard & Bubble Injection...");
        id_slot0_valid = 1'b1; id_slot0_rs1 = 5'd10; id_slot0_uses_rs1 = 1'b1; id_slot0_uses_rs2 = 1'b0;
        id_slot0_rd = 5'd1; id_slot0_reg_write = 1'b1; id_slot0_mem_read = 1'b0; id_slot0_mem_write = 1'b0;
        id_slot0_branch = 1'b0; id_slot0_jal = 1'b0; id_slot0_jalr = 1'b0; id_slot0_pred_taken = 1'b0;
        id_slot0_mem_class = 2'b00;

        id_slot1_valid = 1'b1; id_slot1_rs1 = 5'd2; id_slot1_rs2 = 5'd3;
        id_slot1_uses_rs1 = 1'b1; id_slot1_uses_rs2 = 1'b1; id_slot1_rd = 5'd4;
        id_slot1_reg_write = 1'b1; id_slot1_mem_read = 1'b0; id_slot1_mem_write = 1'b0;
        id_slot1_branch = 1'b0; id_slot1_jal = 1'b0; id_slot1_jalr = 1'b0;
        id_slot1_mem_class = 2'b00;

        hz_ex0_mem_read = 1'b1; hz_ex0_rd = 5'd10; hz_ex0_reg_write = 1'b1;
        hz_ex1_mem_read = 1'b0; hz_ex1_rd = 5'd0;  hz_ex1_reg_write = 1'b0;
        hz_ex_redirect  = 1'b0;
        #1;
        check(hz_load_use_hazard_0 == 1'b1, "Stress 2a: Load-Use hazard detected on Slot 0");
        check(hz_pc_write == 1'b0,          "Stress 2b: PC frozen (pc_write == 0)");
        check(hz_flush_id_ex == 1'b1,       "Stress 2c: ID/EX pipeline register flushed (bubble inserted)");
        check(hz_issue_count == 2'd0,       "Stress 2d: Issue count truncated to 0 (full stall)");

        // ---------------------------------------------------------------------
        // STRESS TEST 3: WAW Output Hazard Priority (Slot 1 Overwrites Slot 0)
        // ---------------------------------------------------------------------
        $display("\n--> Stress Test 3: WAW Output Hazard Commitment Priority...");
        @(posedge clk);
        rf_we0      = 1'b1;
        rf_rd_addr0 = 5'd7;
        rf_rd_data0 = 32'h1111_1111; // Slot 0 older value

        rf_we1      = 1'b1;
        rf_rd_addr1 = 5'd7;
        rf_rd_data1 = 32'h2222_2222; // Slot 1 younger value (program order)
        @(posedge clk);
        rf_we0 = 1'b0;
        rf_we1 = 1'b0;
        rf_rs1_0 = 5'd7;
        #1;
        check(rf_rdata1_0 == 32'h2222_2222, "Stress 3: Slot 1 (younger) overwrites Slot 0 in WAW collision");

        // ---------------------------------------------------------------------
        // STRESS TEST 4: Speculative Branch Misprediction & Synchronous Flush
        // ---------------------------------------------------------------------
        $display("\n--> Stress Test 4: Speculative Branch Mispredict & Pipeline Flush...");
        hz_ex_redirect = 1'b1;
        #1;
        check(hz_flush_if_id == 1'b1, "Stress 4a: IF/ID flushed on branch redirect");
        check(hz_flush_id_ex == 1'b1, "Stress 4b: ID/EX flushed on branch redirect");
        check(hz_pc_write == 1'b1,    "Stress 4c: PC update enabled to accept correct branch target");
        hz_ex_redirect = 1'b0;

        // ---------------------------------------------------------------------
        // STRESS TEST 5: Intra-Stage Store-to-Load Forwarding in MEM Stage
        // ---------------------------------------------------------------------
        $display("\n--> Stress Test 5: Intra-Stage Store-to-Load Forwarding in MEM...");
        arb_s0_valid = 1'b1; arb_s0_write = 1'b1; arb_s0_read = 1'b0;
        arb_s0_addr  = 32'h0000_0040; arb_s0_wdata = 32'h7777_8888; arb_s0_funct3 = 3'b010;
        arb_s0_class = 2'b01; // MEM_STORE

        arb_s1_valid = 1'b1; arb_s1_write = 1'b0; arb_s1_read = 1'b1;
        arb_s1_addr  = 32'h0000_0040; arb_s1_funct3 = 3'b010;
        arb_s1_class = 2'b00; // MEM_NONE

        arb_ram_rdata0 = 32'hDEAD_BEEF; arb_ram_rdata1 = 32'hDEAD_BEEF;
        arb_npu_rdata0 = 32'd0; arb_npu_rdata1 = 32'd0;
        #1;
        check(arb_s2l == 1'b1, "Stress 5a: Matching word address detected for S2L forwarding");
        check(arb_final_rdata1 == 32'h7777_8888, "Stress 5b: Slot 1 receives forwarded store data directly");

        // ---------------------------------------------------------------------
        // STRESS TEST 6: Store-Store Memory Conflict & Serialization
        // ---------------------------------------------------------------------
        $display("\n--> Stress Test 6: Store-Store Structural Hazard & Serialization...");
        arb_s0_valid = 1'b1; arb_s0_write = 1'b1; arb_s0_class = 2'b01; // MEM_STORE
        arb_s1_valid = 1'b1; arb_s1_write = 1'b1; arb_s1_class = 2'b01; // MEM_STORE
        #1;
        check(arb_collision == 1'b1, "Stress 6a: Store-Store structural collision flagged");

        id_slot0_mem_class = 2'b01; id_slot1_mem_class = 2'b01;
        hz_ex0_mem_read = 1'b0; hz_ex1_mem_read = 1'b0;
        #1;
        check(hz_mem_class_conflict == 1'b1, "Stress 6b: Hazard unit serializes stores into separate cycles");
        check(hz_issue_count == 2'd1,        "Stress 6c: Single-issue advance (+4) enforced");

        // Summary
        $display("\n=======================================================");
        if (test_errors == 0) begin
            $display("ALL 6 SUPERSCALAR HAZARD STRESS TESTS PASSED (0 ERRORS)");
        end else begin
            $display("HAZARD STRESS TEST FAILED WITH %0d ERRORS", test_errors);
        end
        $display("=======================================================\n");

        $finish;
    end

endmodule
