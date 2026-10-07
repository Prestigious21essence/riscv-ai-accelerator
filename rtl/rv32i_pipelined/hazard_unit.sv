module hazard_unit (
    // ID stage register sources and usage
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,
    input  logic        id_uses_rs1,
    input  logic        id_uses_rs2,

    // EX stage register sources and destination
    input  logic [4:0]  id_ex_rs1,
    input  logic [4:0]  id_ex_rs2,
    input  logic [4:0]  id_ex_rd,
    input  logic        id_ex_mem_read,

    // MEM stage destination and write enable
    input  logic [4:0]  ex_mem_rd,
    input  logic        ex_mem_reg_write,

    // WB stage destination and write enable
    input  logic [4:0]  mem_wb_rd,
    input  logic        mem_wb_reg_write,

    // Control hazard signal from EX stage
    input  logic        ex_redirect,

    // Outputs: forwarding controls
    output logic [1:0]  forward_a,
    output logic [1:0]  forward_b,

    // Outputs: pipeline register control signals
    output logic        pc_write,
    output logic        if_id_write,
    output logic        flush_if_id,
    output logic        flush_id_ex
);

    // -------------------------------------------------------------------------
    // 1. FORWARDING UNIT (RAW Data Hazards)
    // -------------------------------------------------------------------------
    // Forward to ALU input A
    always_comb begin
        forward_a = 2'b00;
        // EX hazard (higher priority: most recent instruction in EX/MEM)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = 2'b10;
        end
        // MEM hazard (instruction in MEM/WB)
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = 2'b01;
        end
    end

    // Forward to ALU input B / Store Data
    always_comb begin
        forward_b = 2'b00;
        // EX hazard (higher priority: most recent instruction in EX/MEM)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = 2'b10;
        end
        // MEM hazard (instruction in MEM/WB)
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = 2'b01;
        end
    end

    // -------------------------------------------------------------------------
    // 2. LOAD-USE HAZARD STALL DETECTION
    // -------------------------------------------------------------------------
    // When instruction in EX is a load and instruction in ID depends on the
    // loaded register, we must stall IF and ID for 1 cycle and insert a bubble
    // into ID/EX.
    logic load_use_hazard;
    assign load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                             ((id_uses_rs1 && (id_rs1 == id_ex_rd)) ||
                              (id_uses_rs2 && (id_rs2 == id_ex_rd)));

    // -------------------------------------------------------------------------
    // 3. PIPELINE CONTROL: STALL & FLUSH PRIORITY
    // -------------------------------------------------------------------------
    // If a branch is taken or JAL/JALR executes in EX, it redirects PC and flushes
    // the speculatively fetched instructions in IF and ID. Control redirect has
    // higher priority than a load-use stall in ID.
    always_comb begin
        if (ex_redirect) begin
            // Branch/Jump taken: redirect PC, flush IF/ID and ID/EX
            pc_write    = 1'b1;
            if_id_write = 1'b1;
            flush_if_id = 1'b1;
            flush_id_ex = 1'b1;
        end else if (load_use_hazard) begin
            // Load-use hazard: stall PC and IF/ID, insert bubble (NOP) into ID/EX
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            flush_if_id = 1'b0;
            flush_id_ex = 1'b1;
        end else begin
            // Normal sequential execution: advance all stages
            pc_write    = 1'b1;
            if_id_write = 1'b1;
            flush_if_id = 1'b0;
            flush_id_ex = 1'b0;
        end
    end

endmodule

