// =============================================================================
// Pipeline Registers for 5-Stage RV32I Core
// =============================================================================

// -----------------------------------------------------------------------------
// IF/ID Pipeline Register
// -----------------------------------------------------------------------------
module if_id_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    input  logic        write_en,
    input  logic [31:0] if_pc,
    input  logic [31:0] if_instr,
    output logic [31:0] id_pc,
    output logic [31:0] id_instr
);
    // RISC-V NOP: addi x0, x0, 0 = 32'h00000013
    localparam NOP = 32'h00000013;

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            id_pc    <= 32'b0;
            id_instr <= NOP;
        end else if (write_en) begin
            id_pc    <= if_pc;
            id_instr <= if_instr;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// ID/EX Pipeline Register
// -----------------------------------------------------------------------------
module id_ex_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,

    // Control signals from ID stage
    input  logic        id_reg_write,
    input  logic        id_mem_to_reg,
    input  logic        id_mem_read,
    input  logic        id_mem_write,
    input  logic        id_alu_src,
    input  logic        id_branch,
    input  logic        id_lui,
    input  logic        id_jal,
    input  logic        id_jalr,
    input  logic        id_auipc,
    input  logic [3:0]  id_alu_op,

    // Data from ID stage
    input  logic [31:0] id_pc,
    input  logic [31:0] id_rs1_data,
    input  logic [31:0] id_rs2_data,
    input  logic [31:0] id_imm,
    input  logic [2:0]  id_funct3,
    input  logic [4:0]  id_rd,
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,

    // Control signals to EX stage
    output logic        ex_reg_write,
    output logic        ex_mem_to_reg,
    output logic        ex_mem_read,
    output logic        ex_mem_write,
    output logic        ex_alu_src,
    output logic        ex_branch,
    output logic        ex_lui,
    output logic        ex_jal,
    output logic        ex_jalr,
    output logic        ex_auipc,
    output logic [3:0]  ex_alu_op,

    // Data to EX stage
    output logic [31:0] ex_pc,
    output logic [31:0] ex_rs1_data,
    output logic [31:0] ex_rs2_data,
    output logic [31:0] ex_imm,
    output logic [2:0]  ex_funct3,
    output logic [4:0]  ex_rd,
    output logic [4:0]  ex_rs1,
    output logic [4:0]  ex_rs2
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            ex_reg_write  <= 1'b0;
            ex_mem_to_reg <= 1'b0;
            ex_mem_read   <= 1'b0;
            ex_mem_write  <= 1'b0;
            ex_alu_src    <= 1'b0;
            ex_branch     <= 1'b0;
            ex_lui        <= 1'b0;
            ex_jal        <= 1'b0;
            ex_jalr       <= 1'b0;
            ex_auipc      <= 1'b0;
            ex_alu_op     <= 4'b0000;
            ex_pc         <= 32'b0;
            ex_rs1_data   <= 32'b0;
            ex_rs2_data   <= 32'b0;
            ex_imm        <= 32'b0;
            ex_funct3     <= 3'b0;
            ex_rd         <= 5'b0;
            ex_rs1        <= 5'b0;
            ex_rs2        <= 5'b0;
        end else begin
            ex_reg_write  <= id_reg_write;
            ex_mem_to_reg <= id_mem_to_reg;
            ex_mem_read   <= id_mem_read;
            ex_mem_write  <= id_mem_write;
            ex_alu_src    <= id_alu_src;
            ex_branch     <= id_branch;
            ex_lui        <= id_lui;
            ex_jal        <= id_jal;
            ex_jalr       <= id_jalr;
            ex_auipc      <= id_auipc;
            ex_alu_op     <= id_alu_op;
            ex_pc         <= id_pc;
            ex_rs1_data   <= id_rs1_data;
            ex_rs2_data   <= id_rs2_data;
            ex_imm        <= id_imm;
            ex_funct3     <= id_funct3;
            ex_rd         <= id_rd;
            ex_rs1        <= id_rs1;
            ex_rs2        <= id_rs2;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// EX/MEM Pipeline Register
