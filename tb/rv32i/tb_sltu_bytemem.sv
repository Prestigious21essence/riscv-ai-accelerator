`timescale 1ns/1ps
module tb_sltu_bytemem;
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
        $dumpvars(0, tb_sltu_bytemem);
        @(negedge clk);
        rst = 0;
        repeat (20) @(negedge clk);

        // SLTU/SLTIU: unsigned comparisons where signed would give the
        // opposite answer -- the case that actually distinguishes them
        // from SLT/SLTI.
        check("x1 = sltiu x1,x0,-1  (0 <u 0xFFFFFFFF -> 1)", core_dut.regfile.regs[1], 32'd1);
        check("x2 = addi x2,x0,-1  (-> 0xFFFFFFFF)",         core_dut.regfile.regs[2], 32'hFFFFFFFF);
        check("x3 = sltu x3,x0,x2  (0 <u 0xFFFFFFFF -> 1)",  core_dut.regfile.regs[3], 32'd1);
        check("x4 = sltu x4,x2,x0  (0xFFFFFFFF <u 0 -> 0)",  core_dut.regfile.regs[4], 32'd0);

        // Byte/halfword store then load back.
        check("x10 = lb  word0 byte0 (0xFF, sign-extended)",   core_dut.regfile.regs[10], 32'hFFFFFFFF);
        check("x11 = lbu word0 byte0 (0xFF, zero-extended)",   core_dut.regfile.regs[11], 32'd255);
        check("x12 = lh  word1 half0 (0x8000, sign-extended)", core_dut.regfile.regs[12], 32'hFFFF8000);
        check("x13 = lhu word1 half0 (0x8000, zero-extended)", core_dut.regfile.regs[13], 32'h00008000);
        check("x14 = lw  word0 (confirms sb wrote just byte0)",core_dut.regfile.regs[14], 32'h000000FF);

        if (errors == 0) $display("\nALL SLTU/BYTEMEM TESTS PASSED");
        else $display("\n%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
