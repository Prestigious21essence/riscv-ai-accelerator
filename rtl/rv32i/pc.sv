module pc (
    input  logic        clk,
    input  logic        rst,
    output logic [31:0] pc_out
);
    always_ff @(posedge clk) begin
        if (rst)
            pc_out <= 32'h0;
        else
            pc_out <= pc_out + 32'd4;
    end
endmodule