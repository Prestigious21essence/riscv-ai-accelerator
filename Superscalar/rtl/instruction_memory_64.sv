// =============================================================================
// Module: instruction_memory_64
// Description: 64-bit Dual-Word Instruction Memory for Superscalar RV32I Core.
//              - Reads two contiguous 32-bit words simultaneously from memory.
//              - Indexing is aligned to 64-bit (8-byte) boundaries.
//              - Outputs even word (raw_word0) and odd word (raw_word1).
//              - Automatically initializes from "instr_mem.hex" or +HEX=<file>.
// =============================================================================

`timescale 1ns/1ps

module instruction_memory_64 #(
    parameter MEM_WORDS = 1024
)(
    input  logic [31:0] addr,
    output logic [31:0] raw_word0,   // Word at 64-bit aligned base: (addr & ~32'h7)
    output logic [31:0] raw_word1,   // Word at 64-bit aligned base + 4: (addr & ~32'h7) + 4
    output logic [63:0] raw_data_64  // 64-bit packet: {raw_word1, raw_word0}
);

    logic [31:0] mem [0:MEM_WORDS-1];

    initial begin
        string hex_file;
        if ($value$plusargs("HEX=%s", hex_file)) begin
            $readmemh(hex_file, mem);
        end else begin
            $readmemh("instr_mem.hex", mem);
        end
    end

    localparam WORD_BITS  = $clog2(MEM_WORDS);     // e.g. 10 for 1024 words
    localparam DWORD_BITS = WORD_BITS - 1;          // e.g. 9 for 512 doublewords

    // Align to 8-byte (64-bit doubleword) boundary
    logic [DWORD_BITS-1:0] dword_idx;
    assign dword_idx = addr[WORD_BITS+1:3];

    logic [31:0] word0_idx;
    logic [31:0] word1_idx;
    assign word0_idx = 32'({dword_idx, 1'b0});
    assign word1_idx = 32'({dword_idx, 1'b1});

    // Read even word (offset 0) and odd word (offset 4)
    always_comb begin
        if (word0_idx < MEM_WORDS)
            raw_word0 = mem[word0_idx[WORD_BITS-1:0]];
        else
            raw_word0 = 32'h00000013; // Default NOP: addi x0, x0, 0

        if (word1_idx < MEM_WORDS)
            raw_word1 = mem[word1_idx[WORD_BITS-1:0]];
        else
            raw_word1 = 32'h00000013; // Default NOP: addi x0, x0, 0
    end

    assign raw_data_64 = {raw_word1, raw_word0};

endmodule

