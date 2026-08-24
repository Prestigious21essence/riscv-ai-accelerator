module data_memory #(
    parameter MEM_WORDS = 256
)(
    input  logic        clk,
    input  logic        mem_write,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    output logic [31:0] read_data
);
    logic [31:0] mem [0:MEM_WORDS-1];

    assign read_data = mem[addr[9:2]];

    always_ff @(posedge clk) begin
        if (mem_write)
            mem[addr[9:2]] <= write_data;
    end
endmodule
