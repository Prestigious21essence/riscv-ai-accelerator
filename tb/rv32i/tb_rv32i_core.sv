`timescale 1ns/1ps

module tb_rv32i_core;
    logic clk = 0;
    logic rst = 1;

    int errors = 0;

    rv32i_core core_dut (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    task check(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual !== expected) begin
            $display("FAIL: %s -- expected %0d, got %0d", name, expected, actual);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_rv32i_core);

        @(negedge clk);
        rst = 0;

        repeat (12) @(negedge clk);

        check("x1 = 5",  core_dut.regfile.regs[1], 32'd5);
        check("x2 = 10", core_dut.regfile.regs[2], 32'd10);
        check("x3 = 15", core_dut.regfile.regs[3], 32'd15);
        check("x4 = 15 (loaded from mem)", core_dut.regfile.regs[4], 32'd15);
        check("x5 = 10", core_dut.regfile.regs[5], 32'd10);
        check("x6 = 0",  core_dut.regfile.regs[6], 32'd0);
        check("x7 = 15", core_dut.regfile.regs[7], 32'd15);

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule
