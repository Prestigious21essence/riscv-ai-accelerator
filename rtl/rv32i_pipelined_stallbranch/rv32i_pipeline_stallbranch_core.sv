// =============================================================================
// 5-Stage Pipelined RV32I Core with Always-Stall on Branch/Jump
// =============================================================================
// Features:
// - Classic 5-stage RISC-V Harvard architecture (IF, ID, EX, MEM, WB)
// - Full data forwarding unit (EX-to-EX, MEM-to-EX)
// - Load-use hazard detection unit (1-cycle stall)
// - Always-Stall on Branch/Jump:
//   * Freezes instruction fetch (PC & IF/ID) whenever a branch or jump is in ID
//   * Evaluates branch condition / target in EX stage
//   * Dispatches target or fallthrough address to PC
//   * Zero speculative execution (no wrong-path instructions ever reach ID or EX)
// - Internal write-to-read forwarding in register file (WB-to-ID)
// =============================================================================

module rv32i_pipeline_stallbranch_core #(
    parameter MEM_WORDS = 256
)(
    input  logic clk,
    input  logic rst
);

    // =========================================================================
    // 1. IF STAGE (Instruction Fetch)
    // =========================================================================
    logic [31:0] if_pc, next_pc, if_pc_plus_4;
    logic [31:0] if_instr;
    logic        pc_write, if_id_write, flush_if_id, flush_id_ex;

    logic        ex_branch_or_jump;
    logic [31:0] ex_resolved_pc;

    assign if_pc_plus_4 = if_pc + 32'd4;
    assign next_pc      = ex_branch_or_jump ? ex_resolved_pc : if_pc_plus_4;

    pc_pipeline pc_reg (
        .clk(clk),
        .rst(rst),
        .pc_write(pc_write),
        .next_pc(next_pc),
        .pc_out(if_pc)
    );

    instruction_memory #(.MEM_WORDS(MEM_WORDS)) imem (
        .addr(if_pc),
        .instr(if_instr)
    );

    // -------------------------------------------------------------------------
    // IF/ID Pipeline Register
    // -------------------------------------------------------------------------
    logic [31:0] id_pc, id_instr;

    if_id_reg if_id_inst (
        .clk(clk),
        .rst(rst),
        .flush(flush_if_id),
        .write_en(if_id_write),
        .if_pc(if_pc),
        .if_instr(if_instr),
        .id_pc(id_pc),
        .id_instr(id_instr)
    );

    // =========================================================================
    // 2. ID STAGE (Instruction Decode & Register Read)
    // =========================================================================
    logic [6:0] id_opcode, id_funct7;
    logic [2:0] id_funct3;
    logic [4:0] id_rd, id_rs1, id_rs2;
    logic [31:0] id_imm;
    logic [31:0] id_rs1_data, id_rs2_data;

    assign id_opcode = id_instr[6:0];
    assign id_rd     = id_instr[11:7];
    assign id_funct3 = id_instr[14:12];
    assign id_rs1    = id_instr[19:15];
    assign id_rs2    = id_instr[24:20];
    assign id_funct7 = id_instr[31:25];

    logic id_reg_write, id_mem_read, id_mem_write, id_mem_to_reg, id_alu_src;
    logic id_branch, id_lui, id_jal, id_jalr, id_auipc;
    logic [3:0] id_alu_op;

    control ctrl (
        .opcode(id_opcode),
        .funct3(id_funct3),
        .funct7(id_funct7),
        .reg_write(id_reg_write),
        .mem_read(id_mem_read),
        .mem_write(id_mem_write),
        .mem_to_reg(id_mem_to_reg),
        .alu_src(id_alu_src),
        .branch(id_branch),
        .lui(id_lui),
        .jal(id_jal),
        .jalr(id_jalr),
        .auipc(id_auipc),
        .alu_op(id_alu_op)
    );

    imm_gen immgen (
        .instr(id_instr),
        .imm(id_imm)
    );

    // Writeback signals for register file write
    logic        wb_reg_write;
    logic [4:0]  wb_rd;
    logic [31:0] wb_write_data;

    register_file_pipeline regfile (
        .clk(clk),
        .we(wb_reg_write),
        .rs1_addr(id_rs1),
        .rs2_addr(id_rs2),
        .rd_addr(wb_rd),
        .rd_data(wb_write_data),
        .rs1_data(id_rs1_data),
        .rs2_data(id_rs2_data)
    );

    // Identify which registers are actually read by the current instruction
    logic id_uses_rs1, id_uses_rs2;
    assign id_uses_rs1 = (id_opcode == 7'b0110011) || // R-type
                         (id_opcode == 7'b0010011) || // I-type ALU
                         (id_opcode == 7'b0000011) || // Load
                         (id_opcode == 7'b0100011) || // Store
                         (id_opcode == 7'b1100011) || // Branch
                         (id_opcode == 7'b1100111);   // JALR

    assign id_uses_rs2 = (id_opcode == 7'b0110011) || // R-type
                         (id_opcode == 7'b0100011) || // Store
                         (id_opcode == 7'b1100011);   // Branch

    logic id_branch_or_jump;
    assign id_branch_or_jump = id_branch || id_jal || id_jalr;

    // -------------------------------------------------------------------------
    // ID/EX Pipeline Register
    // -------------------------------------------------------------------------
    logic        ex_reg_write, ex_mem_to_reg, ex_mem_read, ex_mem_write, ex_alu_src;
    logic        ex_branch, ex_lui, ex_jal, ex_jalr, ex_auipc;
    logic [3:0]  ex_alu_op;
    logic [31:0] ex_pc, ex_rs1_data, ex_rs2_data, ex_imm;
    logic [2:0]  ex_funct3;
    logic [4:0]  ex_rd, ex_rs1, ex_rs2;

    id_ex_reg id_ex_inst (
        .clk(clk),
        .rst(rst),
        .flush(flush_id_ex),
        .id_reg_write(id_reg_write),
        .id_mem_to_reg(id_mem_to_reg),
        .id_mem_read(id_mem_read),
        .id_mem_write(id_mem_write),
        .id_alu_src(id_alu_src),
        .id_branch(id_branch),
        .id_lui(id_lui),
        .id_jal(id_jal),
        .id_jalr(id_jalr),
        .id_auipc(id_auipc),
        .id_alu_op(id_alu_op),
        .id_pc(id_pc),
        .id_rs1_data(id_rs1_data),
        .id_rs2_data(id_rs2_data),
        .id_imm(id_imm),
        .id_funct3(id_funct3),
        .id_rd(id_rd),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .ex_reg_write(ex_reg_write),
        .ex_mem_to_reg(ex_mem_to_reg),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_alu_src(ex_alu_src),
        .ex_branch(ex_branch),
        .ex_lui(ex_lui),
        .ex_jal(ex_jal),
        .ex_jalr(ex_jalr),
        .ex_auipc(ex_auipc),
        .ex_alu_op(ex_alu_op),
        .ex_pc(ex_pc),
        .ex_rs1_data(ex_rs1_data),
        .ex_rs2_data(ex_rs2_data),
        .ex_imm(ex_imm),
        .ex_funct3(ex_funct3),
        .ex_rd(ex_rd),
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2)
    );

    // =========================================================================
    // 3. EX STAGE (Execute, ALU, Branch & Jump Evaluation)
    // =========================================================================
    logic [1:0]  forward_a, forward_b;
    logic [31:0] forwarded_a, forwarded_b;
    logic [31:0] alu_a, alu_b, ex_alu_result;
    logic        ex_zero;

    // Data forwarded from EX/MEM stage
    logic        ex_mem_reg_write, ex_mem_jal, ex_mem_jalr;
    logic [4:0]  ex_mem_rd;
    logic [31:0] ex_mem_alu_result, ex_mem_link_addr;
    logic [31:0] ex_mem_forward_data;

    assign ex_mem_forward_data = (ex_mem_jal || ex_mem_jalr) ? ex_mem_link_addr : ex_mem_alu_result;

    // Operand A Forwarding Multiplexer
    always_comb begin
        case (forward_a)
            2'b10:   forwarded_a = ex_mem_forward_data;
            2'b01:   forwarded_a = wb_write_data;
            default: forwarded_a = ex_rs1_data;
        endcase
    end

    // Operand B Forwarding Multiplexer
    always_comb begin
        case (forward_b)
            2'b10:   forwarded_b = ex_mem_forward_data;
            2'b01:   forwarded_b = wb_write_data;
            default: forwarded_b = ex_rs2_data;
        endcase
    end

    // ALU Operand A Multiplexer
    assign alu_a = ex_lui   ? 32'b0 :
                   ex_auipc ? ex_pc : forwarded_a;

    // ALU Operand B Multiplexer
    assign alu_b = ex_alu_src ? ex_imm : forwarded_b;

    alu alu_inst (
        .a(alu_a),
        .b(alu_b),
        .alu_op(ex_alu_op),
        .result(ex_alu_result),
        .zero(ex_zero)
    );

    // Link address for JAL / JALR (return address = pc + 4)
    logic [31:0] ex_link_addr;
    assign ex_link_addr = ex_pc + 32'd4;

    // Branch Resolution Logic
    logic ex_branch_taken;
    always_comb begin
        ex_branch_taken = 1'b0;
        if (ex_branch) begin
            case (ex_funct3)
                3'b000:  ex_branch_taken =  ex_zero;          // BEQ
                3'b001:  ex_branch_taken = ~ex_zero;          // BNE
                3'b100:  ex_branch_taken =  ex_alu_result[0]; // BLT  (SLT signed)
                3'b101:  ex_branch_taken = ~ex_alu_result[0]; // BGE
                3'b110:  ex_branch_taken =  ex_alu_result[0]; // BLTU (SLTU unsigned)
                3'b111:  ex_branch_taken = ~ex_alu_result[0]; // BGEU
                default: ex_branch_taken = 1'b0;
            endcase
        end
    end

    // Resolved Target / Fallthrough PC
    logic [31:0] jalr_target, branch_jal_target;
    assign jalr_target       = {ex_alu_result[31:1], 1'b0};
    assign branch_jal_target = ex_pc + ex_imm;

    always_comb begin
        if (ex_jalr) begin
            ex_resolved_pc = jalr_target;
        end else if (ex_jal) begin
            ex_resolved_pc = branch_jal_target;
        end else if (ex_branch) begin
            // Taken branch goes to target; not-taken branch goes to fallthrough PC+4
            ex_resolved_pc = ex_branch_taken ? branch_jal_target : (ex_pc + 32'd4);
        end else begin
            ex_resolved_pc = ex_pc + 32'd4;
        end
    end

    assign ex_branch_or_jump = ex_branch || ex_jal || ex_jalr;

    // -------------------------------------------------------------------------
    // EX/MEM Pipeline Register
    // -------------------------------------------------------------------------
    logic        ex_mem_mem_to_reg, ex_mem_mem_read, ex_mem_mem_write;
    logic [31:0] ex_mem_write_data;
    logic [2:0]  ex_mem_funct3;
    logic [4:0]  ex_mem_rs2;

    ex_mem_reg ex_mem_inst (
        .clk(clk),
        .rst(rst),
        .ex_reg_write(ex_reg_write),
        .ex_mem_to_reg(ex_mem_to_reg),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_jal(ex_jal),
        .ex_jalr(ex_jalr),
        .ex_alu_result(ex_alu_result),
        .ex_write_data(forwarded_b),
        .ex_link_addr(ex_link_addr),
        .ex_rd(ex_rd),
        .ex_funct3(ex_funct3),
        .ex_rs2(ex_rs2),
        .mem_reg_write(ex_mem_reg_write),
        .mem_mem_to_reg(ex_mem_mem_to_reg),
        .mem_mem_read(ex_mem_mem_read),
        .mem_mem_write(ex_mem_mem_write),
        .mem_jal(ex_mem_jal),
        .mem_jalr(ex_mem_jalr),
        .mem_alu_result(ex_mem_alu_result),
        .mem_write_data(ex_mem_write_data),
        .mem_link_addr(ex_mem_link_addr),
        .mem_rd(ex_mem_rd),
        .mem_funct3(ex_mem_funct3),
        .mem_rs2(ex_mem_rs2)
    );

    // =========================================================================
    // 4. MEM STAGE (Data Memory Access)
    // =========================================================================
    logic [31:0] mem_dmem_read_data;
    logic [31:0] dmem_store_data;

    assign dmem_store_data = (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_mem_rs2)) ?
                             wb_write_data : ex_mem_write_data;

    data_memory #(.MEM_WORDS(MEM_WORDS)) dmem (
        .clk(clk),
        .mem_write(ex_mem_mem_write),
        .addr(ex_mem_alu_result),
        .write_data(dmem_store_data),
        .funct3(ex_mem_funct3),
        .read_data(mem_dmem_read_data)
    );

    // -------------------------------------------------------------------------
    // MEM/WB Pipeline Register
    // -------------------------------------------------------------------------
    logic        wb_mem_to_reg, wb_jal, wb_jalr;
    logic [31:0] wb_read_data, wb_alu_result, wb_link_addr;

    mem_wb_reg mem_wb_inst (
        .clk(clk),
        .rst(rst),
        .mem_reg_write(ex_mem_reg_write),
        .mem_mem_to_reg(ex_mem_mem_to_reg),
        .mem_jal(ex_mem_jal),
        .mem_jalr(ex_mem_jalr),
        .mem_read_data(mem_dmem_read_data),
        .mem_alu_result(ex_mem_alu_result),
        .mem_link_addr(ex_mem_link_addr),
        .mem_rd(ex_mem_rd),
        .wb_reg_write(wb_reg_write),
        .wb_mem_to_reg(wb_mem_to_reg),
        .wb_jal(wb_jal),
        .wb_jalr(wb_jalr),
        .wb_read_data(wb_read_data),
        .wb_alu_result(wb_alu_result),
        .wb_link_addr(wb_link_addr),
        .wb_rd(wb_rd)
    );

    // =========================================================================
    // 5. WB STAGE (Writeback to Register File)
    // =========================================================================
    assign wb_write_data = (wb_jal || wb_jalr) ? wb_link_addr :
                           wb_mem_to_reg       ? wb_read_data : wb_alu_result;

    // =========================================================================
    // 6. HAZARD UNIT (Always-Stall on Branch + Forwarding + Load-Use Stall)
    // =========================================================================
    hazard_unit_stallbranch hazard_ctrl (
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_uses_rs1(id_uses_rs1),
        .id_uses_rs2(id_uses_rs2),
        .id_branch_or_jump(id_branch_or_jump),
        .id_ex_rs1(ex_rs1),
        .id_ex_rs2(ex_rs2),
        .id_ex_rd(ex_rd),
        .id_ex_mem_read(ex_mem_read),
        .ex_branch_or_jump(ex_branch_or_jump),
        .ex_mem_rd(ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd(wb_rd),
        .mem_wb_reg_write(wb_reg_write),
        .forward_a(forward_a),
        .forward_b(forward_b),
        .pc_write(pc_write),
        .if_id_write(if_id_write),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

endmodule

