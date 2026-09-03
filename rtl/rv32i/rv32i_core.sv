module rv32i_core #(
    parameter MEM_WORDS = 256   // pass-through to imem/dmem; see ARCH_TEST_PLAN.md
)(
    input  logic clk,
    input  logic rst
);
    logic [31:0] pc_out, instr;
    logic [31:0] rs1_data, rs2_data, alu_a, alu_b, alu_result, imm, write_data, read_data;
    logic        zero;

    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    logic [4:0] rd, rs1, rs2;

    logic reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch, lui, jal, jalr, auipc;
    logic [3:0] alu_op;

    // Branch resolution: control.sv already picked the right ALU comparison
    // for this funct3 (SUB for BEQ/BNE, SLT for BLT/BGE, SLTU for BLTU/BGEU
    // -- see control.sv). Here we just read off whether that comparison
    // means "take the branch": BEQ/BLT/BLTU take when the ALU says
    // zero/less-than is true, BNE/BGE/BGEU take on the opposite.
    logic branch_taken;
    always_comb begin
        branch_taken = 1'b0;
        if (branch) begin
            case (funct3)
                3'b000: branch_taken =  zero;          // BEQ
                3'b001: branch_taken = ~zero;          // BNE
                3'b100: branch_taken =  alu_result[0]; // BLT  (SLT result)
                3'b101: branch_taken = ~alu_result[0]; // BGE
                3'b110: branch_taken =  alu_result[0]; // BLTU (SLTU result)
                3'b111: branch_taken = ~alu_result[0]; // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

    // JALR target: rs1 + I-imm (computed by the ALU, since alu_src=1 and
    // alu_a defaults to rs1_data for jalr), with bit 0 cleared per spec.
    logic [31:0] jalr_target;
    assign jalr_target = {alu_result[31:1], 1'b0};

    pc pc_reg (
        .clk(clk), .rst(rst),
        .jump(jal), .branch_taken(branch_taken), .jalr(jalr),
        .imm(imm), .jalr_target(jalr_target),
        .pc_out(pc_out)
    );
    instruction_memory #(.MEM_WORDS(MEM_WORDS)) imem (.addr(pc_out), .instr(instr));

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    control ctrl (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .mem_to_reg(mem_to_reg), .alu_src(alu_src), .branch(branch),
        .lui(lui), .jal(jal), .jalr(jalr), .auipc(auipc), .alu_op(alu_op)
    );

    imm_gen immgen (.instr(instr), .imm(imm));

    register_file regfile (
        .clk(clk), .we(reg_write),
        .rs1_addr(rs1), .rs2_addr(rs2), .rd_addr(rd),
        .rd_data(write_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    // LUI has no rs1 field (those bits are part of the immediate), so its
    // result must be 0 + imm, not rs1_data + imm. AUIPC is the same shape
    // but adds the current PC instead of 0.
    assign alu_a = lui ? 32'b0 : (auipc ? pc_out : rs1_data);
    assign alu_b = alu_src ? imm : rs2_data;

    alu alu_inst (
        .a(alu_a), .b(alu_b), .alu_op(alu_op),
        .result(alu_result), .zero(zero)
    );

    data_memory #(.MEM_WORDS(MEM_WORDS)) dmem (
        .clk(clk), .mem_write(mem_write),
        .addr(alu_result), .write_data(rs2_data), .funct3(funct3), .read_data(read_data)
    );

    // JAL/JALR write pc+4 (the return address) to rd, not an ALU/memory result.
    assign write_data = (jal || jalr) ? (pc_out + 32'd4) : (mem_to_reg ? read_data : alu_result);
endmodule
