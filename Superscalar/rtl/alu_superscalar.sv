// =============================================================================
// Module: alu_superscalar
// Description: Dual 32-bit Arithmetic Logic Units (ALU0 and ALU1) for 2-Way
//              Superscalar RV32I Processor.
//              - ALU0 serves Pipeline Slot 0 (Pipe 0)
//              - ALU1 serves Pipeline Slot 1 (Pipe 1)
//              - Supports all RV32I standard operations:
//                  4'b0000: ADD   (a + b)
//                  4'b0001: SUB   (a - b)
//                  4'b0010: AND   (a & b)
//                  4'b0011: OR    (a | b)
//                  4'b0100: XOR   (a ^ b)
//                  4'b0101: SLL   (a << b[4:0])
//                  4'b0110: SRL   (a >> b[4:0])
//                  4'b0111: SRA   ($signed(a) >>> b[4:0])
//                  4'b1000: SLT   ($signed(a) < $signed(b) ? 1 : 0)
//                  4'b1001: SLTU  (a < b ? 1 : 0)
// =============================================================================

`timescale 1ns/1ps

module alu_core (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  alu_op,
    output logic [31:0] result,
    output logic        zero
);
    always_comb begin
        case (alu_op)
            4'b0000: result = a + b;
            4'b0001: result = a - b;
            4'b0010: result = a & b;
            4'b0011: result = a | b;
            4'b0100: result = a ^ b;
            4'b0101: result = a << b[4:0];
            4'b0110: result = a >> b[4:0];
            4'b0111: result = $signed(a) >>> b[4:0];
            4'b1000: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            4'b1001: result = (a < b) ? 32'd1 : 32'd0;
            default: result = 32'd0;
        endcase
    end

    assign zero = (result == 32'd0);
endmodule

module alu_superscalar (
    // Slot 0 Execution Unit
    input  logic [31:0] alu0_a,
    input  logic [31:0] alu0_b,
    input  logic [3:0]  alu0_op,
    output logic [31:0] alu0_result,
    output logic        alu0_zero,

    // Slot 1 Execution Unit
    input  logic [31:0] alu1_a,
    input  logic [31:0] alu1_b,
    input  logic [3:0]  alu1_op,
    output logic [31:0] alu1_result,
    output logic        alu1_zero
);

    alu_core u_alu0 (
        .a(alu0_a),
        .b(alu0_b),
        .alu_op(alu0_op),
        .result(alu0_result),
        .zero(alu0_zero)
    );

    alu_core u_alu1 (
        .a(alu1_a),
        .b(alu1_b),
        .alu_op(alu1_op),
        .result(alu1_result),
        .zero(alu1_zero)
    );

endmodule

