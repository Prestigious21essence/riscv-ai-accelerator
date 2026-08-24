module rv32i_core (
    input  logic clk,
    input  logic rst
);
    logic [31:0] pc_out, instr;
    logic [31:0] rs1_data, rs2_data, alu_b, alu_result, imm, write_data, read_data;
    logic        zero;

    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    logic [4:0] rd, rs1, rs2;

    logic reg_write, mem_read, mem_write, mem_to_reg, alu_src, branch;
    logic [3:0] alu_op;

    pc pc_reg (.clk(clk), .rst(rst), .pc_out(pc_out));
    instruction_memory imem (.addr(pc_out), .instr(instr));

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1    = instr[19:15];
    assign rs2    = instr[24:20];
    assign funct7 = instr[31:25];

    control ctrl (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .mem_to_reg(mem_to_reg), .alu_src(alu_src), .branch(branch), .alu_op(alu_op)
    );

    imm_gen immgen (.instr(instr), .imm(imm));

    register_file regfile (
        .clk(clk), .we(reg_write),
        .rs1_addr(rs1), .rs2_addr(rs2), .rd_addr(rd),
        .rd_data(write_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    assign alu_b = alu_src ? imm : rs2_data;

    alu alu_inst (
        .a(rs1_data), .b(alu_b), .alu_op(alu_op),
        .result(alu_result), .zero(zero)
    );

    data_memory dmem (
        .clk(clk), .mem_write(mem_write),
        .addr(alu_result), .write_data(rs2_data), .read_data(read_data)
    );

    assign write_data = mem_to_reg ? read_data : alu_result;
endmodule
