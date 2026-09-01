module instruction_memory #(
    parameter MEM_WORDS = 256
)(
    input  logic [31:0] addr,
    output logic [31:0] instr
);
    logic [31:0] mem [0:MEM_WORDS-1];

    initial begin
        $readmemh("instr_mem.hex", mem);
    end

    // word-aligned index sized to MEM_WORDS (was hardcoded addr[9:2], which
    // silently ignored MEM_WORDS above 256 -- see ARCH_TEST_PLAN.md)
    localparam IDX_HI = $clog2(MEM_WORDS) + 1;

    assign instr = mem[addr[IDX_HI:2]];
endmodule
