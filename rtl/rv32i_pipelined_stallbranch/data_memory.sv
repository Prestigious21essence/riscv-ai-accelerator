module data_memory #(
    parameter MEM_WORDS = 256
)(
    input  logic        clk,
    input  logic        mem_write,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    input  logic [2:0]  funct3,   // 000=B, 001=H, 010=W, 100=BU, 101=HU
    output logic [31:0] read_data
);
    logic [31:0] mem [0:MEM_WORDS-1];

    localparam IDX_HI = $clog2(MEM_WORDS) + 1;

    logic [31:0] word;
    logic [1:0]  byte_off;
    logic [7:0]  byte_val;
    logic [15:0] half_val;

    assign word     = mem[addr[IDX_HI:2]];
    assign byte_off = addr[1:0];
    assign byte_val = word[byte_off*8 +: 8];
    assign half_val = word[byte_off[1]*16 +: 16];

    always_comb begin
        case (funct3)
            3'b000:  read_data = {{24{byte_val[7]}}, byte_val};   // LB
            3'b001:  read_data = {{16{half_val[15]}}, half_val};  // LH
            3'b100:  read_data = {24'b0, byte_val};                // LBU
            3'b101:  read_data = {16'b0, half_val};                // LHU
            default: read_data = word;                             // LW
        endcase
    end

    always_ff @(posedge clk) begin
        if (mem_write) begin
            case (funct3)
                3'b000:  mem[addr[IDX_HI:2]][byte_off*8 +: 8]      <= write_data[7:0];
                3'b001:  mem[addr[IDX_HI:2]][byte_off[1]*16 +: 16] <= write_data[15:0];
                default: mem[addr[IDX_HI:2]]                      <= write_data;
            endcase
        end
    end
endmodule

