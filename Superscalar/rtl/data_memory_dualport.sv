// =============================================================================
// Module: data_memory_dualport
// Description: True Dual-Port Synchronous Data Memory for 2-Way Superscalar Core.
//              - Independent Port 0 (Pipe 0) and Port 1 (Pipe 1) interfaces.
//              - Simultaneous dual read accesses to any addresses (including same word).
//              - Independent byte/halfword/word masked write access on both ports.
//              - Internal write-first bypass if Port 0 writes to the same word
//                being read by Port 1 in the same cycle.
//              - Configurable memory size (default: 1024 words = 4 KB).
// =============================================================================

`timescale 1ns/1ps

module data_memory_dualport #(
    parameter MEM_WORDS = 1024
)(
    input  logic        clk,

    // -------------------------------------------------------------------------
    // Port 0 Interface (Pipeline Slot 0)
    // -------------------------------------------------------------------------
    input  logic        mem_write0,
    input  logic [31:0] addr0,
    input  logic [31:0] write_data0,
    input  logic [2:0]  funct3_0,
    output logic [31:0] read_data0,

    // -------------------------------------------------------------------------
    // Port 1 Interface (Pipeline Slot 1)
    // -------------------------------------------------------------------------
    input  logic        mem_write1,
    input  logic [31:0] addr1,
    input  logic [31:0] write_data1,
    input  logic [2:0]  funct3_1,
    output logic [31:0] read_data1
);

    logic [31:0] mem [0:MEM_WORDS-1];
    localparam IDX_HI = $clog2(MEM_WORDS) + 1;

    // -------------------------------------------------------------------------
    // Port 0 Read Logic
    // -------------------------------------------------------------------------
    logic [31:0] word0;
    logic [1:0]  byte_off0;
    logic [7:0]  byte_val0;
    logic [15:0] half_val0;

    assign word0     = mem[addr0[IDX_HI:2]];
    assign byte_off0 = addr0[1:0];
    assign byte_val0 = word0[byte_off0*8 +: 8];
    assign half_val0 = word0[byte_off0[1]*16 +: 16];

    always_comb begin
        case (funct3_0)
            3'b000:  read_data0 = {{24{byte_val0[7]}}, byte_val0};   // LB
            3'b001:  read_data0 = {{16{half_val0[15]}}, half_val0};  // LH
            3'b100:  read_data0 = {24'b0, byte_val0};                // LBU
            3'b101:  read_data0 = {16'b0, half_val0};                // LHU
            default: read_data0 = word0;                             // LW
        endcase
    end

    // -------------------------------------------------------------------------
    // Port 1 Read Logic (with internal write-first bypass from Port 0)
    // -------------------------------------------------------------------------
    logic [31:0] raw_word1;
    logic [31:0] effective_word1;
    logic [1:0]  byte_off1;
    logic [7:0]  byte_val1;
    logic [15:0] half_val1;

    assign raw_word1 = mem[addr1[IDX_HI:2]];

    // Internal write-to-read bypass: if Port 0 writes in the current cycle
    // to the exact word Port 1 is reading, forward the written word
    always_comb begin
        if (mem_write0 && (addr0[IDX_HI:2] == addr1[IDX_HI:2])) begin
            case (funct3_0)
                3'b000: begin // SB
                    effective_word1 = raw_word1;
                    effective_word1[byte_off0*8 +: 8] = write_data0[7:0];
                end
                3'b001: begin // SH
                    effective_word1 = raw_word1;
                    effective_word1[byte_off0[1]*16 +: 16] = write_data0[15:0];
                end
                default: begin // SW
                    effective_word1 = write_data0;
                end
            endcase
        end else begin
            effective_word1 = raw_word1;
        end
    end

    assign byte_off1 = addr1[1:0];
    assign byte_val1 = effective_word1[byte_off1*8 +: 8];
    assign half_val1 = effective_word1[byte_off1[1]*16 +: 16];

    always_comb begin
        case (funct3_1)
            3'b000:  read_data1 = {{24{byte_val1[7]}}, byte_val1};   // LB
            3'b001:  read_data1 = {{16{half_val1[15]}}, half_val1};  // LH
            3'b100:  read_data1 = {24'b0, byte_val1};                // LBU
            3'b101:  read_data1 = {16'b0, half_val1};                // LHU
            default: read_data1 = effective_word1;                   // LW
        endcase
    end

    // -------------------------------------------------------------------------
    // Synchronous Writes on posedge clk
    // Priority: If both write to the exact same word, Port 1 takes priority (younger)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        // Port 0 write: only commits if Port 1 is not writing to the same word
        if (mem_write0) begin
            if (!(mem_write1 && (addr1[IDX_HI:2] == addr0[IDX_HI:2]))) begin
                case (funct3_0)
                    3'b000:  mem[addr0[IDX_HI:2]][byte_off0*8 +: 8]      <= write_data0[7:0];
                    3'b001:  mem[addr0[IDX_HI:2]][byte_off0[1]*16 +: 16] <= write_data0[15:0];
                    default: mem[addr0[IDX_HI:2]]                        <= write_data0;
                endcase
            end
        end

        // Port 1 write: commits with highest priority in the cycle
        if (mem_write1) begin
            case (funct3_1)
                3'b000:  mem[addr1[IDX_HI:2]][byte_off1*8 +: 8]      <= write_data1[7:0];
                3'b001:  mem[addr1[IDX_HI:2]][byte_off1[1]*16 +: 16] <= write_data1[15:0];
                default: mem[addr1[IDX_HI:2]]                        <= write_data1;
            endcase
        end
    end

endmodule

