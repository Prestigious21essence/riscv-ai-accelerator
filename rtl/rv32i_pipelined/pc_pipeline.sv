module pc_pipeline (
    input  logic        clk,
    input  logic        rst,
    input  logic        pc_write,     // 1 to update, 0 to stall (freeze PC)
    input  logic [31:0] next_pc,
    output logic [31:0] pc_out
);
    always_ff @(posedge clk) begin
        if (rst)
            pc_out <= 32'h0;
        else if (pc_write)
            pc_out <= next_pc;
    end
endmodule

