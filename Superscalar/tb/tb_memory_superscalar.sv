// =============================================================================
// Testbench: tb_memory_superscalar
// Description: Comprehensive self-checking verification for Phase 4:
//              - True Dual-Port Data RAM (data_memory_dualport.sv)
//              - Memory Class Arbiter & Crossbar Interconnect (mem_class_arbiter.sv)
// =============================================================================

`timescale 1ns/1ps

module tb_memory_superscalar;
    logic clk = 0;
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
    // Signals for data_memory_dualport
    // -------------------------------------------------------------------------
    logic        dmem_we0, dmem_we1;
    logic [31:0] dmem_addr0, dmem_addr1;
    logic [31:0] dmem_wdata0, dmem_wdata1;
    logic [2:0]  dmem_funct3_0, dmem_funct3_1;
    logic [31:0] dmem_rdata0, dmem_rdata1;

    data_memory_dualport #(
        .MEM_WORDS(256)
    ) u_dmem_2p (
        .clk(clk),
        .mem_write0(dmem_we0), .addr0(dmem_addr0), .write_data0(dmem_wdata0),
        .funct3_0(dmem_funct3_0), .read_data0(dmem_rdata0),
        .mem_write1(dmem_we1), .addr1(dmem_addr1), .write_data1(dmem_wdata1),
        .funct3_1(dmem_funct3_1), .read_data1(dmem_rdata1)
    );

    // -------------------------------------------------------------------------
    // Signals for mem_class_arbiter
    // -------------------------------------------------------------------------
    logic        arb_s0_valid, arb_s0_mem_read, arb_s0_mem_write;
    logic [31:0] arb_s0_addr, arb_s0_write_data;
    logic [2:0]  arb_s0_funct3;
    logic [1:0]  arb_s0_mem_class;

    logic        arb_s1_valid, arb_s1_mem_read, arb_s1_mem_write;
    logic [31:0] arb_s1_addr, arb_s1_write_data;
    logic [2:0]  arb_s1_funct3;
    logic [1:0]  arb_s1_mem_class;

    logic [31:0] arb_ram_rdata0, arb_ram_rdata1;
    logic [31:0] arb_npu_rdata0, arb_npu_rdata1;

    logic        arb_ram_write0, arb_ram_write1;
    logic [31:0] arb_ram_addr0, arb_ram_addr1;
    logic [31:0] arb_ram_write_data0, arb_ram_write_data1;
    logic [2:0]  arb_ram_funct3_0, arb_ram_funct3_1;

    logic        arb_npu_write0, arb_npu_read0, arb_npu_write1, arb_npu_read1;
    logic [31:0] arb_npu_addr0, arb_npu_addr1;
    logic [31:0] arb_npu_write_data0, arb_npu_write_data1;

    logic [31:0] arb_final_rdata0, arb_final_rdata1;
    logic        arb_is_npu_addr0, arb_is_npu_addr1;
    logic        arb_mem_collision, arb_store_to_load_fwd;

    mem_class_arbiter u_arbiter (
        .slot0_valid(arb_s0_valid), .slot0_mem_read(arb_s0_mem_read), .slot0_mem_write(arb_s0_mem_write),
        .slot0_addr(arb_s0_addr), .slot0_write_data(arb_s0_write_data), .slot0_funct3(arb_s0_funct3),
        .slot0_mem_class(arb_s0_mem_class),

        .slot1_valid(arb_s1_valid), .slot1_mem_read(arb_s1_mem_read), .slot1_mem_write(arb_s1_mem_write),
        .slot1_addr(arb_s1_addr), .slot1_write_data(arb_s1_write_data), .slot1_funct3(arb_s1_funct3),
        .slot1_mem_class(arb_s1_mem_class),

        .ram_read_data0(arb_ram_rdata0), .ram_read_data1(arb_ram_rdata1),
        .npu_read_data0(arb_npu_rdata0), .npu_read_data1(arb_npu_rdata1),

        .ram_write0(arb_ram_write0), .ram_addr0(arb_ram_addr0),
        .ram_write_data0(arb_ram_write_data0), .ram_funct3_0(arb_ram_funct3_0),
        .ram_write1(arb_ram_write1), .ram_addr1(arb_ram_addr1),
        .ram_write_data1(arb_ram_write_data1), .ram_funct3_1(arb_ram_funct3_1),

        .npu_write0(arb_npu_write0), .npu_read0(arb_npu_read0),
        .npu_addr0(arb_npu_addr0), .npu_write_data0(arb_npu_write_data0),
        .npu_write1(arb_npu_write1), .npu_read1(arb_npu_read1),
        .npu_addr1(arb_npu_addr1), .npu_write_data1(arb_npu_write_data1),

        .final_read_data0(arb_final_rdata0), .final_read_data1(arb_final_rdata1),
        .is_npu_addr0(arb_is_npu_addr0), .is_npu_addr1(arb_is_npu_addr1),
        .mem_collision_detected(arb_mem_collision),
        .store_to_load_fwd(arb_store_to_load_fwd)
    );

    initial begin
        $display("\n=======================================================");
        $display("STARTING PHASE 4 SUPERSCALAR MEMORY TESTBENCH");
        $display("=======================================================\n");

        // ---------------------------------------------------------------------
        // Test 1: Dual Simultaneous Synchronous Writes to Distinct Words
        // ---------------------------------------------------------------------
        @(negedge clk);
        dmem_we0 = 1; dmem_addr0 = 32'h0000_0010; dmem_wdata0 = 32'hAAAA_1010; dmem_funct3_0 = 3'b010; // SW
        dmem_we1 = 1; dmem_addr1 = 32'h0000_0020; dmem_wdata1 = 32'hBBBB_2020; dmem_funct3_1 = 3'b010; // SW
        @(negedge clk);
        dmem_we0 = 0; dmem_we1 = 0;

        // Verify with True Dual Simultaneous Reads
        dmem_addr0 = 32'h0000_0010; dmem_funct3_0 = 3'b010; // LW
        dmem_addr1 = 32'h0000_0020; dmem_funct3_1 = 3'b010; // LW
        #1;
        check("Test 1a: Port 0 reads 0xAAAA1010 from addr 0x10", dmem_rdata0 == 32'hAAAA_1010);
        check("Test 1b: Port 1 reads 0xBBBB2020 from addr 0x20", dmem_rdata1 == 32'hBBBB_2020);

        // ---------------------------------------------------------------------
        // Test 2: Simultaneous Dual Reads to the Exact Same Word
        // ---------------------------------------------------------------------
        dmem_addr0 = 32'h0000_0010;
        dmem_addr1 = 32'h0000_0010;
        #1;
        check("Test 2: Both Port 0 and Port 1 read identical word simultaneously",
              (dmem_rdata0 == 32'hAAAA_1010) && (dmem_rdata1 == 32'hAAAA_1010));

        // ---------------------------------------------------------------------
        // Test 3: Byte and Halfword Access Modes (SB, SH, LB, LBU, LH, LHU)
        // ---------------------------------------------------------------------
        // Write byte 0xFE to byte offset 1 of word at 0x30
        @(negedge clk);
        dmem_we0 = 1; dmem_addr0 = 32'h0000_0031; dmem_wdata0 = 32'h0000_00FE; dmem_funct3_0 = 3'b000; // SB
        dmem_we1 = 0;
        @(negedge clk);
        dmem_we0 = 0;

        // Port 0 reads as signed byte LB (sign-extended)
        dmem_addr0 = 32'h0000_0031; dmem_funct3_0 = 3'b000; // LB
        // Port 1 reads as unsigned byte LBU (zero-extended)
        dmem_addr1 = 32'h0000_0031; dmem_funct3_1 = 3'b100; // LBU
        #1;
        check("Test 3a: Port 0 signed byte read LB (0xFFFFFFFE)", dmem_rdata0 == 32'hFFFF_FFFE);
        check("Test 3b: Port 1 unsigned byte read LBU (0x000000FE)", dmem_rdata1 == 32'h0000_00FE);

        // ---------------------------------------------------------------------
        // Test 4: Write-First Read-During-Write Bypass in RAM
        // Port 0 writes word at 0x40; simultaneously Port 1 reads word at 0x40!
        // ---------------------------------------------------------------------
        @(negedge clk);
        dmem_we0 = 1; dmem_addr0 = 32'h0000_0040; dmem_wdata0 = 32'hCAFE_BABE; dmem_funct3_0 = 3'b010; // SW
        dmem_we1 = 0;
        dmem_addr1 = 32'h0000_0040; dmem_funct3_1 = 3'b010; // LW
        #1;
        check("Test 4: Port 1 receives write-first bypassed word (0xCAFEBABE)", dmem_rdata1 == 32'hCAFE_BABE);
        @(negedge clk);
        dmem_we0 = 0;

        // ---------------------------------------------------------------------
        // Test 5: Same-Word Dual Write Collision (Port 1 Priority)
        // Both Port 0 and Port 1 write to word at 0x50 in the same cycle!
        // ---------------------------------------------------------------------
        @(negedge clk);
        dmem_we0 = 1; dmem_addr0 = 32'h0000_0050; dmem_wdata0 = 32'h1111_1111; dmem_funct3_0 = 3'b010;
        dmem_we1 = 1; dmem_addr1 = 32'h0000_0050; dmem_wdata1 = 32'h2222_2222; dmem_funct3_1 = 3'b010;
        @(negedge clk);
        dmem_we0 = 0; dmem_we1 = 0;

        dmem_addr0 = 32'h0000_0050; dmem_funct3_0 = 3'b010;
        #1;
        check("Test 5: Port 1 (Slot 1) takes priority on same-word write collision", dmem_rdata0 == 32'h2222_2222);

        // =====================================================================
        // PART 2: Memory Class Arbiter Verification
        // =====================================================================
        $display("\n--> Testing mem_class_arbiter routing and conflicts...");

        // Test 6: Address Space Routing (RAM vs NPU aperture >= 0x8000_0000)
        arb_s0_valid = 1; arb_s0_mem_write = 1; arb_s0_mem_read = 0;
        arb_s0_addr = 32'h0000_1000; arb_s0_write_data = 32'h1234_5678;
        arb_s0_funct3 = 3'b010; arb_s0_mem_class = 2'b01; // MEM_STORE to RAM

        arb_s1_valid = 1; arb_s1_mem_write = 1; arb_s1_mem_read = 0;
        arb_s1_addr = 32'h8000_0100; arb_s1_write_data = 32'h9ABC_DEF0;
        arb_s1_funct3 = 3'b010; arb_s1_mem_class = 2'b10; // MEM_BANK_A to NPU
        #1;
        check("Test 6a: Slot 0 routed to Data RAM (is_npu_addr0 == 0)", !arb_is_npu_addr0 && arb_ram_write0);
        check("Test 6b: Slot 1 routed to NPU aperture (is_npu_addr1 == 1)", arb_is_npu_addr1 && arb_npu_write1);

        // Test 7: Memory Class Collision Detection (Store + Store)
        arb_s0_mem_class = 2'b01; // MEM_STORE
        arb_s1_mem_class = 2'b01; // MEM_STORE
        #1;
        check("Test 7: Store-Store collision flagged (mem_collision_detected == 1)", arb_mem_collision);

        // Test 8: Memory Class Non-Conflict (Store + Bank A Load)
        arb_s0_mem_class = 2'b01; // MEM_STORE
        arb_s1_mem_class = 2'b10; // MEM_BANK_A
        #1;
        check("Test 8: Store + Bank A Load co-issues without collision", !arb_mem_collision);

        // Test 9: Memory Class Non-Conflict (Bank A Load + Bank B Load)
        arb_s0_mem_class = 2'b10; // MEM_BANK_A
        arb_s1_mem_class = 2'b11; // MEM_BANK_B
        #1;
        check("Test 9: Bank A + Bank B concurrent streaming without collision", !arb_mem_collision);

        // Test 10: Store-to-Load Intra-Stage Forwarding in MEM
        // Slot 0 writes to word 0x0000_0200 in RAM.
        // Slot 1 reads from word 0x0000_0200 in RAM.
        arb_s0_valid = 1; arb_s0_mem_write = 1; arb_s0_mem_read = 0;
        arb_s0_addr = 32'h0000_0200; arb_s0_write_data = 32'h5555_6666;
        arb_s0_funct3 = 3'b010; arb_s0_mem_class = 2'b01;

        arb_s1_valid = 1; arb_s1_mem_write = 0; arb_s1_mem_read = 1;
        arb_s1_addr = 32'h0000_0200; arb_s1_funct3 = 3'b010;
        arb_s1_mem_class = 2'b00;

        arb_ram_rdata0 = 32'd0; arb_ram_rdata1 = 32'hDEAD_DEAD; // Stale data in RAM
        #1;
        check("Test 10a: Store-to-load forwarding detected on matching word address", arb_store_to_load_fwd);
        check("Test 10b: Slot 1 receives forwarded store data (0x55556666) instead of stale RAM data",
              arb_final_rdata1 == 32'h5555_6666);

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n=======================================================");
            $display("ALL PHASE 4 MEMORY & ARBITER CHECKS PASSED (0 ERRORS)");
            $display("=======================================================\n");
        end else begin
            $display("\nFAILED: %0d errors detected in Phase 4.\n", errors);
        end
        $finish;
    end
endmodule

