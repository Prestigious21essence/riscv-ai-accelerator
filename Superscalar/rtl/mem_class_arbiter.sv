// =============================================================================
// Module: mem_class_arbiter
// Description: Memory Subsystem Class Arbiter and Crossbar Interconnect for
//              2-Way Superscalar Core & Accelerated NPU.
//              - Dispatches memory requests across Dual-Port Data RAM and
//                NPU MMIO address space (>= 0x8000_0000).
//              - Implements MemClass structural conflict resolution:
//                  * MEM_STORE + MEM_STORE collision detection
//                  * MEM_BANK_A + MEM_BANK_A collision detection
//                  * Concurrent MEM_STORE + MEM_BANK_A/B co-issue
//                  * Concurrent MEM_BANK_A + MEM_BANK_B co-issue
//              - Implements intra-stage Store-to-Load forwarding:
//                  * If Slot 0 stores to word W and Slot 1 reads from word W,
//                    the written data is forwarded to Slot 1's read bus.
// =============================================================================

`timescale 1ns/1ps

module mem_class_arbiter (
    // -------------------------------------------------------------------------
    // Slot 0 (Pipe 0) Memory Stage Inputs
    // -------------------------------------------------------------------------
    input  logic        slot0_valid,
    input  logic        slot0_mem_read,
    input  logic        slot0_mem_write,
    input  logic [31:0] slot0_addr,
    input  logic [31:0] slot0_write_data,
    input  logic [2:0]  slot0_funct3,
    input  logic [1:0]  slot0_mem_class,

    // -------------------------------------------------------------------------
    // Slot 1 (Pipe 1) Memory Stage Inputs
    // -------------------------------------------------------------------------
    input  logic        slot1_valid,
    input  logic        slot1_mem_read,
    input  logic        slot1_mem_write,
    input  logic [31:0] slot1_addr,
    input  logic [31:0] slot1_write_data,
    input  logic [2:0]  slot1_funct3,
    input  logic [1:0]  slot1_mem_class,

    // -------------------------------------------------------------------------
    // Raw Memory Read Data from Dual-Port Data RAM
    // -------------------------------------------------------------------------
    input  logic [31:0] ram_read_data0,
    input  logic [31:0] ram_read_data1,

    // -------------------------------------------------------------------------
    // Raw NPU Read Data
    // -------------------------------------------------------------------------
    input  logic [31:0] npu_read_data0,
    input  logic [31:0] npu_read_data1,

    // -------------------------------------------------------------------------
    // Dispatched Controls to Dual-Port Data RAM
    // -------------------------------------------------------------------------
    output logic        ram_write0,
    output logic [31:0] ram_addr0,
    output logic [31:0] ram_write_data0,
    output logic [2:0]  ram_funct3_0,

    output logic        ram_write1,
    output logic [31:0] ram_addr1,
    output logic [31:0] ram_write_data1,
    output logic [2:0]  ram_funct3_1,

    // -------------------------------------------------------------------------
    // Dispatched Controls to NPU Coprocessor
    // -------------------------------------------------------------------------
    output logic        npu_write0,
    output logic        npu_read0,
    output logic [31:0] npu_addr0,
    output logic [31:0] npu_write_data0,

    output logic        npu_write1,
    output logic        npu_read1,
    output logic [31:0] npu_addr1,
    output logic [31:0] npu_write_data1,

    // -------------------------------------------------------------------------
    // Final Resolved Read Data to MEM/WB Pipeline Registers
    // -------------------------------------------------------------------------
    output logic [31:0] final_read_data0,
    output logic [31:0] final_read_data1,

    // -------------------------------------------------------------------------
    // Hazard & Forwarding Telemetry Flags
    // -------------------------------------------------------------------------
    output logic        is_npu_addr0,
    output logic        is_npu_addr1,
    output logic        mem_collision_detected,
    output logic        store_to_load_fwd
);

    localparam MEM_NONE   = 2'b00;
    localparam MEM_STORE  = 2'b01;
    localparam MEM_BANK_A = 2'b10;
    localparam MEM_BANK_B = 2'b11;

    // -------------------------------------------------------------------------
    // 1. Address Space Segmentation (>= 0x8000_0000 is NPU MMIO aperture)
    // -------------------------------------------------------------------------
    assign is_npu_addr0 = slot0_valid && (slot0_addr >= 32'h8000_0000);
    assign is_npu_addr1 = slot1_valid && (slot1_addr >= 32'h8000_0000);

    // -------------------------------------------------------------------------
    // 2. Data RAM Dispatch Routing
    // -------------------------------------------------------------------------
    assign ram_addr0       = slot0_addr;
    assign ram_write_data0 = slot0_write_data;
    assign ram_funct3_0    = slot0_funct3;
    assign ram_write0      = slot0_valid && slot0_mem_write && !is_npu_addr0;

    assign ram_addr1       = slot1_addr;
    assign ram_write_data1 = slot1_write_data;
    assign ram_funct3_1    = slot1_funct3;
    assign ram_write1      = slot1_valid && slot1_mem_write && !is_npu_addr1;

    // -------------------------------------------------------------------------
    // 3. NPU MMIO Dispatch Routing
    // -------------------------------------------------------------------------
    assign npu_addr0       = slot0_addr;
    assign npu_write_data0 = slot0_write_data;
    assign npu_write0      = slot0_valid && slot0_mem_write && is_npu_addr0;
    assign npu_read0       = slot0_valid && slot0_mem_read  && is_npu_addr0;

    assign npu_addr1       = slot1_addr;
    assign npu_write_data1 = slot1_write_data;
    assign npu_write1      = slot1_valid && slot1_mem_write && is_npu_addr1;
    assign npu_read1       = slot1_valid && slot1_mem_read  && is_npu_addr1;

    // -------------------------------------------------------------------------
    // 4. Memory Conflict Detection
    // -------------------------------------------------------------------------
    assign mem_collision_detected = slot0_valid && slot1_valid &&
                                    (slot0_mem_class != MEM_NONE) &&
                                    (slot0_mem_class == slot1_mem_class);

    // -------------------------------------------------------------------------
    // 5. Store-to-Load Forwarding Logic
    // Detects when Slot 0 stores to word W and Slot 1 reads from word W in RAM
    // -------------------------------------------------------------------------
    wire same_word = (slot0_addr[31:2] == slot1_addr[31:2]);
    assign store_to_load_fwd = slot0_valid && slot1_valid &&
                               slot0_mem_write && slot1_mem_read &&
                               !is_npu_addr0 && !is_npu_addr1 && same_word;

    // Byte/Halfword/Word store-to-load forwarding formatter
    logic [31:0] fwd_word;
    logic [1:0]  byte_off0;
    logic [1:0]  byte_off1;
    logic [7:0]  fwd_byte;
    logic [15:0] fwd_half;

    assign byte_off0 = slot0_addr[1:0];
    assign byte_off1 = slot1_addr[1:0];

    always_comb begin
        // Start with raw RAM read data
        fwd_word = ram_read_data1;
        case (slot0_funct3)
            3'b000:  fwd_word[byte_off0*8 +: 8]      = slot0_write_data[7:0];  // SB
            3'b001:  fwd_word[byte_off0[1]*16 +: 16] = slot0_write_data[15:0]; // SH
            default: fwd_word                        = slot0_write_data;       // SW
        endcase
    end

    assign fwd_byte = fwd_word[byte_off1*8 +: 8];
    assign fwd_half = fwd_word[byte_off1[1]*16 +: 16];

    logic [31:0] formatted_fwd_read;
    always_comb begin
        case (slot1_funct3)
            3'b000:  formatted_fwd_read = {{24{fwd_byte[7]}}, fwd_byte}; // LB
            3'b001:  formatted_fwd_read = {{16{fwd_half[15]}}, fwd_half}; // LH
            3'b100:  formatted_fwd_read = {24'b0, fwd_byte};             // LBU
            3'b101:  formatted_fwd_read = {16'b0, fwd_half};             // LHU
            default: formatted_fwd_read = fwd_word;                      // LW
        endcase
    end

    // -------------------------------------------------------------------------
    // 6. Final Read Data Multiplexing
    // -------------------------------------------------------------------------
    assign final_read_data0 = is_npu_addr0 ? npu_read_data0 : ram_read_data0;

    assign final_read_data1 = is_npu_addr1 ? npu_read_data1 :
                              (store_to_load_fwd ? formatted_fwd_read : ram_read_data1);

endmodule

