`timescale 1ns/1ps

module tb_pc_instr_mem;
    logic        clk = 0;
    logic        rst = 1;
    logic [31:0] pc_out;
    logic [31:0] instr;

    int errors = 0;

    pc pc_dut (
        .clk(clk), .rst(rst), .jump(1'b0), .imm(32'd0), .pc_out(pc_out)
    );

    instruction_memory imem_dut (
        .addr(pc_out), .instr(instr)
    );

    always #5 clk = ~clk;

    task check(string name, logic [31:0] actual, logic [31:0] expected);
        if (actual !== expected) begin
            $display("FAIL: %s -- expected %08h, got %08h", name, expected, actual);
            errors++;
        end else begin
            $display("PASS: %s", name);
        end
    endtask

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_pc_instr_mem);

        @(negedge clk);
        rst = 0;
        #1 check("PC=0 fetches addi x1,x0,5", instr, 32'h00500093);

        @(negedge clk);
        #1 check("PC=4 fetches addi x2,x0,10", instr, 32'h00a00113);

        @(negedge clk);
        #1 check("PC=8 fetches add x3,x1,x2", instr, 32'h002081b3);

        @(negedge clk);
        #1 check("PC=12 fetches nop", instr, 32'h00000013);

        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule