`timescale 1ns/1ps
// Hand-assembled program covering BEQ/BNE/BLT/BGE/BLTU/BGEU (each with one
// taken and one not-taken case) plus JAL and JALR -- see
// ../../../asm_branch_jalr.py (repo root's sandbox copy) for the encoder
// and the address-by-address layout this checks against. Every "[skip]"
// instruction in that program must NOT execute; if pc.sv's branch/jalr
// wiring is wrong, the skipped instruction's value (999) leaks into the
// register instead of the real one, which is exactly what this catches.
module tb_branch_jalr;
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
        $dumpvars(0, tb_branch_jalr);
        @(negedge clk);
        rst = 0;
        repeat (40) @(negedge clk);

        check("x1  = 5                          (operand)",         core_dut.regfile.regs[1],  32'd5);
        check("x2  = 5                          (operand)",         core_dut.regfile.regs[2],  32'd5);
        check("x3  = 111  (BEQ taken, skip not executed)",          core_dut.regfile.regs[3],  32'd111);
        check("x4  = 222  (BNE not taken, fallthrough executed)",   core_dut.regfile.regs[4],  32'd222);
        check("x5  = -1                         (operand)",         core_dut.regfile.regs[5],  32'hFFFFFFFF);
        check("x6  = 1                          (operand)",         core_dut.regfile.regs[6],  32'd1);
        check("x7  = 333  (BLT taken, skip not executed)",          core_dut.regfile.regs[7],  32'd333);
        check("x8  = 444  (BLTU not taken, fallthrough executed)",  core_dut.regfile.regs[8],  32'd444);
        check("x9  = 555  (BGE taken, skip not executed)",          core_dut.regfile.regs[9],  32'd555);
        check("x10 = 666  (BGEU not taken, fallthrough executed)",  core_dut.regfile.regs[10], 32'd666);
        check("x11 = 0x50 (JAL return address, pc+4)",              core_dut.regfile.regs[11], 32'h00000050);
        check("x12 = 0    (JAL-skipped instr never executed)",      core_dut.regfile.regs[12], 32'd0);
        check("x13 = 777  (JAL landed and executed)",               core_dut.regfile.regs[13], 32'd777);
        check("x14 = 0x64                       (operand)",         core_dut.regfile.regs[14], 32'h00000064);
        check("x15 = 0x60 (JALR return address, pc+4)",             core_dut.regfile.regs[15], 32'h00000060);
        check("x16 = 0    (JALR-skipped instr never executed)",     core_dut.regfile.regs[16], 32'd0);
        check("x17 = 0    (JALR-skipped instr never executed)",     core_dut.regfile.regs[17], 32'd0);
        check("x18 = 0    (JALR-skipped instr never executed)",     core_dut.regfile.regs[18], 32'd0);
        check("x19 = 888  (JALR landed at rs1+imm and executed)",   core_dut.regfile.regs[19], 32'd888);

        if (errors == 0) $display("\nALL BRANCH/JALR TESTS PASSED");
        else $display("\n%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
