// =============================================================================
// Module: register_file_4r2w
// Description: 32-entry x 32-bit General Purpose Register File for Dual-Issue
//              Superscalar RV32I Core.
//              - 4 Asynchronous Read Ports (2 for Pipe 0, 2 for Pipe 1)
//              - 2 Synchronous Write Ports (1 for Pipe 0 WB, 1 for Pipe 1 WB)
//              - Register x0 is hardwired to 32'h00000000.
//              - Internal Write-to-Read (Write-First) Bypassing with age-based
//                priority (Port 1 is later in program order than Port 0).
//              - Synchronous WAW resolution: Port 1 takes precedence on collisions.
// =============================================================================

`timescale 1ns/1ps

module register_file_4r2w (
    input  logic        clk,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // Read Ports - Slot 0 (Pipeline 0)
    // -------------------------------------------------------------------------
    input  logic [4:0]  rs1_addr0,
    input  logic [4:0]  rs2_addr0,
    output logic [31:0] rs1_data0,
    output logic [31:0] rs2_data0,

    // -------------------------------------------------------------------------
    // Read Ports - Slot 1 (Pipeline 1)
    // -------------------------------------------------------------------------
    input  logic [4:0]  rs1_addr1,
    input  logic [4:0]  rs2_addr1,
    output logic [31:0] rs1_data1,
    output logic [31:0] rs2_data1,

    // -------------------------------------------------------------------------
    // Write Ports - Slot 0 and Slot 1 (Writeback)
    // -------------------------------------------------------------------------
    input  logic        we0,
    input  logic [4:0]  rd_addr0,
    input  logic [31:0] rd_data0,

    input  logic        we1,
    input  logic [4:0]  rd_addr1,
    input  logic [31:0] rd_data1
);

    // 32 x 32-bit register storage
    logic [31:0] regs [31:0];

    // =========================================================================
    // Asynchronous Read Ports with Priority Write-First Bypassing
    // Priority order:
    // 1. x0 is unconditionally 0
    // 2. Port 1 write-first bypass (Slot 1 is younger / later in program order)
    // 3. Port 0 write-first bypass (Slot 0 is older / earlier in program order)
    // 4. Register array storage
    // =========================================================================

    // Slot 0 - Operand 1
    always_comb begin
        if (rs1_addr0 == 5'd0) begin
            rs1_data0 = 32'd0;
        end else if (we1 && (rd_addr1 == rs1_addr0)) begin
            rs1_data0 = rd_data1;
        end else if (we0 && (rd_addr0 == rs1_addr0)) begin
            rs1_data0 = rd_data0;
        end else begin
            rs1_data0 = regs[rs1_addr0];
        end
    end

    // Slot 0 - Operand 2
    always_comb begin
        if (rs2_addr0 == 5'd0) begin
            rs2_data0 = 32'd0;
        end else if (we1 && (rd_addr1 == rs2_addr0)) begin
            rs2_data0 = rd_data1;
        end else if (we0 && (rd_addr0 == rs2_addr0)) begin
            rs2_data0 = rd_data0;
        end else begin
            rs2_data0 = regs[rs2_addr0];
        end
    end

    // Slot 1 - Operand 1
    always_comb begin
        if (rs1_addr1 == 5'd0) begin
            rs1_data1 = 32'd0;
        end else if (we1 && (rd_addr1 == rs1_addr1)) begin
            rs1_data1 = rd_data1;
        end else if (we0 && (rd_addr0 == rs1_addr1)) begin
            rs1_data1 = rd_data0;
        end else begin
            rs1_data1 = regs[rs1_addr1];
        end
    end

    // Slot 1 - Operand 2
    always_comb begin
        if (rs2_addr1 == 5'd0) begin
            rs2_data1 = 32'd0;
        end else if (we1 && (rd_addr1 == rs2_addr1)) begin
            rs2_data1 = rd_data1;
        end else if (we0 && (rd_addr0 == rs2_addr1)) begin
            rs2_data1 = rd_data0;
        end else begin
            rs2_data1 = regs[rs2_addr1];
        end
    end

    // =========================================================================
    // Synchronous Register Writes on posedge clk
    // WAW Conflict Resolution:
    // If both Port 0 and Port 1 write to the same non-zero destination register
    // in the same clock cycle, Port 1 (Slot 1) takes precedence and Port 0 write
    // is masked.
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 32; i++) begin
                regs[i] <= 32'd0;
            end
        end else begin
            // Port 0 write: only commits if Port 1 is not targeting the same register
            if (we0 && (rd_addr0 != 5'd0)) begin
                if (!(we1 && (rd_addr1 == rd_addr0))) begin
                    regs[rd_addr0] <= rd_data0;
                end
            end

            // Port 1 write: always commits (highest age priority in current cycle)
            if (we1 && (rd_addr1 != 5'd0)) begin
                regs[rd_addr1] <= rd_data1;
            end
        end
    end

endmodule

