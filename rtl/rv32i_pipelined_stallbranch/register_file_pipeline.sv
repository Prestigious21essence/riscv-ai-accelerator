module register_file_pipeline (
    input  logic        clk,
    input  logic        we,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);
    logic [31:0] regs [31:0];

    // Internal write-to-read forwarding (write-first):
    // If WB is writing to rd_addr in the same cycle that ID is reading it,
    // immediately forward rd_data to rs1/rs2 to resolve WB-to-ID hazard.
    assign rs1_data = (rs1_addr == 5'd0) ? 32'd0 :
                      (we && (rd_addr == rs1_addr)) ? rd_data : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'd0 :
                      (we && (rd_addr == rs2_addr)) ? rd_data : regs[rs2_addr];

    always_ff @(posedge clk) begin
        if (we && rd_addr != 5'd0)
            regs[rd_addr] <= rd_data;
    end
endmodule

