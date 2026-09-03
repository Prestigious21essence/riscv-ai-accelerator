module pc (
    input  logic        clk,
    input  logic         rst,
    input  logic        jump,          // JAL: pc_out + imm (PC-relative)
    input  logic        branch_taken,  // conditional branch resolved taken: pc_out + imm (PC-relative)
    input  logic        jalr,          // JALR: jump straight to jalr_target (register-relative, absolute)
    input  logic [31:0] imm,           // JAL's J-imm, or the branch's B-imm -- imm_gen already
                                        // selects the right one off the current opcode
    input  logic [31:0] jalr_target,   // (rs1 + I-imm) with bit 0 cleared, computed in rv32i_core
                                        // (Verilator doesn't support in-port default values, so
                                        // every instantiation -- including tb_pc_instr_mem.sv --
                                        // must wire these explicitly, even if just tied to 0/1'b0)
    output logic [31:0] pc_out
);
    always_ff @(posedge clk) begin
        if (rst)
            pc_out <= 32'h0;
        else if (jalr)
            pc_out <= jalr_target;
        else if (jump || branch_taken)
            pc_out <= pc_out + imm;
        else
            pc_out <= pc_out + 32'd4;
    end
endmodule
