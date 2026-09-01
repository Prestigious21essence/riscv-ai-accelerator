module pc (
    input  logic        clk,
    input  logic        rst,
    input  logic        jump,   // 1 = take a jump (pc_out + imm) instead of auto-incrementing
    input  logic [31:0] imm,    // JAL's J-type immediate, added to current pc_out when jump=1
    output logic [31:0] pc_out
);
    always_ff @(posedge clk) begin
        if (rst)
            pc_out <= 32'h0;
        else if (jump)
            pc_out <= pc_out + imm;
        else
            pc_out <= pc_out + 32'd4;
    end
endmodule
