`timescale 1ns/1ps
module tb_arch_test #(
    parameter DATA_HEX       = "data_mem.hex",
    parameter OUT_FILE       = "out.signature",
    parameter int SIG_START_WORD = 0,
    parameter int SIG_END_WORD   = 0,
    parameter int MAX_CYCLES = 8000,
    parameter int MEM_WORDS  = 4096
)();
    logic clk = 0;
    logic rst = 1;
    rv32i_core #(.MEM_WORDS(MEM_WORDS)) core_dut (.clk(clk), .rst(rst));
    always #5 clk = ~clk;
    integer sigfile;
    integer i;
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_arch_test);
        $readmemh(DATA_HEX, core_dut.dmem.mem);
        @(negedge clk);
        rst = 0;
        repeat (MAX_CYCLES) @(negedge clk);
        sigfile = $fopen(OUT_FILE, "w");
        for (i = SIG_START_WORD; i < SIG_END_WORD; i = i + 1)
            $fdisplay(sigfile, "%08x", core_dut.dmem.mem[i]);
        $fclose(sigfile);
        $display("Wrote signature (%0d words) to %s", SIG_END_WORD - SIG_START_WORD, OUT_FILE);
        $finish;
    end
endmodule
