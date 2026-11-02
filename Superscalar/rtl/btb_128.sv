// =============================================================================
// Module: btb_128
// Description: 128-entry Direct-Mapped Branch Target Buffer (BTB) with 2-bit
//              saturating counter branch direction predictor for Superscalar Core.
//              - Index: addr[8:2] (128 entries)
//              - Tag: addr[31:9] (23 bits)
//              - 2-bit Saturating Counter:
//                  2'b00: Strongly Not-Taken
//                  2'b01: Weakly Not-Taken
//                  2'b10: Weakly Taken
//                  2'b11: Strongly Taken
// =============================================================================

`timescale 1ns/1ps

module btb_128 (
    input  logic        clk,
    input  logic        rst,

    // Query Port (Fetch Stage)
    input  logic [31:0] query_pc,
    output logic        predict_taken,
    output logic [31:0] predict_target,

    // Update Port (Execution Stage - Branch Resolution)
    input  logic        update_en,
    input  logic [31:0] update_pc,
    input  logic [31:0] update_target,
    input  logic        actual_taken
);

    typedef struct packed {
        logic        valid;
        logic [22:0] tag;
        logic [31:0] target;
        logic [1:0]  state; // 2-bit saturating counter
    } btb_entry_t;

    btb_entry_t btb_array [127:0];

    // Query lookup
    logic [6:0] query_idx;
    logic [22:0] query_tag;
    assign query_idx = query_pc[8:2];
    assign query_tag = query_pc[31:9];

    always_comb begin
        if (btb_array[query_idx].valid && (btb_array[query_idx].tag == query_tag)) begin
            predict_taken  = (btb_array[query_idx].state >= 2'b10);
            predict_target = btb_array[query_idx].target;
        end else begin
            predict_taken  = 1'b0;
            predict_target = query_pc + 32'd4;
        end
    end

    // Update on branch resolution
    logic [6:0] update_idx;
    logic [22:0] update_tag;
    assign update_idx = update_pc[8:2];
    assign update_tag = update_pc[31:9];

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 128; i++) begin
                btb_array[i].valid  = 1'b0;
                btb_array[i].tag    = 23'd0;
                btb_array[i].target = 32'd0;
                btb_array[i].state  = 2'b01; // Weakly Not-Taken default
            end
        end else if (update_en) begin
            btb_array[update_idx].valid  <= 1'b1;
            btb_array[update_idx].tag    <= update_tag;
            btb_array[update_idx].target <= update_target;

            // Saturating counter update
            if (actual_taken) begin
                if (btb_array[update_idx].state < 2'b11)
                    btb_array[update_idx].state <= btb_array[update_idx].state + 2'b01;
            end else begin
                if (btb_array[update_idx].state > 2'b00)
                    btb_array[update_idx].state <= btb_array[update_idx].state - 2'b01;
            end
        end
    end

endmodule

