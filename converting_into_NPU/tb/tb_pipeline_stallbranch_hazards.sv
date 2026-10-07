`timescale 1ns/1ps

module tb_pipeline_stallbranch_hazards;
    logic clk = 0;
    logic rst = 1;
    int errors = 0;

    rv32i_pipeline_stallbranch_core core_dut (.clk(clk), .rst(rst));
    always #5 clk = ~clk;

    task check(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual !== expected) begin
            $display("FAIL: %s -- expected %0d, got %0d", name, expected, actual);
            errors++;
        end else begin
            $display("PASS: %s (%0d)", name, actual);
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_pipeline_stallbranch_hazards);
        @(negedge clk);
        rst = 0;

        repeat (45) @(negedge clk);

        // 1. EX-to-EX and MEM-to-EX RAW forwarding
        check("x1 = 10",                                  core_dut.regfile.regs[1],  32'd10);
        check("x2 = 30  (EX-to-EX forwarding on rs1)",     core_dut.regfile.regs[2],  32'd30);
        check("x3 = 40  (MEM-to-EX rs1 + EX-to-EX rs2)",   core_dut.regfile.regs[3],  32'd40);

        // 2. MEM-to-EX forwarding across a NOP
        check("x4 = 100",                                 core_dut.regfile.regs[4],  32'd100);
        check("x5 = 150 (MEM-to-EX forwarding on rs1)",    core_dut.regfile.regs[5],  32'd150);

        // 3. Load-use hazard with 1-cycle stall
        check("x6 = 10  (loaded from mem)",               core_dut.regfile.regs[6],  32'd10);
        check("x7 = 15  (1-cycle stall then forwarded)",   core_dut.regfile.regs[7],  32'd15);

        // 4. Store data forwarding
        check("x8 = 77  (stored to mem[4])",              core_dut.regfile.regs[8],  32'd77);
        check("x9 = 77  (reloaded from mem[4])",          core_dut.regfile.regs[9],  32'd77);

        // 5. Register file write-through (WB-to-ID simultaneous)
        check("x10 = 99",                                 core_dut.regfile.regs[10], 32'd99);
        check("x11 = 100 (WB-to-ID write-through)",       core_dut.regfile.regs[11], 32'd100);

        if (errors == 0) $display("\nALL STALLBRANCH HAZARD TESTS PASSED (11/11)");
        else $display("\n%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule

