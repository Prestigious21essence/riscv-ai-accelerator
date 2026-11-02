// =============================================================================
// Module: control_superscalar
// Description: Dual-Instruction Decoder and Control Unit for 2-Way Superscalar Core.
//              - Instantiates two decoders for Slot 0 and Slot 1.
//              - Extracts opcode, funct3, funct7, rd, rs1, rs2, and usage flags.
//              - Classifies memory operations into MemClass:
//                  2'b00: MEM_NONE   (ALU, branch, lui, auipc)
//                  2'b01: MEM_STORE  (SW, SH, SB, NPU store_c)
//                  2'b10: MEM_BANK_A (NPU load_a)
//                  2'b11: MEM_BANK_B (NPU load_b)
// =============================================================================

`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Submodule: decoder_rv32i
// -----------------------------------------------------------------------------
module decoder_rv32i (
    input  logic [31:0] instr,
    output logic [6:0]  opcode,
    output logic [2:0]  funct3,
    output logic [6:0]  funct7,
    output logic [4:0]  rd,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic        uses_rs1,
    output logic        uses_rs2,
    output logic        reg_write,
    output logic        mem_read,
    output logic        mem_write,
    output logic        mem_to_reg,
    output logic        alu_src,
    output logic        branch,
    output logic        lui,
    output logic        jal,
    output logic        jalr,
    output logic        auipc,
    output logic [3:0]  alu_op,
    output logic [1:0]  mem_class,   // 00: NONE, 01: STORE, 10: BANK_A, 11: BANK_B
    output logic        is_npu_op
);

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    // Memory Class Constants
    localparam MEM_NONE   = 2'b00;
    localparam MEM_STORE  = 2'b01;
    localparam MEM_BANK_A = 2'b10;
    localparam MEM_BANK_B = 2'b11;

    always_comb begin
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        alu_src    = 1'b0;
        branch     = 1'b0;
        lui        = 1'b0;
        jal        = 1'b0;
        jalr       = 1'b0;
        auipc      = 1'b0;
        alu_op     = 4'b0000;
        uses_rs1   = 1'b0;
        uses_rs2   = 1'b0;
        mem_class  = MEM_NONE;
        is_npu_op  = 1'b0;

        case (opcode)
            // R-type (Register-Register ALU)
            7'b0110011: begin
                reg_write = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                case ({funct7, funct3})
                    10'b0000000_000: alu_op = 4'b0000; // ADD
                    10'b0100000_000: alu_op = 4'b0001; // SUB
                    10'b0000000_111: alu_op = 4'b0010; // AND
                    10'b0000000_110: alu_op = 4'b0011; // OR
                    10'b0000000_100: alu_op = 4'b0100; // XOR
                    10'b0000000_001: alu_op = 4'b0101; // SLL
                    10'b0000000_101: alu_op = 4'b0110; // SRL
                    10'b0100000_101: alu_op = 4'b0111; // SRA
                    10'b0000000_010: alu_op = 4'b1000; // SLT
                    10'b0000000_011: alu_op = 4'b1001; // SLTU
                    default:         alu_op = 4'b0000;
                endcase
            end

            // I-type (Register-Immediate ALU)
            7'b0010011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b0;
                case (funct3)
                    3'b000:  alu_op = 4'b0000; // ADDI
                    3'b111:  alu_op = 4'b0010; // ANDI
                    3'b110:  alu_op = 4'b0011; // ORI
                    3'b100:  alu_op = 4'b0100; // XORI
                    3'b010:  alu_op = 4'b1000; // SLTI
                    3'b011:  alu_op = 4'b1001; // SLTIU
                    3'b001:  alu_op = 4'b0101; // SLLI
                    3'b101:  alu_op = funct7[5] ? 4'b0111 : 4'b0110; // SRAI / SRLI
                    default: alu_op = 4'b0000;
                endcase
            end

            // Loads (I-type)
            7'b0000011: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                uses_rs1   = 1'b1;
                uses_rs2   = 1'b0;
                alu_op     = 4'b0000;
            end

            // Stores (S-type)
            7'b0100011: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b1;
                mem_class = MEM_STORE;
                alu_op    = 4'b0000;
            end

            // Branches (B-type)
            7'b1100011: begin
                branch   = 1'b1;
                uses_rs1 = 1'b1;
                uses_rs2 = 1'b1;
                case (funct3)
                    3'b000, 3'b001: alu_op = 4'b0001; // BEQ / BNE -> SUB
                    3'b100, 3'b101: alu_op = 4'b1000; // BLT / BGE -> SLT
                    3'b110, 3'b111: alu_op = 4'b1001; // BLTU / BGEU -> SLTU
                    default:        alu_op = 4'b0001;
                endcase
            end

            // LUI (U-type)
            7'b0110111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                lui       = 1'b1;
                uses_rs1  = 1'b0;
                uses_rs2  = 1'b0;
                alu_op    = 4'b0000;
            end

            // AUIPC (U-type)
            7'b0010111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                auipc     = 1'b1;
                uses_rs1  = 1'b0;
                uses_rs2  = 1'b0;
                alu_op    = 4'b0000;
            end

            // JAL (J-type)
            7'b1101111: begin
                reg_write = 1'b1;
                jal       = 1'b1;
                uses_rs1  = 1'b0;
                uses_rs2  = 1'b0;
            end

            // JALR (I-type)
            7'b1100111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jalr      = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = 1'b0;
                alu_op    = 4'b0000;
            end

            // Custom-0: NPU Coprocessor Instructions (Opcode 0x0B)
            7'b0001011: begin
                is_npu_op = 1'b1;
                uses_rs1  = 1'b1;
                uses_rs2  = (funct3 == 3'b010 || funct3 == 3'b011); // store_c or mem_print
                case (funct3)
                    3'b000:  mem_class = MEM_BANK_A; // load_a
                    3'b001:  mem_class = MEM_BANK_B; // load_b
                    3'b010:  mem_class = MEM_STORE;  // store_c
                    default: mem_class = MEM_NONE;
                endcase
            end

            default: ;
        endcase
    end
endmodule

// -----------------------------------------------------------------------------
// Top Module: control_superscalar
// -----------------------------------------------------------------------------
module control_superscalar (
    // Slot 0 Instruction
    input  logic [31:0] slot0_instr,
    output logic [6:0]  slot0_opcode,
    output logic [2:0]  slot0_funct3,
    output logic [6:0]  slot0_funct7,
    output logic [4:0]  slot0_rd,
    output logic [4:0]  slot0_rs1,
    output logic [4:0]  slot0_rs2,
    output logic        slot0_uses_rs1,
    output logic        slot0_uses_rs2,
    output logic        slot0_reg_write,
    output logic        slot0_mem_read,
    output logic        slot0_mem_write,
    output logic        slot0_mem_to_reg,
    output logic        slot0_alu_src,
    output logic        slot0_branch,
    output logic        slot0_lui,
    output logic        slot0_jal,
    output logic        slot0_jalr,
    output logic        slot0_auipc,
    output logic [3:0]  slot0_alu_op,
    output logic [1:0]  slot0_mem_class,
    output logic        slot0_is_npu_op,

    // Slot 1 Instruction
    input  logic [31:0] slot1_instr,
    output logic [6:0]  slot1_opcode,
    output logic [2:0]  slot1_funct3,
    output logic [6:0]  slot1_funct7,
    output logic [4:0]  slot1_rd,
    output logic [4:0]  slot1_rs1,
    output logic [4:0]  slot1_rs2,
    output logic        slot1_uses_rs1,
    output logic        slot1_uses_rs2,
    output logic        slot1_reg_write,
    output logic        slot1_mem_read,
    output logic        slot1_mem_write,
    output logic        slot1_mem_to_reg,
    output logic        slot1_alu_src,
    output logic        slot1_branch,
    output logic        slot1_lui,
    output logic        slot1_jal,
    output logic        slot1_jalr,
    output logic        slot1_auipc,
    output logic [3:0]  slot1_alu_op,
    output logic [1:0]  slot1_mem_class,
    output logic        slot1_is_npu_op
);

    // Instantiate Decoder for Slot 0
    decoder_rv32i dec0 (
        .instr     (slot0_instr),
        .opcode    (slot0_opcode),
        .funct3    (slot0_funct3),
        .funct7    (slot0_funct7),
        .rd        (slot0_rd),
        .rs1       (slot0_rs1),
        .rs2       (slot0_rs2),
        .uses_rs1  (slot0_uses_rs1),
        .uses_rs2  (slot0_uses_rs2),
        .reg_write (slot0_reg_write),
        .mem_read  (slot0_mem_read),
        .mem_write (slot0_mem_write),
        .mem_to_reg(slot0_mem_to_reg),
        .alu_src   (slot0_alu_src),
        .branch    (slot0_branch),
        .lui       (slot0_lui),
        .jal       (slot0_jal),
        .jalr      (slot0_jalr),
        .auipc     (slot0_auipc),
        .alu_op    (slot0_alu_op),
        .mem_class (slot0_mem_class),
        .is_npu_op (slot0_is_npu_op)
    );

    // Instantiate Decoder for Slot 1
    decoder_rv32i dec1 (
        .instr     (slot1_instr),
        .opcode    (slot1_opcode),
        .funct3    (slot1_funct3),
        .funct7    (slot1_funct7),
        .rd        (slot1_rd),
        .rs1       (slot1_rs1),
        .rs2       (slot1_rs2),
        .uses_rs1  (slot1_uses_rs1),
        .uses_rs2  (slot1_uses_rs2),
        .reg_write (slot1_reg_write),
        .mem_read  (slot1_mem_read),
        .mem_write (slot1_mem_write),
        .mem_to_reg(slot1_mem_to_reg),
        .alu_src   (slot1_alu_src),
        .branch    (slot1_branch),
        .lui       (slot1_lui),
        .jal       (slot1_jal),
        .jalr      (slot1_jalr),
        .auipc     (slot1_auipc),
        .alu_op    (slot1_alu_op),
        .mem_class (slot1_mem_class),
        .is_npu_op (slot1_is_npu_op)
    );

endmodule

