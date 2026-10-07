// =============================================================================
// Level 3 & Level 4 Testbench: End-to-End 32x32 Tiled GEMM Benchmark
// File: tb_pipeline_npu_benchmark32.sv
//
// Description:
//   Executes the full 32x32 matrix multiplication benchmark from matmul_32_t2_s32_O2.c
//   on the RV32I Always-Stall Pipeline Core accelerated by the NPU MMIO coprocessor.
//
//   Memory Configuration:
//     - 1 MB Unified Address Space (MEM_WORDS = 262,144 words)
//     - Matrix A: byte 0x0000_0000 (words 0..1023)
//     - Matrix B: byte 0x0000_1000 (words 1024..2047)
//     - Matrix C: byte 0x000C_8000 (words 204,800..205,823)
//     - Completion Vector: PC == 0x0000000C (j 0x0000000C)
//
//   Verification:
//     - Checks all 1,024 computed 32-bit signed words against mathematical Golden C
//     - Measures total CPU+NPU hardware execution cycles
// =============================================================================

`timescale 1ns / 1ps

module tb_pipeline_npu_benchmark32;

    logic clk = 0;
    logic rst = 1;

    // 100MHz clock
    always #5 clk = ~clk;

    // 1 MB Unified RAM (262,144 32-bit words)
    localparam RAM_WORDS = 262144;
    localparam C_BASE_WORD = 32'h000C8000 >> 2; // 204,800

    rv32i_pipeline_stallbranch_core #(.MEM_WORDS(RAM_WORDS)) core_dut (
        .clk(clk),
        .rst(rst)
    );

    // Golden model array
    logic signed [31:0] golden_c [0:1023];
    logic signed [31:0] data_a   [0:1023];
    logic signed [31:0] data_b   [0:1023];

    integer i;
    integer errors = 0;
    integer total_cycles = 0;

    initial begin
        $display("================================================================================");
        $display("      STARTING LEVEL 3: 32x32 TILED MATRIX MULTIPLICATION BENCHMARK            ");
        $display("================================================================================");

        // Preload Data Memory with Benchmark Matrices A and B
        $readmemh("data_a.hex", data_a);
        $readmemh("data_b.hex", data_b);
        $readmemh("golden_c.hex", golden_c);

        for (i = 0; i < 1024; i++) begin
            core_dut.dmem.mem[i]        = data_a[i];        // Matrix A at 0x0000_0000
            core_dut.dmem.mem[1024 + i] = data_b[i];        // Matrix B at 0x0000_1000
            core_dut.dmem.mem[C_BASE_WORD + i] = 32'd0;    // Clear Matrix C at 0x000C_8000
        end

        $display("Preloaded 1,024 words of Matrix A at 0x0000_0000");
        $display("Preloaded 1,024 words of Matrix B at 0x0000_1000");
        $display("Preloaded 1,024 words of Golden Reference C");

        // Release reset
        @(negedge clk);
        rst = 0;

        // Run until completion vector PC == 0x0000000C
        while (core_dut.if_pc !== 32'h0000_000C && total_cycles < 300000) begin
            @(posedge clk);
            total_cycles++;
        end

        if (core_dut.if_pc === 32'h0000_000C) begin
            $display("\nProgram reached completion vector at PC = 0x0000000C in %0d clock cycles!", total_cycles);
        end else begin
            $display("\nWARNING: Reached cycle limit (%0d cycles) at PC = 0x%08h", total_cycles, core_dut.if_pc);
        end

        // ---------------------------------------------------------------------
        // Verify all 1,024 computed words in Destination Matrix C
        // ---------------------------------------------------------------------
        $display("\n[Verification] Comparing Result Matrix C (0x000C8000) against Golden Model:");
        for (i = 0; i < 1024; i++) begin
            logic signed [31:0] actual;
            actual = core_dut.dmem.mem[C_BASE_WORD + i];
            if (actual !== golden_c[i]) begin
                if (errors < 10) begin
                    $display("FAIL at word %0d (row %0d, col %0d): Expected %0d, Got %0d",
                             i, i / 32, i % 32, golden_c[i], actual);
                end
                errors++;
            end
        end

        // Display sample elements
        $display("Sample Check:");
        $display("  C[0,  0]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 0]),  golden_c[0]);
        $display("  C[0,  1]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 1]),  golden_c[1]);
        $display("  C[0,  2]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 2]),  golden_c[2]);
        $display("  C[0,  3]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 3]),  golden_c[3]);
        $display("  C[31, 28]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 1020]), golden_c[1020]);
        $display("  C[31, 29]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 1021]), golden_c[1021]);
        $display("  C[31, 30]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 1022]), golden_c[1022]);
        $display("  C[31, 31]: Actual = %0d, Expected = %0d", $signed(core_dut.dmem.mem[C_BASE_WORD + 1023]), golden_c[1023]);

        $display("\n================================================================================");
        if (errors == 0) begin
            $display("       ALL 1,024/1,024 WORDS MATCHED EXACTLY (0 ERRORS)                        ");
            $display("       32x32 BENCHMARK FULLY VERIFIED ON RV32I + NPU COPROCESSOR!               ");
            $display("================================================================================");
            $finish(0);
        end else begin
            $display("       BENCHMARK FAILED WITH %0d / 1024 MISMATCHES                             ", errors);
            $display("================================================================================");
            $finish(1);
        end
    end

endmodule
