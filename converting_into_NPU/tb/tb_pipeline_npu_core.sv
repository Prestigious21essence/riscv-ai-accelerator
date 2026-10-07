// =============================================================================
// Full-System Testbench: RV32I Always-Stall Pipeline Core + NPU Coprocessor
// File: tb_pipeline_npu_core.sv
//
// Description:
//   Executes a complete software program on the RV32I pipeline core that:
//     1. Programs NPU dimensions (M=2, K=2, N=2) via MMIO
//     2. Streams Matrix A and Matrix B into NPU on-chip SRAM buffers
//     3. Triggers hardware matrix multiplication
//     4. Polls NPU_STATUS until hardware asserts completion
//     5. Reads back Matrix C from NPU on-chip SRAM into CPU registers
//     6. Reads back cycle counter measuring hardware execution time
// =============================================================================

`timescale 1ns / 1ps

module tb_pipeline_npu_core;

    logic clk = 0;
    logic rst = 1;
    int errors = 0;

    rv32i_pipeline_stallbranch_core core_dut (
        .clk(clk),
        .rst(rst)
    );

    always #5 clk = ~clk;

    task check(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual !== expected) begin
            $display("FAIL: %s -- expected %0d, got %0d", name, expected, actual);
            errors++;
        end else begin
            $display("PASS: %s = %0d", name, actual);
        end
    endtask

    initial begin
        $display("================================================================================");
        $display("          RUNNING FULL-SYSTEM CPU + NPU CO-SIMULATION TESTBENCH                 ");
        $display("================================================================================");

        @(negedge clk);
        rst = 0;

        // Run until the core completes computation and reaches termination loop
        repeat (150) @(negedge clk);

        $display("\n[Verification 1] Checking Concurrent CPU Execution (Non-Blocking Concurrency):");
        check("Concurrent ALU math x20 (imm 100)", core_dut.regfile.regs[20], 32'd100);
        check("Concurrent ALU math x21 (imm 200)", core_dut.regfile.regs[21], 32'd200);
        check("Concurrent ALU add x22 (100 + 200)", core_dut.regfile.regs[22], 32'd300);

        $display("\n[Verification 2] Checking Memory Stage Boundary & Isolation (RAM vs NPU MMIO):");
        check("Main RAM load x23 from addr 0x50", core_dut.regfile.regs[23], 32'd42);

        $display("\n[Verification 3] Checking NPU Computed Matrix C in Architectural Registers:");
        check("C[0,0] in x11 (3*1 + 4*3)", core_dut.regfile.regs[11], 32'd15);
        check("C[0,1] in x12 (3*2 + 4*4)", core_dut.regfile.regs[12], 32'd22);
        check("C[1,0] in x14 (5*1 + 6*3)", core_dut.regfile.regs[14], 32'd23);
        check("C[1,1] in x15 (5*2 + 6*4)", core_dut.regfile.regs[15], 32'd34);
        check("NPU Execution Cycles in x16", core_dut.regfile.regs[16], 32'd8);

        $display("\n================================================================================");
        if (errors == 0) begin
            $display("       ALL FULL-SYSTEM CPU + NPU TESTS PASSED (0 ERRORS)                       ");
            $display("================================================================================");
            $finish(0);
        end else begin
            $display("       FULL-SYSTEM TEST FAILED WITH %0d ERRORS                                 ", errors);
            $display("================================================================================");
            $finish(1);
        end
    end

endmodule
