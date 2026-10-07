// =============================================================================
// Standalone Testbench for NPU Hardware Accelerator (npu_top.sv)
// File: tb_npu_top.sv
// =============================================================================

`timescale 1ns / 1ps

module tb_npu_top;

    logic        clk;
    logic        rst;
    logic        we;
    logic        re;
    logic [31:0] addr;
    logic [31:0] write_data;
    logic [31:0] read_data;

    // Clock generator: 100MHz (10ns period)
    always #5 clk = ~clk;

    // Instantiate Unit Under Test (UUT)
    npu_top uut (
        .clk        (clk),
        .rst        (rst),
        .we         (we),
        .re         (re),
        .addr       (addr),
        .write_data (write_data),
        .read_data  (read_data)
    );

    // Helper task: MMIO Write
    task mmio_write(input [31:0] target_addr, input [31:0] data);
        begin
            @(posedge clk);
            addr       = target_addr;
            write_data = data;
            we         = 1'b1;
            re         = 1'b0;
            @(posedge clk);
            we         = 1'b0;
        end
    endtask

    // Helper task: MMIO Read
    task mmio_read(input [31:0] target_addr, output [31:0] data);
        begin
            @(posedge clk);
            addr = target_addr;
            we   = 1'b0;
            re   = 1'b1;
            #1; // Combinational read delay
            data = read_data;
            @(posedge clk);
            re   = 1'b0;
        end
    endtask

    // Helper task: Poll until NPU completes
    task npu_wait_done;
        logic [31:0] status;
        begin
            status = 32'd0;
            while ((status & 32'h1) == 32'd0) begin
                mmio_read(32'h8000_0018, status);
            end
        end
    endtask

    // =========================================================================
    // Test Verification Logic
    // =========================================================================
    logic [31:0] val;
    integer i, j, k;
    integer errors = 0;

    // Golden model arrays
    integer gold_a [0:15][0:15];
    integer gold_b [0:15][0:15];
    integer gold_c [0:15][0:15];

    initial begin
        clk = 0;
        rst = 1;
        we  = 0;
        re  = 0;
        addr = 0;
        write_data = 0;

        #20;
        rst = 0;
        #10;

        $display("================================================================================");
        $display("                   STARTING NPU STANDALONE TESTBENCH                            ");
        $display("================================================================================");

        // ---------------------------------------------------------------------
        // Test 1: Register Read / Write Integrity
        // ---------------------------------------------------------------------
        $display("\n[Test 1] Verifying Dimension and Status Registers...");
        mmio_write(32'h8000_0000, 32'd4); // M = 4
        mmio_write(32'h8000_0004, 32'd4); // K = 4
        mmio_write(32'h8000_0008, 32'd4); // N = 4

        mmio_read(32'h8000_0000, val);
        if (val !== 32'd4) begin
            $display("FAIL: NPU_DIM_M expected 4, got %0d", val);
            errors++;
        end else $display("PASS: NPU_DIM_M = %0d", val);

        mmio_read(32'h8000_0004, val);
        if (val !== 32'd4) begin
            $display("FAIL: NPU_DIM_K expected 4, got %0d", val);
            errors++;
        end else $display("PASS: NPU_DIM_K = %0d", val);

        mmio_read(32'h8000_0008, val);
        if (val !== 32'd4) begin
            $display("FAIL: NPU_DIM_N expected 4, got %0d", val);
            errors++;
        end else $display("PASS: NPU_DIM_N = %0d", val);

        // ---------------------------------------------------------------------
        // Test 2: 4x4 Identity Matrix Multiplication (C = A * I == A)
        // ---------------------------------------------------------------------
        $display("\n[Test 2] Running 4x4 Identity Matrix Multiplication (C = A * I)...");
        // Load Matrix A: A[i, k] = i*4 + k + 1
        for (i = 0; i < 4; i++) begin
            for (k = 0; k < 4; k++) begin
                mmio_write(32'h8000_0100 + ((i * 16 + k) << 2), (i * 4 + k + 1));
            end
        end

        // Load Matrix B: Identity matrix
        for (k = 0; k < 4; k++) begin
            for (j = 0; j < 4; j++) begin
                mmio_write(32'h8000_0500 + ((k * 16 + j) << 2), (k == j) ? 32'd1 : 32'd0);
            end
        end

        // Trigger computation
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();

        // Read cycle count
        mmio_read(32'h8000_0020, val);
        $display("NPU reported calculation cycles: %0d (Expected 4x4x4 = 64 cycles)", val);

        // Verify Matrix C equals Matrix A
        for (i = 0; i < 4; i++) begin
            for (j = 0; j < 4; j++) begin
                mmio_read(32'h8000_0900 + ((i * 16 + j) << 2), val);
                if (val !== (i * 4 + j + 1)) begin
                    $display("FAIL: C[%0d,%0d] expected %0d, got %0d", i, j, (i * 4 + j + 1), val);
                    errors++;
                end
            end
        end
        if (errors == 0) $display("PASS: 4x4 Identity multiplication bit-exact match!");

        // ---------------------------------------------------------------------
        // Test 3: Full 16x16 Signed Matrix Multiplication Stress Test
        // ---------------------------------------------------------------------
        $display("\n[Test 3] Running Full 16x16 Signed Matrix Stress Test (4096 MACs)...");
        mmio_write(32'h8000_0000, 32'd16); // M = 16
        mmio_write(32'h8000_0004, 32'd16); // K = 16
        mmio_write(32'h8000_0008, 32'd16); // N = 16

        // Initialize pseudo-random matrices
        for (i = 0; i < 16; i++) begin
            for (k = 0; k < 16; k++) begin
                gold_a[i][k] = ((i * 7 + k * 13) % 21) - 10; // Values in range [-10, 10]
                mmio_write(32'h8000_0100 + ((i * 16 + k) << 2), gold_a[i][k]);
            end
        end

        for (k = 0; k < 16; k++) begin
            for (j = 0; j < 16; j++) begin
                gold_b[k][j] = ((k * 11 + j * 17) % 21) - 10; // Values in range [-10, 10]
                mmio_write(32'h8000_0500 + ((k * 16 + j) << 2), gold_b[k][j]);
            end
        end

        // Compute Golden C
        for (i = 0; i < 16; i++) begin
            for (j = 0; j < 16; j++) begin
                gold_c[i][j] = 0;
                for (k = 0; k < 16; k++) begin
                    gold_c[i][j] = gold_c[i][j] + (gold_a[i][k] * gold_b[k][j]);
                end
            end
        end

        // Trigger NPU
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();

        mmio_read(32'h8000_0020, val);
        $display("16x16 NPU computation completed in %0d cycles (Expected 16x16x16 = 4096 cycles)", val);

        // Verify all 256 results
        for (i = 0; i < 16; i++) begin
            for (j = 0; j < 16; j++) begin
                mmio_read(32'h8000_0900 + ((i * 16 + j) << 2), val);
                if ($signed(val) !== gold_c[i][j]) begin
                    $display("FAIL: C[%0d,%0d] expected %0d, got %0d", i, j, gold_c[i][j], $signed(val));
                    errors++;
                end
            end
        end
        if (errors == 0) $display("PASS: 16x16 Full Stress Test bit-exact match!");

        // ---------------------------------------------------------------------
        // Test 4: All-Zeroes Matrix Multiplication (C = 0 * 0 == 0)
        // ---------------------------------------------------------------------
        $display("\n[Test 4] Verifying All-Zeroes Matrix Multiplication...");
        mmio_write(32'h8000_0000, 32'd8); // M = 8
        mmio_write(32'h8000_0004, 32'd8); // K = 8
        mmio_write(32'h8000_0008, 32'd8); // N = 8

        // Preset C buffer with non-zero dirty data to ensure NPU actively clears/overwrites
        for (i = 0; i < 8; i++) begin
            for (j = 0; j < 8; j++) begin
                mmio_write(32'h8000_0900 + ((i * 16 + j) << 2), 32'hDEAD_BEEF);
            end
        end

        // Zero out A and B
        for (i = 0; i < 8; i++) begin
            for (k = 0; k < 8; k++) begin
                mmio_write(32'h8000_0100 + ((i * 16 + k) << 2), 32'd0);
            end
        end
        for (k = 0; k < 8; k++) begin
            for (j = 0; j < 8; j++) begin
                mmio_write(32'h8000_0500 + ((k * 16 + j) << 2), 32'd0);
            end
        end

        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();

        for (i = 0; i < 8; i++) begin
            for (j = 0; j < 8; j++) begin
                mmio_read(32'h8000_0900 + ((i * 16 + j) << 2), val);
                if (val !== 32'd0) begin
                    $display("FAIL: Zeroes test C[%0d,%0d] expected 0, got %0h", i, j, val);
                    errors++;
                end
            end
        end
        if (errors == 0) $display("PASS: All-zeroes matrix test passed with clean overwrite!");

        // ---------------------------------------------------------------------
        // Test 5: Dimension Sweeps (Non-Square Matrices)
        // ---------------------------------------------------------------------
        $display("\n[Test 5] Running Dimension Sweeps across Non-Square Matrices...");

        // 5.1: 1x1x1 Scalar MAC
        mmio_write(32'h8000_0000, 32'd1);
        mmio_write(32'h8000_0004, 32'd1);
        mmio_write(32'h8000_0008, 32'd1);
        mmio_write(32'h8000_0100, 32'd7);  // A[0,0] = 7
        mmio_write(32'h8000_0500, -32'd6); // B[0,0] = -6
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();
        mmio_read(32'h8000_0020, val);
        if (val !== 32'd1) begin
            $display("FAIL: 1x1x1 expected 1 cycle, got %0d", val);
            errors++;
        end
        mmio_read(32'h8000_0900, val);
        if ($signed(val) !== -42) begin
            $display("FAIL: 1x1x1 scalar product expected -42, got %0d", $signed(val));
            errors++;
        end else $display("PASS: 1x1x1 Scalar MAC bit-exact (7 * -6 = -42 in 1 cycle)");

        // 5.2: 1x16x1 Vector Dot Product
        mmio_write(32'h8000_0000, 32'd1);
        mmio_write(32'h8000_0004, 32'd16);
        mmio_write(32'h8000_0008, 32'd1);
        for (k = 0; k < 16; k++) begin
            mmio_write(32'h8000_0100 + (k << 2), k + 1);       // A[0,k] = k + 1
            mmio_write(32'h8000_0500 + ((k * 16) << 2), 32'd2); // B[k,0] = 2
        end
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();
        mmio_read(32'h8000_0020, val);
        if (val !== 32'd16) begin
            $display("FAIL: 1x16x1 expected 16 cycles, got %0d", val);
            errors++;
        end
        // Expected: sum(2 * (k+1) for k in 0..15) = 2 * (16 * 17 / 2) = 272
        mmio_read(32'h8000_0900, val);
        if (val !== 32'd272) begin
            $display("FAIL: 1x16x1 dot product expected 272, got %0d", val);
            errors++;
        end else $display("PASS: 1x16x1 Vector Dot Product bit-exact (sum = 272 in 16 cycles)");

        // 5.3: 3x7x5 Asymmetric Matrix Multiplication
        mmio_write(32'h8000_0000, 32'd3);
        mmio_write(32'h8000_0004, 32'd7);
        mmio_write(32'h8000_0008, 32'd5);
        for (i = 0; i < 3; i++) begin
            for (k = 0; k < 7; k++) begin
                gold_a[i][k] = (i + 1) * (k - 3);
                mmio_write(32'h8000_0100 + ((i * 16 + k) << 2), gold_a[i][k]);
            end
        end
        for (k = 0; k < 7; k++) begin
            for (j = 0; j < 5; j++) begin
                gold_b[k][j] = (k + 2) - (j * 3);
                mmio_write(32'h8000_0500 + ((k * 16 + j) << 2), gold_b[k][j]);
            end
        end
        for (i = 0; i < 3; i++) begin
            for (j = 0; j < 5; j++) begin
                gold_c[i][j] = 0;
                for (k = 0; k < 7; k++) begin
                    gold_c[i][j] = gold_c[i][j] + (gold_a[i][k] * gold_b[k][j]);
                end
            end
        end
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();
        mmio_read(32'h8000_0020, val);
        if (val !== 32'd105) begin // 3 * 7 * 5 = 105
            $display("FAIL: 3x7x5 expected 105 cycles, got %0d", val);
            errors++;
        end
        for (i = 0; i < 3; i++) begin
            for (j = 0; j < 5; j++) begin
                mmio_read(32'h8000_0900 + ((i * 16 + j) << 2), val);
                if ($signed(val) !== gold_c[i][j]) begin
                    $display("FAIL: 3x7x5 C[%0d,%0d] expected %0d, got %0d", i, j, gold_c[i][j], $signed(val));
                    errors++;
                end
            end
        end
        if (errors == 0) $display("PASS: 3x7x5 Asymmetric Matrix (105 cycles) bit-exact!");

        // ---------------------------------------------------------------------
        // Test 6: Reset Semantics
        // ---------------------------------------------------------------------
        $display("\n[Test 6] Verifying Hardware Reset Semantics...");
        // Start a 16x16 computation
        mmio_write(32'h8000_0000, 32'd16);
        mmio_write(32'h8000_0004, 32'd16);
        mmio_write(32'h8000_0008, 32'd16);
        mmio_write(32'h8000_000C, 32'd1);

        // Wait a few cycles, then issue NPU_RESET
        repeat (10) @(posedge clk);
        mmio_write(32'h8000_0010, 32'd1); // RESET

        // Verify state is immediately idle and status is 0
        mmio_read(32'h8000_0018, val);
        if (val !== 32'd0) begin
            $display("FAIL: NPU_STATUS after RESET expected 0, got %0h", val);
            errors++;
        end else $display("PASS: NPU_STATUS cleared to 0 after RESET");

        mmio_read(32'h8000_0020, val);
        if (val !== 32'd0) begin
            $display("FAIL: NPU_CYCLES after RESET expected 0, got %0d", val);
            errors++;
        end else $display("PASS: NPU_CYCLES reset to 0");

        // ---------------------------------------------------------------------
        // Test 7: Signed 32-bit Two's Complement Wrap-Around
        // ---------------------------------------------------------------------
        $display("\n[Test 7] Verifying Signed 32-bit Two's Complement Arithmetic & Wrap...");
        mmio_write(32'h8000_0000, 32'd1);
        mmio_write(32'h8000_0004, 32'd1);
        mmio_write(32'h8000_0008, 32'd1);

        // 1,000,000 * 3,000 = 3,000,000,000 (0xB2D0_5E00 = -1,294,967,296 in signed 32-bit)
        mmio_write(32'h8000_0100, 32'd1_000_000);
        mmio_write(32'h8000_0500, 32'd3_000);
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();
        mmio_read(32'h8000_0900, val);
        if (val !== 32'hB2D0_5E00) begin
            $display("FAIL: Overflow wrap expected 0xB2D05E00, got %0h", val);
            errors++;
        end else $display("PASS: Large value wrap-around matches 32-bit two's complement standard!");

        // ---------------------------------------------------------------------
        // Test 8: Back-to-Back Computations Without Reset
        // ---------------------------------------------------------------------
        $display("\n[Test 8] Running Back-to-Back Computations Without Reset...");
        // Run 1: 2x2 with sum = 10
        mmio_write(32'h8000_0000, 32'd2);
        mmio_write(32'h8000_0004, 32'd2);
        mmio_write(32'h8000_0008, 32'd2);
        mmio_write(32'h8000_0100, 32'd1); mmio_write(32'h8000_0104, 32'd2);
        mmio_write(32'h8000_0140, 32'd3); mmio_write(32'h8000_0144, 32'd4);
        mmio_write(32'h8000_0500, 32'd1); mmio_write(32'h8000_0504, 32'd0);
        mmio_write(32'h8000_0540, 32'd0); mmio_write(32'h8000_0544, 32'd1);
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();

        // Run 2: Immediately change dimensions and operands without issuing RESET
        mmio_write(32'h8000_0000, 32'd1);
        mmio_write(32'h8000_0004, 32'd1);
        mmio_write(32'h8000_0008, 32'd1);
        mmio_write(32'h8000_0100, 32'd50);
        mmio_write(32'h8000_0500, 32'd2);
        mmio_write(32'h8000_000C, 32'd1);
        npu_wait_done();
        mmio_read(32'h8000_0900, val);
        if (val !== 32'd100) begin
            $display("FAIL: Back-to-back expected 100, got %0d (accumulator leakage detected)", val);
            errors++;
        end else $display("PASS: Back-to-back computation cleanly re-initialized accumulator!");

        $display("\n================================================================================");
        if (errors == 0) begin
            $display("       ALL NPU STANDALONE VERIFICATION TESTS PASSED (0 ERRORS)                 ");
            $display("================================================================================");
            $finish(0);
        end else begin
            $display("       TEST FAILED WITH %0d MISMATCHES                                         ", errors);
            $display("================================================================================");
            $finish(1);
        end
    end

endmodule
