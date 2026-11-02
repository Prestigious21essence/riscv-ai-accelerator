// =============================================================================
// Module: pipeline_regs_superscalar
// Description: Dual Pipeline Registers (IF/ID, ID/EX, EX/MEM, MEM/WB) for
//              2-Way In-Order Superscalar RV32I Processor.
//              - Encapsulates synchronous registers for Pipe 0 and Pipe 1.
//              - Supports synchronous stalls (write_en) and flushes (bubble insertion).
// =============================================================================

`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// 1. IF/ID Dual Pipeline Register
// -----------------------------------------------------------------------------
module if_id_superscalar_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    input  logic        write_en,

    // Inputs from IF stage
    input  logic [31:0] if_slot0_pc,
    input  logic [31:0] if_slot0_instr,
    input  logic        if_slot0_valid,
    input  logic        if_slot0_pred_taken,
    input  logic [31:0] if_slot0_pred_target,

    input  logic [31:0] if_slot1_pc,
    input  logic [31:0] if_slot1_instr,
    input  logic        if_slot1_valid,

    // Outputs to ID stage
    output logic [31:0] id_slot0_pc,
    output logic [31:0] id_slot0_instr,
    output logic        id_slot0_valid,
    output logic        id_slot0_pred_taken,
    output logic [31:0] id_slot0_pred_target,

    output logic [31:0] id_slot1_pc,
    output logic [31:0] id_slot1_instr,
    output logic        id_slot1_valid
);
    localparam NOP = 32'h0000_0013; // addi x0, x0, 0

    always_ff @(posedge clk) begin
        if (rst || flush) begin
            id_slot0_pc          <= 32'd0;
            id_slot0_instr       <= NOP;
            id_slot0_valid       <= 1'b0;
            id_slot0_pred_taken  <= 1'b0;
            id_slot0_pred_target <= 32'd0;

            id_slot1_pc          <= 32'd0;
            id_slot1_instr       <= NOP;
            id_slot1_valid       <= 1'b0;
        end else if (write_en) begin
            id_slot0_pc          <= if_slot0_pc;
            id_slot0_instr       <= if_slot0_instr;
            id_slot0_valid       <= if_slot0_valid;
            id_slot0_pred_taken  <= if_slot0_pred_taken;
            id_slot0_pred_target <= if_slot0_pred_target;

            id_slot1_pc          <= if_slot1_pc;
            id_slot1_instr       <= if_slot1_instr;
            id_slot1_valid       <= if_slot1_valid;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// 2. ID/EX Dual Pipeline Register
// -----------------------------------------------------------------------------
module id_ex_superscalar_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    input  logic        write_en,

    // Slot 0 Inputs from ID
    input  logic [31:0] id0_pc,
    input  logic [31:0] id0_rs1_data,
    input  logic [31:0] id0_rs2_data,
    input  logic [31:0] id0_imm,
    input  logic [4:0]  id0_rd,
    input  logic [4:0]  id0_rs1,
    input  logic [4:0]  id0_rs2,
    input  logic        id0_uses_rs1,
    input  logic        id0_uses_rs2,
    input  logic [2:0]  id0_funct3,
    input  logic [3:0]  id0_alu_op,
    input  logic        id0_alu_src,
    input  logic        id0_reg_write,
    input  logic        id0_mem_read,
    input  logic        id0_mem_write,
    input  logic        id0_mem_to_reg,
    input  logic        id0_branch,
    input  logic        id0_jal,
    input  logic        id0_jalr,
    input  logic        id0_lui,
    input  logic        id0_auipc,
    input  logic [1:0]  id0_mem_class,
    input  logic        id0_pred_taken,
    input  logic [31:0] id0_pred_target,
    input  logic        id0_valid,

    // Slot 1 Inputs from ID
    input  logic [31:0] id1_pc,
    input  logic [31:0] id1_rs1_data,
    input  logic [31:0] id1_rs2_data,
    input  logic [31:0] id1_imm,
    input  logic [4:0]  id1_rd,
    input  logic [4:0]  id1_rs1,
    input  logic [4:0]  id1_rs2,
    input  logic        id1_uses_rs1,
    input  logic        id1_uses_rs2,
    input  logic [2:0]  id1_funct3,
    input  logic [3:0]  id1_alu_op,
    input  logic        id1_alu_src,
    input  logic        id1_reg_write,
    input  logic        id1_mem_read,
    input  logic        id1_mem_write,
    input  logic        id1_mem_to_reg,
    input  logic        id1_branch,
    input  logic        id1_jal,
    input  logic        id1_jalr,
    input  logic        id1_lui,
    input  logic        id1_auipc,
    input  logic [1:0]  id1_mem_class,
    input  logic        id1_valid,

    // Slot 0 Outputs to EX
    output logic [31:0] ex0_pc,
    output logic [31:0] ex0_rs1_data,
    output logic [31:0] ex0_rs2_data,
    output logic [31:0] ex0_imm,
    output logic [4:0]  ex0_rd,
    output logic [4:0]  ex0_rs1,
    output logic [4:0]  ex0_rs2,
    output logic        ex0_uses_rs1,
    output logic        ex0_uses_rs2,
    output logic [2:0]  ex0_funct3,
    output logic [3:0]  ex0_alu_op,
    output logic        ex0_alu_src,
    output logic        ex0_reg_write,
    output logic        ex0_mem_read,
    output logic        ex0_mem_write,
    output logic        ex0_mem_to_reg,
    output logic        ex0_branch,
    output logic        ex0_jal,
    output logic        ex0_jalr,
    output logic        ex0_lui,
    output logic        ex0_auipc,
    output logic [1:0]  ex0_mem_class,
    output logic        ex0_pred_taken,
    output logic [31:0] ex0_pred_target,
    output logic        ex0_valid,

    // Slot 1 Outputs to EX
    output logic [31:0] ex1_pc,
    output logic [31:0] ex1_rs1_data,
    output logic [31:0] ex1_rs2_data,
    output logic [31:0] ex1_imm,
    output logic [4:0]  ex1_rd,
    output logic [4:0]  ex1_rs1,
    output logic [4:0]  ex1_rs2,
    output logic        ex1_uses_rs1,
    output logic        ex1_uses_rs2,
    output logic [2:0]  ex1_funct3,
    output logic [3:0]  ex1_alu_op,
    output logic        ex1_alu_src,
    output logic        ex1_reg_write,
    output logic        ex1_mem_read,
    output logic        ex1_mem_write,
    output logic        ex1_mem_to_reg,
    output logic        ex1_branch,
    output logic        ex1_jal,
    output logic        ex1_jalr,
    output logic        ex1_lui,
    output logic        ex1_auipc,
    output logic [1:0]  ex1_mem_class,
    output logic        ex1_valid
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            ex0_pc          <= 32'd0;
            ex0_rs1_data    <= 32'd0;
            ex0_rs2_data    <= 32'd0;
            ex0_imm         <= 32'd0;
            ex0_rd          <= 5'd0;
            ex0_rs1         <= 5'd0;
            ex0_rs2         <= 5'd0;
            ex0_uses_rs1    <= 1'b0;
            ex0_uses_rs2    <= 1'b0;
            ex0_funct3      <= 3'd0;
            ex0_alu_op      <= 4'd0;
            ex0_alu_src     <= 1'b0;
            ex0_reg_write   <= 1'b0;
            ex0_mem_read    <= 1'b0;
            ex0_mem_write   <= 1'b0;
            ex0_mem_to_reg  <= 1'b0;
            ex0_branch      <= 1'b0;
            ex0_jal         <= 1'b0;
            ex0_jalr        <= 1'b0;
            ex0_lui         <= 1'b0;
            ex0_auipc       <= 1'b0;
            ex0_mem_class   <= 2'd0;
            ex0_pred_taken  <= 1'b0;
            ex0_pred_target <= 32'd0;
            ex0_valid       <= 1'b0;

            ex1_pc          <= 32'd0;
            ex1_rs1_data    <= 32'd0;
            ex1_rs2_data    <= 32'd0;
            ex1_imm         <= 32'd0;
            ex1_rd          <= 5'd0;
            ex1_rs1         <= 5'd0;
            ex1_rs2         <= 5'd0;
            ex1_uses_rs1    <= 1'b0;
            ex1_uses_rs2    <= 1'b0;
            ex1_funct3      <= 3'd0;
            ex1_alu_op      <= 4'd0;
            ex1_alu_src     <= 1'b0;
            ex1_reg_write   <= 1'b0;
            ex1_mem_read    <= 1'b0;
            ex1_mem_write   <= 1'b0;
            ex1_mem_to_reg  <= 1'b0;
            ex1_branch      <= 1'b0;
            ex1_jal         <= 1'b0;
            ex1_jalr        <= 1'b0;
            ex1_lui         <= 1'b0;
            ex1_auipc       <= 1'b0;
            ex1_mem_class   <= 2'd0;
            ex1_valid       <= 1'b0;
        end else if (write_en) begin
            ex0_pc          <= id0_pc;
            ex0_rs1_data    <= id0_rs1_data;
            ex0_rs2_data    <= id0_rs2_data;
            ex0_imm         <= id0_imm;
            ex0_rd          <= id0_rd;
            ex0_rs1         <= id0_rs1;
            ex0_rs2         <= id0_rs2;
            ex0_uses_rs1    <= id0_uses_rs1;
            ex0_uses_rs2    <= id0_uses_rs2;
            ex0_funct3      <= id0_funct3;
            ex0_alu_op      <= id0_alu_op;
            ex0_alu_src     <= id0_alu_src;
            ex0_reg_write   <= id0_reg_write;
            ex0_mem_read    <= id0_mem_read;
            ex0_mem_write   <= id0_mem_write;
            ex0_mem_to_reg  <= id0_mem_to_reg;
            ex0_branch      <= id0_branch;
            ex0_jal         <= id0_jal;
            ex0_jalr        <= id0_jalr;
            ex0_lui         <= id0_lui;
            ex0_auipc       <= id0_auipc;
            ex0_mem_class   <= id0_mem_class;
            ex0_pred_taken  <= id0_pred_taken;
            ex0_pred_target <= id0_pred_target;
            ex0_valid       <= id0_valid;

            ex1_pc          <= id1_pc;
            ex1_rs1_data    <= id1_rs1_data;
            ex1_rs2_data    <= id1_rs2_data;
            ex1_imm         <= id1_imm;
            ex1_rd          <= id1_rd;
            ex1_rs1         <= id1_rs1;
            ex1_rs2         <= id1_rs2;
            ex1_uses_rs1    <= id1_uses_rs1;
            ex1_uses_rs2    <= id1_uses_rs2;
            ex1_funct3      <= id1_funct3;
            ex1_alu_op      <= id1_alu_op;
            ex1_alu_src     <= id1_alu_src;
            ex1_reg_write   <= id1_reg_write;
            ex1_mem_read    <= id1_mem_read;
            ex1_mem_write   <= id1_mem_write;
            ex1_mem_to_reg  <= id1_mem_to_reg;
            ex1_branch      <= id1_branch;
            ex1_jal         <= id1_jal;
            ex1_jalr        <= id1_jalr;
            ex1_lui         <= id1_lui;
            ex1_auipc       <= id1_auipc;
            ex1_mem_class   <= id1_mem_class;
            ex1_valid       <= id1_valid;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// 3. EX/MEM Dual Pipeline Register
// -----------------------------------------------------------------------------
module ex_mem_superscalar_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    input  logic        write_en,

    // Slot 0 Inputs from EX
    input  logic [31:0] ex0_pc,
    input  logic [31:0] ex0_alu_result,
    input  logic [31:0] ex0_store_data,
    input  logic [4:0]  ex0_rd,
    input  logic        ex0_reg_write,
    input  logic        ex0_mem_read,
    input  logic        ex0_mem_write,
    input  logic        ex0_mem_to_reg,
    input  logic [2:0]  ex0_funct3,
    input  logic [1:0]  ex0_mem_class,
    input  logic        ex0_valid,

    // Slot 1 Inputs from EX
    input  logic [31:0] ex1_pc,
    input  logic [31:0] ex1_alu_result,
    input  logic [31:0] ex1_store_data,
    input  logic [4:0]  ex1_rd,
    input  logic        ex1_reg_write,
    input  logic        ex1_mem_read,
    input  logic        ex1_mem_write,
    input  logic        ex1_mem_to_reg,
    input  logic [2:0]  ex1_funct3,
    input  logic [1:0]  ex1_mem_class,
    input  logic        ex1_valid,

    // Slot 0 Outputs to MEM
    output logic [31:0] mem0_pc,
    output logic [31:0] mem0_alu_result,
    output logic [31:0] mem0_store_data,
    output logic [4:0]  mem0_rd,
    output logic        mem0_reg_write,
    output logic        mem0_mem_read,
    output logic        mem0_mem_write,
    output logic        mem0_mem_to_reg,
    output logic [2:0]  mem0_funct3,
    output logic [1:0]  mem0_mem_class,
    output logic        mem0_valid,

    // Slot 1 Outputs to MEM
    output logic [31:0] mem1_pc,
    output logic [31:0] mem1_alu_result,
    output logic [31:0] mem1_store_data,
    output logic [4:0]  mem1_rd,
    output logic        mem1_reg_write,
    output logic        mem1_mem_read,
    output logic        mem1_mem_write,
    output logic        mem1_mem_to_reg,
    output logic [2:0]  mem1_funct3,
    output logic [1:0]  mem1_mem_class,
    output logic        mem1_valid
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            mem0_pc         <= 32'd0;
            mem0_alu_result <= 32'd0;
            mem0_store_data <= 32'd0;
            mem0_rd         <= 5'd0;
            mem0_reg_write  <= 1'b0;
            mem0_mem_read   <= 1'b0;
            mem0_mem_write  <= 1'b0;
            mem0_mem_to_reg <= 1'b0;
            mem0_funct3     <= 3'd0;
            mem0_mem_class  <= 2'd0;
            mem0_valid      <= 1'b0;

            mem1_pc         <= 32'd0;
            mem1_alu_result <= 32'd0;
            mem1_store_data <= 32'd0;
            mem1_rd         <= 5'd0;
            mem1_reg_write  <= 1'b0;
            mem1_mem_read   <= 1'b0;
            mem1_mem_write  <= 1'b0;
            mem1_mem_to_reg <= 1'b0;
            mem1_funct3     <= 3'd0;
            mem1_mem_class  <= 2'd0;
            mem1_valid      <= 1'b0;
        end else if (write_en) begin
            mem0_pc         <= ex0_pc;
            mem0_alu_result <= ex0_alu_result;
            mem0_store_data <= ex0_store_data;
            mem0_rd         <= ex0_rd;
            mem0_reg_write  <= ex0_reg_write;
            mem0_mem_read   <= ex0_mem_read;
            mem0_mem_write  <= ex0_mem_write;
            mem0_mem_to_reg <= ex0_mem_to_reg;
            mem0_funct3     <= ex0_funct3;
            mem0_mem_class  <= ex0_mem_class;
            mem0_valid      <= ex0_valid;

            mem1_pc         <= ex1_pc;
            mem1_alu_result <= ex1_alu_result;
            mem1_store_data <= ex1_store_data;
            mem1_rd         <= ex1_rd;
            mem1_reg_write  <= ex1_reg_write;
            mem1_mem_read   <= ex1_mem_read;
            mem1_mem_write  <= ex1_mem_write;
            mem1_mem_to_reg <= ex1_mem_to_reg;
            mem1_funct3     <= ex1_funct3;
            mem1_mem_class  <= ex1_mem_class;
            mem1_valid      <= ex1_valid;
        end
    end
endmodule

// -----------------------------------------------------------------------------
// 4. MEM/WB Dual Pipeline Register
// -----------------------------------------------------------------------------
module mem_wb_superscalar_reg (
    input  logic        clk,
    input  logic        rst,
    input  logic        flush,
    input  logic        write_en,

    // Slot 0 Inputs from MEM
    input  logic [31:0] mem0_pc,
    input  logic [31:0] mem0_alu_result,
    input  logic [31:0] mem0_read_data,
    input  logic [4:0]  mem0_rd,
    input  logic        mem0_reg_write,
    input  logic        mem0_mem_to_reg,
    input  logic        mem0_valid,

    // Slot 1 Inputs from MEM
    input  logic [31:0] mem1_pc,
    input  logic [31:0] mem1_alu_result,
    input  logic [31:0] mem1_read_data,
    input  logic [4:0]  mem1_rd,
    input  logic        mem1_reg_write,
    input  logic        mem1_mem_to_reg,
    input  logic        mem1_valid,

    // Slot 0 Outputs to WB
    output logic [31:0] wb0_pc,
    output logic [31:0] wb0_alu_result,
    output logic [31:0] wb0_read_data,
    output logic [4:0]  wb0_rd,
    output logic        wb0_reg_write,
    output logic        wb0_mem_to_reg,
    output logic        wb0_valid,

    // Slot 1 Outputs to WB
    output logic [31:0] wb1_pc,
    output logic [31:0] wb1_alu_result,
    output logic [31:0] wb1_read_data,
    output logic [4:0]  wb1_rd,
    output logic        wb1_reg_write,
    output logic        wb1_mem_to_reg,
    output logic        wb1_valid
);
    always_ff @(posedge clk) begin
        if (rst || flush) begin
            wb0_pc          <= 32'd0;
            wb0_alu_result  <= 32'd0;
            wb0_read_data   <= 32'd0;
            wb0_rd          <= 5'd0;
            wb0_reg_write   <= 1'b0;
            wb0_mem_to_reg  <= 1'b0;
            wb0_valid       <= 1'b0;

            wb1_pc          <= 32'd0;
            wb1_alu_result  <= 32'd0;
            wb1_read_data   <= 32'd0;
            wb1_rd          <= 5'd0;
            wb1_reg_write   <= 1'b0;
            wb1_mem_to_reg  <= 1'b0;
            wb1_valid       <= 1'b0;
        end else if (write_en) begin
            wb0_pc          <= mem0_pc;
            wb0_alu_result  <= mem0_alu_result;
            wb0_read_data   <= mem0_read_data;
            wb0_rd          <= mem0_rd;
            wb0_reg_write   <= mem0_reg_write;
            wb0_mem_to_reg  <= mem0_mem_to_reg;
            wb0_valid       <= mem0_valid;

            wb1_pc          <= mem1_pc;
            wb1_alu_result  <= mem1_alu_result;
            wb1_read_data   <= mem1_read_data;
            wb1_rd          <= mem1_rd;
            wb1_reg_write   <= mem1_reg_write;
            wb1_mem_to_reg  <= mem1_mem_to_reg;
            wb1_valid       <= mem1_valid;
        end
    end
endmodule

