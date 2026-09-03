module control (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    output logic       reg_write,
    output logic       mem_read,
    output logic       mem_write,
    output logic       mem_to_reg,
    output logic       alu_src,
    output logic       branch,
    output logic       lui,
    output logic       jal,
    output logic       jalr,
    output logic       auipc,
    output logic [3:0] alu_op
);
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

        case (opcode)
            7'b0110011: begin
                reg_write = 1'b1;
                case ({funct7, funct3})
                    10'b0000000_000: alu_op = 4'b0000;
                    10'b0100000_000: alu_op = 4'b0001;
                    10'b0000000_111: alu_op = 4'b0010;
                    10'b0000000_110: alu_op = 4'b0011;
                    10'b0000000_100: alu_op = 4'b0100;
                    10'b0000000_001: alu_op = 4'b0101;
                    10'b0000000_101: alu_op = 4'b0110;
                    10'b0100000_101: alu_op = 4'b0111;
                    10'b0000000_010: alu_op = 4'b1000;
                    10'b0000000_011: alu_op = 4'b1001;  // SLTU
                    default: alu_op = 4'b0000;
                endcase
            end
            7'b0010011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                case (funct3)
                    3'b000: alu_op = 4'b0000;
                    3'b111: alu_op = 4'b0010;
                    3'b110: alu_op = 4'b0011;
                    3'b100: alu_op = 4'b0100;
                    3'b010: alu_op = 4'b1000;
                    3'b011: alu_op = 4'b1001;  // SLTIU
                    3'b001: alu_op = 4'b0101;
                    3'b101: alu_op = funct7[5] ? 4'b0111 : 4'b0110;
                    default: alu_op = 4'b0000;
                endcase
            end
            7'b0000011: begin
                reg_write  = 1'b1;
                alu_src    = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 1'b1;
                alu_op     = 4'b0000;
            end
            7'b0100011: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                alu_op    = 4'b0000;
            end
            7'b1100011: begin
                // Branch comparison depends on funct3, not just "subtract":
                // BEQ/BNE (000/001) read the SUB result's zero flag; BLT/BGE
                // (100/101) need a signed less-than; BLTU/BGEU (110/111) need
                // an unsigned less-than. Whether the branch is actually taken
                // (zero vs !zero, slt vs !slt) is resolved downstream in
                // rv32i_core from this alu_op choice plus funct3 -- control
                // only picks which comparison the ALU performs.
                branch  = 1'b1;
                case (funct3)
                    3'b000, 3'b001: alu_op = 4'b0001;  // BEQ/BNE -> SUB (zero flag)
                    3'b100, 3'b101: alu_op = 4'b1000;  // BLT/BGE -> SLT (signed)
                    3'b110, 3'b111: alu_op = 4'b1001;  // BLTU/BGEU -> SLTU (unsigned)
                    default:        alu_op = 4'b0001;
                endcase
            end
            7'b0110111: begin  // LUI: rd = imm (ALU computes 0 + imm; A-input forced to 0 in rv32i_core)
                reg_write = 1'b1;
                alu_src   = 1'b1;
                lui       = 1'b1;
                alu_op    = 4'b0000;
            end
            7'b1101111: begin  // JAL: rd = pc+4, pc = pc + J-imm
                reg_write = 1'b1;
                jal       = 1'b1;
            end
            7'b1100111: begin  // JALR: rd = pc+4, pc = (rs1 + I-imm) & ~1
                reg_write = 1'b1;
                alu_src   = 1'b1;   // ALU computes rs1 + imm (target, before LSB clear)
                jalr      = 1'b1;
                alu_op    = 4'b0000;
            end
            7'b0010111: begin  // AUIPC: rd = pc + imm (ALU computes pc + imm; A-input forced to pc_out in rv32i_core)
                reg_write = 1'b1;
                alu_src   = 1'b1;
                auipc     = 1'b1;
                alu_op    = 4'b0000;
            end
            default: ;
        endcase
    end
endmodule
