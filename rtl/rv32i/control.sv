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
    output logic [3:0] alu_op
);
    always_comb begin
        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        alu_src    = 1'b0;
        branch     = 1'b0;
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
                branch  = 1'b1;
                alu_op  = 4'b0001;
            end
            default: ;
        endcase
    end
endmodule
