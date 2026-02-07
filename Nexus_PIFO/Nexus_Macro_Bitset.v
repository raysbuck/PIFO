`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Nexus_Macro_Bitset.v
Description: Two-level compressed bitset for fast bucket localization.
             Supports 256 buckets using a 16x16 hierarchical structure.
-----------------------------------------------------------------------------*/

module Nexus_Macro_Bitset #(
    parameter BUCKETS = 256,
    parameter L1_SIZE = 16,
    parameter L2_SIZE = 16
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,
    
    // Push: Mark a bucket as non-empty
    input  wire                   i_set_valid,
    input  wire [$clog2(BUCKETS)-1:0] i_bucket_idx,
    
    // Pop: Find the highest priority non-empty bucket
    input  wire                   i_clear_valid, // Optional: for simplicity in prototype
    output wire                   o_valid,
    output wire [$clog2(BUCKETS)-1:0] o_best_bucket_idx
);

    reg [L1_SIZE-1:0] l1_bitmap;
    reg [L2_SIZE-1:0] l2_bitmaps [0:L1_SIZE-1];

    wire [3:0] l1_idx = i_bucket_idx[7:4];
    wire [3:0] l2_idx = i_bucket_idx[3:0];

    // --- Write Logic ---
    always @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            l1_bitmap <= 0;
            for (integer i=0; i<L1_SIZE; i++) l2_bitmaps[i] <= 0;
        end else if (i_set_valid) begin
            l1_bitmap[l1_idx] <= 1'b1;
            l2_bitmaps[l1_idx][l2_idx] <= 1'b1;
        end
    end

    // --- Search Logic (Combinatorial for Speed) ---
    // Find First One (FFO) - Assuming lower index = higher priority
    wire [3:0] best_l1;
    wire [3:0] best_l2;
    wire l1_any_valid;
    
    // Priority Encoder for Level 1
    priority_encoder_16 u_pe_l1 (
        .i_data(l1_bitmap),
        .o_index(best_l1),
        .o_valid(l1_any_valid)
    );

    // Priority Encoder for Level 2 (indexed by best_l1)
    priority_encoder_16 u_pe_l2 (
        .i_data(l2_bitmaps[best_l1]),
        .o_index(best_l2),
        .o_valid() // Should be valid if l1_any_valid is true
    );

    assign o_valid = l1_any_valid;
    assign o_best_bucket_idx = {best_l1, best_l2};

endmodule

// Simple Priority Encoder for 16 bits (Low index has priority)
module priority_encoder_16 (
    input  wire [15:0] i_data,
    output reg  [3:0]  o_index,
    output wire        o_valid
);
    assign o_valid = |i_data;
    always @* begin
        if      (i_data[0])  o_index = 4'd0;
        else if (i_data[1])  o_index = 4'd1;
        else if (i_data[2])  o_index = 4'd2;
        else if (i_data[3])  o_index = 4'd3;
        else if (i_data[4])  o_index = 4'd4;
        else if (i_data[5])  o_index = 4'd5;
        else if (i_data[6])  o_index = 4'd6;
        else if (i_data[7])  o_index = 4'd7;
        else if (i_data[8])  o_index = 4'd8;
        else if (i_data[9])  o_index = 4'd9;
        else if (i_data[10]) o_index = 4'd10;
        else if (i_data[11]) o_index = 4'd11;
        else if (i_data[12]) o_index = 4'd12;
        else if (i_data[13]) o_index = 4'd13;
        else if (i_data[14]) o_index = 4'd14;
        else                 o_index = 4'd15;
    end
endmodule
