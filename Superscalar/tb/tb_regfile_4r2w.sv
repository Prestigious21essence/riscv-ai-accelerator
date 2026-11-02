// =============================================================================
// Testbench: tb_regfile_4r2w
// Description: Comprehensive self-checking verification for register_file_4r2w.
//              Verifies:
//              1. Reset and x0 hardwired to zero
//              2. 4 independent simultaneous read ports
//              3. 2 independent simultaneous write ports
//              4. Internal write-to-read forwarding (Write-First Bypass)
//              5. Simultaneous write-first forwarding across all 4 read ports
//              6. WAW collision priority resolution (Port 1 overwrites Port 0)
//              7. x0 write suppression
// =============================================================================

`timescale 1ns/1ps

module tb_regfile_4r2w;
    logic        clk = 0;
    logic        rst = 1;

    // Read Ports
    logic [4:0]  rs1_addr0, rs2_addr0;
    logic [31:0] rs1_data0, rs2_data0;
    logic [4:0]  rs1_addr1, rs2_addr1;
    logic [31:0] rs1_data1, rs2_data1;

    // Write Ports
    logic        we0;
    logic [4:0]  rd_addr0;
    logic [31:0] rd_data0;
    logic        we1;
    logic [4:0]  rd_addr1;
    logic [31:0] rd_data1;

    int errors = 0;
    always #5 clk = ~clk; // 100MHz clock

    register_file_4r2w dut (
        .clk(clk), .rst(rst),
        .rs1_addr0(rs1_addr0), .rs2_addr0(rs2_addr0), .rs1_data0(rs1_data0), .rs2_data0(rs2_data0),
        .rs1_addr1(rs1_addr1), .rs2_addr1(rs2_addr1), .rs1_data1(rs1_data1), .rs2_data1(rs2_data1),
        .we0(we0), .rd_addr0(rd_addr0), .rd_data0(rd_data0),
        .we1(we1), .rd_addr1(rd_addr1), .rd_data1(rd_data1)
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
        $display("STARTING 4R/2W REGISTER FILE SELF-CHECKING TESTBENCH");
        $display("=======================================================\n");

        // Initialize inputs
        rs1_addr0 = 0; rs2_addr0 = 0;
        rs1_addr1 = 0; rs2_addr1 = 0;
        we0 = 0; rd_addr0 = 0; rd_data0 = 0;
        we1 = 0; rd_addr1 = 0; rd_data1 = 0;

        @(negedge clk);
        rst = 1;
        @(negedge clk);
        rst = 0;

        // ---------------------------------------------------------------------
        // Test 1: Reset state & x0 is always 0
        // ---------------------------------------------------------------------
        rs1_addr0 = 5'd0; rs2_addr0 = 5'd1;
        rs1_addr1 = 5'd2; rs2_addr1 = 5'd3;
        #1;
        check("Test 1a: x0 reads 0 on Port 0", rs1_data0 == 32'd0);
        check("Test 1b: x1 reads 0 after reset", rs2_data0 == 32'd0);
        check("Test 1c: x2 reads 0 after reset", rs1_data1 == 32'd0);
        check("Test 1d: x3 reads 0 after reset", rs2_data1 == 32'd0);

        // ---------------------------------------------------------------------
        // Test 2: Dual simultaneous synchronous writes to distinct registers
        // ---------------------------------------------------------------------
        @(negedge clk);
        we0 = 1; rd_addr0 = 5'd10; rd_data0 = 32'h1010_1010;
        we1 = 1; rd_addr1 = 5'd20; rd_data1 = 32'h2020_2020;
        @(negedge clk);
        we0 = 0; we1 = 0;

        rs1_addr0 = 5'd10; rs2_addr0 = 5'd20;
        rs1_addr1 = 5'd10; rs2_addr1 = 5'd20;
        #1;
        check("Test 2a: Slot 0 reads x10 correctly", rs1_data0 == 32'h1010_1010);
        check("Test 2b: Slot 0 reads x20 correctly", rs2_data0 == 32'h2020_2020);
        check("Test 2c: Slot 1 reads x10 correctly", rs1_data1 == 32'h1010_1010);
        check("Test 2d: Slot 1 reads x20 correctly", rs2_data1 == 32'h2020_2020);

        // ---------------------------------------------------------------------
        // Test 3: 4 simultaneous distinct register reads
        // ---------------------------------------------------------------------
        @(negedge clk);
        we0 = 1; rd_addr0 = 5'd1; rd_data0 = 32'h0000_0001;
        we1 = 1; rd_addr1 = 5'd2; rd_data1 = 32'h0000_0002;
        @(negedge clk);
        we0 = 1; rd_addr0 = 5'd3; rd_data0 = 32'h0000_0003;
        we1 = 1; rd_addr1 = 5'd4; rd_data1 = 32'h0000_0004;
        @(negedge clk);
        we0 = 0; we1 = 0;

        rs1_addr0 = 5'd1; rs2_addr0 = 5'd2;
        rs1_addr1 = 5'd3; rs2_addr1 = 5'd4;
        #1;
        check("Test 3: 4 distinct simultaneous reads (x1,x2,x3,x4)",
              (rs1_data0 == 32'd1) && (rs2_data0 == 32'd2) &&
              (rs1_data1 == 32'd3) && (rs2_data1 == 32'd4));

        // ---------------------------------------------------------------------
        // Test 4: Internal write-first bypass (Write Port 0 to Read Ports)
        // ---------------------------------------------------------------------
        @(negedge clk);
        we0 = 1; rd_addr0 = 5'd15; rd_data0 = 32'hBEEF_CAFE;
        we1 = 0;
        rs1_addr0 = 5'd15; // Reading x15 while Port 0 writes x15 in same cycle!
        rs2_addr1 = 5'd15; // Reading x15 on Slot 1 as well!
        #1;
        check("Test 4a: Write-first bypass from Port 0 to rs1_data0", rs1_data0 == 32'hBEEF_CAFE);
        check("Test 4b: Write-first bypass from Port 0 to rs2_data1", rs2_data1 == 32'hBEEF_CAFE);
        @(negedge clk);
        we0 = 0;

        // ---------------------------------------------------------------------
        // Test 5: Internal write-first bypass (Write Port 1 to Read Ports)
        // ---------------------------------------------------------------------
        @(negedge clk);
        we0 = 0;
        we1 = 1; rd_addr1 = 5'd16; rd_data1 = 32'hDEAD_BEEF;
        rs2_addr0 = 5'd16; // Reading x16 on Slot 0 while Port 1 writes in same cycle!
        rs1_addr1 = 5'd16; // Reading x16 on Slot 1!
        #1;
        check("Test 5a: Write-first bypass from Port 1 to rs2_data0", rs2_data0 == 32'hDEAD_BEEF);
        check("Test 5b: Write-first bypass from Port 1 to rs1_data1", rs1_data1 == 32'hDEAD_BEEF);
        @(negedge clk);
        we1 = 0;

        // ---------------------------------------------------------------------
        // Test 6: WAW Collision & Priority Resolution
        // Both Port 0 and Port 1 write to the SAME register x25 in the same cycle.
        // Port 1 (Slot 1) MUST have higher priority!
        // ---------------------------------------------------------------------
        @(negedge clk);
        we0 = 1; rd_addr0 = 5'd25; rd_data0 = 32'hAAAA_AAAA;
        we1 = 1; rd_addr1 = 5'd25; rd_data1 = 32'h5555_5555;
        rs1_addr0 = 5'd25;
        rs1_addr1 = 5'd25;
        #1;
        check("Test 6a: Bypass in same cycle resolves WAW collision (Port 1 wins)",
              (rs1_data0 == 32'h5555_5555) && (rs1_data1 == 32'h5555_5555));

        // Latch on clock edge and verify storage
        @(negedge clk);
        we0 = 0; we1 = 0;
        rs1_addr0 = 5'd25; rs2_addr1 = 5'd25;
        #1;
        check("Test 6b: Synchronous register array stores Port 1 value (0x55555555)",
              (rs1_data0 == 32'h5555_5555) && (rs2_data1 == 32'h5555_5555));

        // ---------------------------------------------------------------------
        // Test 7: x0 Write Suppression
        // Try writing non-zero to x0 from both Port 0 and Port 1
        // ---------------------------------------------------------------------
        @(negedge clk);
        we0 = 1; rd_addr0 = 5'd0; rd_data0 = 32'hFFFF_FFFF;
        we1 = 1; rd_addr1 = 5'd0; rd_data1 = 32'hFFFF_FFFF;
        rs1_addr0 = 5'd0; rs2_addr0 = 5'd0;
        rs1_addr1 = 5'd0; rs2_addr1 = 5'd0;
        #1;
        check("Test 7a: x0 bypass returns 0 even when writing non-zero",
              (rs1_data0 == 32'd0) && (rs2_data0 == 32'd0) &&
              (rs1_data1 == 32'd0) && (rs2_data1 == 32'd0));

        @(negedge clk);
        we0 = 0; we1 = 0;
        #1;
        check("Test 7b: x0 array value remains 0 after clock edge",
              (rs1_data0 == 32'd0) && (rs1_data1 == 32'd0));

        // ---------------------------------------------------------------------
        // Final Summary
        // ---------------------------------------------------------------------
        if (errors == 0) begin
            $display("\n=======================================================");
            $display("ALL 4R/2W REGISTER FILE CHECKS PASSED PERFECTLY (0 ERRORS)");
            $display("=======================================================\n");
        end else begin
            $display("\nFAILED: %0d errors detected in register file.\n", errors);
        end
        $finish;
    end
endmodule

