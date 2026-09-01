module data_memory #(
    parameter MEM_WORDS = 256
)(
    input  logic        clk,
    input  logic        mem_write,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    input  logic [2:0]  funct3,   // load/store width+signedness: 000=B,001=H,010=W,100=BU,101=HU
    output logic [31:0] read_data
);
    logic [31:0] mem [0:MEM_WORDS-1];

    // word-aligned index sized to MEM_WORDS (was hardcoded addr[9:2], which
    // silently ignored MEM_WORDS above 256 -- see ARCH_TEST_PLAN.md)
    localparam IDX_HI = $clog2(MEM_WORDS) + 1;

    logic [31:0] word;
    logic [1:0]  byte_off;
    logic [7:0]  byte_val;
    logic [15:0] half_val;

    assign word     = mem[addr[IDX_HI:2]];
    assign byte_off = addr[1:0];
    assign byte_val = word[byte_off*8 +: 8];
    assign half_val = word[byte_off[1]*16 +: 16];

    // Byte/halfword loads (LB/LH/LBU/LHU) extract and extend a sub-word from
    // the addressed 32-bit word; LW (and anything else) passes the word
    // through untouched -- matches prior full-word-only behavior exactly
    // when funct3 isn't one of the byte/half encodings.
    always_comb begin
        case (funct3)
            3'b000:  read_data = {{24{byte_val[7]}}, byte_val};   // LB  (sign-extend)
            3'b001:  read_data = {{16{half_val[15]}}, half_val};  // LH  (sign-extend)
            3'b100:  read_data = {24'b0, byte_val};                // LBU (zero-extend)
            3'b101:  read_data = {16'b0, half_val};                // LHU (zero-extend)
            default: read_data = word;                             // LW
        endcase
    end

    // Byte/halfword stores (SB/SH) only overwrite the addressed sub-word,
    // leaving the rest of the containing word untouched; SW (and anything
    // else) writes the full word -- matches prior behavior exactly.
    always_ff @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000:  mem[addr[IDX_HI:2]][byte_off*8 +: 8]        <= write_data[7:0];   // SB
                3'b001:  mem[addr[IDX_HI:2]][byte_off[1]*16 +: 16]   <= write_data[15:0];  // SH
                default: mem[addr[IDX_HI:2]]                        <= write_data;         // SW
            endcase
        end
    end
endmodule
