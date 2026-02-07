`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Nexus_PIFO_TOP.sv
Description: Top-level implementation of Nexus-PIFO (Elastic PIFO).
             Combines hierarchical bitsets, elastic allocation, and micro-sorting.
-----------------------------------------------------------------------------*/

module Nexus_PIFO_TOP #(
    parameter PTW = 16,  // PRIORITY WIDTH
    parameter MTW = 32,  // METADATA WIDTH
    parameter ADW = 10,  // SRAM ADDRESS WIDTH
    parameter TENANTS = 16
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,
    
    // External Interface (Matches BMW Tree for fair comparison)
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    
    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_valid
);

    // 1. Hierarchical Bitset for Macro-level positioning
    wire [7:0] best_bucket_idx;
    wire       macro_valid;
    
    // For simplicity in prototype, we use bits [15:8] of priority as bucket ID
    wire [7:0] current_bucket_idx = i_push_data[15:8];
    wire [3:0] current_tenant_id  = i_push_data[PTW+MTW-1:PTW+MTW-4]; // Assuming high bits are tenant

    Nexus_Macro_Bitset u_bitset (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_set_valid(i_push),
        .i_bucket_idx(current_bucket_idx),
        .i_clear_valid(i_pop && o_empty_best), // Clear if micro-pifo becomes empty
        .o_valid(macro_valid),
        .o_best_bucket_idx(best_bucket_idx)
    );

    // 2. Elastic Allocator for SRAM mapping
    wire [ADW-1:0] sram_addr;
    Nexus_Elastic_Allocator u_alloc (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_bucket_id(i_pop ? best_bucket_idx : current_bucket_idx),
        .i_tenant_id(current_tenant_id),
        .o_sram_addr(sram_addr),
        .i_rebalance_trigger(1'b0)
    );

    // 3. Micro-sorting units (Cashed or Direct)
    // In this prototype, we'll instantiate a micro-sorting unit for the current access.
    // In a full implementation, this would interact with the SRAM blocks.
    wire o_empty_best;
    Nexus_Micro_Sorting u_micro (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_push(i_push && (current_bucket_idx == best_bucket_idx)), // Simplified
        .i_push_data(i_push_data),
        .i_pop(i_pop),
        .o_pop_data(o_pop_data),
        .o_full(),
        .o_empty(o_empty_best)
    );

    assign o_valid = macro_valid;

endmodule
