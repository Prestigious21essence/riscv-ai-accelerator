module hazard_unit_stallbranch (
    // ID stage register sources and usage
    input  logic [4:0]  id_rs1,
    input  logic [4:0]  id_rs2,
    input  logic        id_uses_rs1,
    input  logic        id_uses_rs2,
    input  logic        id_branch_or_jump, // 1 if ID holds branch, JAL, or JALR

    // EX stage register sources and destination
    input  logic [4:0]  id_ex_rs1,
    input  logic [4:0]  id_ex_rs2,
    input  logic [4:0]  id_ex_rd,
    input  logic        id_ex_mem_read,
    input  logic        ex_branch_or_jump, // 1 if EX holds branch, JAL, or JALR

    // MEM stage destination and write enable
    input  logic [4:0]  ex_mem_rd,
    input  logic        ex_mem_reg_write,

    // WB stage destination and write enable
    input  logic [4:0]  mem_wb_rd,
    input  logic        mem_wb_reg_write,

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
    logic load_use_hazard;
    assign load_use_hazard = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                             ((id_uses_rs1 && (id_rs1 == id_ex_rd)) ||
                              (id_uses_rs2 && (id_rs2 == id_ex_rd)));

    // -------------------------------------------------------------------------
    // 3. ALWAYS-STALL ON BRANCH CONTROL LOGIC
    // -------------------------------------------------------------------------
    // In this scheme, NO speculative execution occurs for branches or jumps:
    // - Priority 1: Load-use hazard must stall first (including when a branch
    //   in ID depends on a load currently in EX).
    // - Priority 2: When branch/jump is in EX:
    //   The branch resolves in EX. Target/fallthrough PC is applied, PC is enabled
    //   to update on the clock edge, and IF/ID receives a bubble for this transition cycle.
    // - Priority 3: When branch/jump is in ID:
    //   Freeze instruction fetch (pc_write = 0, flush_if_id = 1). The branch in ID
    //   is allowed to advance into EX (flush_id_ex = 0).
    // - Default: Normal sequential execution.

    always_comb begin
        if (load_use_hazard) begin
            // Load-use stall: freeze PC and IF/ID, insert bubble (NOP) into ID/EX
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            flush_if_id = 1'b0;
            flush_id_ex = 1'b1;
        end else if (ex_branch_or_jump) begin
            // Branch/jump is resolving in EX this cycle.
            // Enable PC update to the resolved target/fallthrough address.
            // Insert bubble in IF/ID so pipeline cleanly receives the target next cycle.
            pc_write    = 1'b1;
            if_id_write = 1'b1;
            flush_if_id = 1'b1;
            flush_id_ex = 1'b0;
        end else if (id_branch_or_jump) begin
            // Branch/jump just arrived in ID.
            // Stall instruction fetch until branch reaches EX and resolves.
            // Discard whatever was in IF (insert bubble), allow branch to advance to EX.
            pc_write    = 1'b0;
            if_id_write = 1'b1;
            flush_if_id = 1'b1;
            flush_id_ex = 1'b0;
        end else begin
            // Normal sequential execution
            pc_write    = 1'b1;
            if_id_write = 1'b1;
            flush_if_id = 1'b0;
            flush_id_ex = 1'b0;
        end
    end

endmodule

