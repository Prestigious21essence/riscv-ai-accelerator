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

    assign instr = mem[addr[9:2]];   // word-aligned index into 256 words
endmodule