`timescale 1ns/1ps
module tb_auipc;
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
        $dumpvars(0, tb_auipc);
        @(negedge clk);
        rst = 0;
        repeat (4) @(negedge clk);

        check("x1 = auipc x1,0x5 @pc=0x00 -> 0x00005000", core_dut.regfile.regs[1], 32'h00005000);
        check("x2 = auipc x2,0x1 @pc=0x04 -> 0x00001004", core_dut.regfile.regs[2], 32'h00001004);

        if (errors == 0) $display("\nALL AUIPC TESTS PASSED");
        else $display("\n%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
