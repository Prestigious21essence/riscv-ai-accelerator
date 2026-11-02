// =============================================================================
// Module: imm_gen_superscalar
// Description: Dual Immediate Generator for 2-Way Superscalar RV32I Core.
//              Decodes sign-extended immediates across I, S, B, U, and J formats
//              in parallel for Slot 0 and Slot 1.
// =============================================================================

`timescale 1ns/1ps

module imm_gen_superscalar (
    input  logic [31:0] slot0_instr,
    output logic [31:0] slot0_imm,

    input  logic [31:0] slot1_instr,
    output logic [31:0] slot1_imm
);

    // Slot 0 Immediate Generation
    always_comb begin
        case (slot0_instr[6:0])
            7'b0010011, 7'b0000011, 7'b1100111: // I-type (ALU imm, Load, JALR)
                slot0_imm = {{20{slot0_instr[31]}}, slot0_instr[31:20]};
            7'b0100011: // S-type (Store)
                slot0_imm = {{20{slot0_instr[31]}}, slot0_instr[31:25], slot0_instr[11:7]};
            7'b1100011: // B-type (Branch)
                slot0_imm = {{19{slot0_instr[31]}}, slot0_instr[31], slot0_instr[7], slot0_instr[30:25], slot0_instr[11:8], 1'b0};
            7'b0110111, 7'b0010111: // U-type (LUI, AUIPC)
                slot0_imm = {slot0_instr[31:12], 12'b0};
            7'b1101111: // J-type (JAL)
                slot0_imm = {{11{slot0_instr[31]}}, slot0_instr[31], slot0_instr[19:12], slot0_instr[20], slot0_instr[30:21], 1'b0};
            default:
                slot0_imm = 32'd0;
        endcase
    end

    // Slot 1 Immediate Generation
    always_comb begin
        case (slot1_instr[6:0])
            7'b0010011, 7'b0000011, 7'b1100111: // I-type
                slot1_imm = {{20{slot1_instr[31]}}, slot1_instr[31:20]};
            7'b0100011: // S-type
                slot1_imm = {{20{slot1_instr[31]}}, slot1_instr[31:25], slot1_instr[11:7]};
            7'b1100011: // B-type
                slot1_imm = {{19{slot1_instr[31]}}, slot1_instr[31], slot1_instr[7], slot1_instr[30:25], slot1_instr[11:8], 1'b0};
            7'b0110111, 7'b0010111: // U-type
                slot1_imm = {slot1_instr[31:12], 12'b0};
            7'b1101111: // J-type
                slot1_imm = {{11{slot1_instr[31]}}, slot1_instr[31], slot1_instr[19:12], slot1_instr[20], slot1_instr[30:21], 1'b0};
            default:
                slot1_imm = 32'd0;
        endcase
    end

endmodule

