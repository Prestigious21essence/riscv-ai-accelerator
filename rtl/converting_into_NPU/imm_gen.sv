module imm_gen (
    input  logic [31:0] instr,
    output logic [31:0] imm
);
    logic [6:0] opcode;
    assign opcode = instr[6:0];

    always_comb begin
        case (opcode)
            7'b0010011, 7'b0000011, 7'b1100111: begin // I-type: OP-IMM, LOAD, JALR
                imm = {{20{instr[31]}}, instr[31:20]};
            end
            7'b0100011: begin // S-type: STORE
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end
            7'b1100011: begin // B-type: BRANCH
                imm = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            end
            7'b0110111, 7'b0010111: begin // U-type: LUI, AUIPC
                imm = {instr[31:12], 12'b0};
            end
            7'b1101111: begin // J-type: JAL
                imm = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            end
            default: imm = 32'b0;
        endcase
    end
endmodule

