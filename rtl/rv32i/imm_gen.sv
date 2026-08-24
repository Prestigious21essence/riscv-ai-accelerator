module imm_gen (
    input  logic [31:0] instr,
    output logic [31:0] imm
);
    logic [6:0] opcode;
    assign opcode = instr[6:0];

    always_comb begin
        case (opcode)
            7'b0010011, 7'b0000011:
                imm = {{20{instr[31]}}, instr[31:20]};
            7'b0100011:
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            7'b1100011:
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            default:
                imm = 32'd0;
        endcase
    end
endmodule
