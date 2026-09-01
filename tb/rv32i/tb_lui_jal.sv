`timescale 1ns/1ps
module tb_lui_jal;
    logic clk = 0;
    logic rst = 1;
    int errors = 0;

    rv32i_core core_dut (.clk(clk), .rst(rst));
    always #5 clk = ~clk;

    task check(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual !== expected) begin
            $display("FAIL: %s -- expected %08h, got %08h", name, expected, actual);
            errors++;
        end else begin
            $display("PASS: %s (%08h)", name, actual);
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_lui_jal);
        @(negedge clk);
        rst = 0;
        repeat (6) @(negedge clk);

        check("x1 = lui result (0x12345000)", core_dut.regfile.regs[1], 32'h12345000);
        check("x2 = 5",                       core_dut.regfile.regs[2], 32'd5);
        check("x3 = jal return addr (0x0c)",  core_dut.regfile.regs[3], 32'h0000000c);
        check("x4 = 0 (skipped by jump)",     core_dut.regfile.regs[4], 32'd0);
        check("x5 = 42 (jump landed here)",   core_dut.regfile.regs[5], 32'd42);

        if (errors == 0) $display("\nALL LUI/JAL TESTS PASSED");
        else $display("\n%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