// -----------------------------------------------------------------------------
module ex_mem_reg (
    input  logic        clk,
    input  logic        rst,

    // Control signals from EX stage
    input  logic        ex_reg_write,
    input  logic        ex_mem_to_reg,
    input  logic        ex_mem_read,
    input  logic        ex_mem_write,
    input  logic        ex_jal,
    input  logic        ex_jalr,

    // Data from EX stage
    input  logic [31:0] ex_alu_result,
    input  logic [31:0] ex_write_data,
    input  logic [31:0] ex_link_addr,
    input  logic [4:0]  ex_rd,
    input  logic [2:0]  ex_funct3,
    input  logic [4:0]  ex_rs2,

    // Control signals to MEM stage
    output logic        mem_reg_write,
    output logic        mem_mem_to_reg,
    output logic        mem_mem_read,
    output logic        mem_mem_write,
    output logic        mem_jal,
    output logic        mem_jalr,

    // Data to MEM stage
    output logic [31:0] mem_alu_result,
    output logic [31:0] mem_write_data,
    output logic [31:0] mem_link_addr,
    output logic [4:0]  mem_rd,
    output logic [2:0]  mem_funct3,
    output logic [4:0]  mem_rs2
);
    always_ff @(posedge clk) begin
        if (rst) begin
            mem_reg_write  <= 1'b0;
            mem_mem_to_reg <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_jal        <= 1'b0;
            mem_jalr       <= 1'b0;
            mem_alu_result <= 32'b0;
            mem_write_data <= 32'b0;
            mem_link_addr  <= 32'b0;
            mem_rd         <= 5'b0;
            mem_funct3     <= 3'b0;
            mem_rs2        <= 5'b0;
        end else begin
            mem_reg_write  <= ex_reg_write;
            mem_mem_to_reg <= ex_mem_to_reg;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_jal        <= ex_jal;
            mem_jalr       <= ex_jalr;
            mem_alu_result <= ex_alu_result;
            mem_write_data <= ex_write_data;
            mem_link_addr  <= ex_link_addr;
            mem_rd         <= ex_rd;
            mem_funct3     <= ex_funct3;
            mem_rs2        <= ex_rs2;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// MEM/WB Pipeline Register
// -----------------------------------------------------------------------------
module mem_wb_reg (
    input  logic        clk,
    input  logic        rst,

    // Control signals from MEM stage
    input  logic        mem_reg_write,
    input  logic        mem_mem_to_reg,
    input  logic        mem_jal,
    input  logic        mem_jalr,

    // Data from MEM stage
    input  logic [31:0] mem_read_data,
    input  logic [31:0] mem_alu_result,
    input  logic [31:0] mem_link_addr,
    input  logic [4:0]  mem_rd,

    // Control signals to WB stage
    output logic        wb_reg_write,
    output logic        wb_mem_to_reg,
    output logic        wb_jal,
    output logic        wb_jalr,

    // Data to WB stage
    output logic [31:0] wb_read_data,
    output logic [31:0] wb_alu_result,
    output logic [31:0] wb_link_addr,
    output logic [4:0]  wb_rd
);
    always_ff @(posedge clk) begin
        if (rst) begin
            wb_reg_write  <= 1'b0;
            wb_mem_to_reg <= 1'b0;
            wb_jal        <= 1'b0;
            wb_jalr       <= 1'b0;
            wb_read_data  <= 32'b0;
            wb_alu_result <= 32'b0;
            wb_link_addr  <= 32'b0;
            wb_rd         <= 5'b0;
        end else begin
            wb_reg_write  <= mem_reg_write;
            wb_mem_to_reg <= mem_mem_to_reg;
            wb_jal        <= mem_jal;
            wb_jalr       <= mem_jalr;
            wb_read_data  <= mem_read_data;
            wb_alu_result <= mem_alu_result;
            wb_link_addr  <= mem_link_addr;
            wb_rd         <= mem_rd;
        end
    end
endmodule

