`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Aether_PIFO_Node.sv
Description: High-Frequency Pipelined PIFO Node for Aether-Tree.
             Uses 2-stage pipeline to achieve 250MHz+ on Vivado.
             Stage 1: Comparison & Insertion Point Search
             Stage 2: Data Shifting & Command Propagation
-----------------------------------------------------------------------------*/

module Aether_PIFO_Node #(
    parameter PTW = 16,  // Priority Tag Width
    parameter MTW = 32,  // Metadata Width
    parameter DEPTH = 4  // 4-way sorting per node
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // Command Input (From Parent)
    input  wire                   i_valid,
    input  wire                   i_op,    // 0: Push, 1: Pop
    input  wire [(MTW+PTW)-1:0]    i_data,

    // Command Output (To Children)
    output reg                    o_c_valid,
    output reg                    o_c_op,
    output reg  [(MTW+PTW)-1:0]    o_c_data,
    output reg  [DEPTH-1:0]       o_c_mask, // Which child gets the command

    // Data Output (To Parent)
    output wire [(MTW+PTW)-1:0]    o_pop_data
);

    // Node Storage
    reg [(MTW+PTW)-1:0] slots [0:DEPTH-1];
    reg [DEPTH:0]       usage_cnt; // Number of active elements in this node

    // --- STAGE 1: Comparison Logic ---
    reg                    s1_valid, s1_op;
    reg [(MTW+PTW)-1:0]    s1_data;
    reg [DEPTH-1:0]       s1_comp_res; // Result of (i_data < slots[n])

    always @(posedge i_clk or negedge i_arst_n) begin
        if (~i_arst_n) begin
            s1_valid <= 0;
            s1_comp_res <= 0;
        end else begin
            s1_valid <= i_valid;
            s1_op    <= i_op;
            s1_data  <= i_data;
            // Parallel Comparison (Fixed latency, high frequency)
            for (int i=0; i<DEPTH; i++) begin
                s1_comp_res[i] <= (i_data[PTW-1:0] < slots[i][PTW-1:0]);
            end
        end
    end

    // --- STAGE 2: Update & Propagate ---
    // Finding insertion index using a simple priority encoder on comp_results
    wire [1:0] insert_idx;
    assign insert_idx = s1_comp_res[0] ? 2'd0 :
                        s1_comp_res[1] ? 2'd1 :
                        s1_comp_res[2] ? 2'd2 : 2'd3;

    always @(posedge i_clk or negedge i_arst_n) begin
        if (~i_arst_n) begin
            for (int i=0; i<DEPTH; i++) slots[i] <= {{(MTW){1'b0}}, {(PTW){1'b1}}};
            usage_cnt <= 0;
            o_c_valid <= 0;
        end else if (s1_valid) begin
            if (s1_op == 1'b0) begin : PUSH_LOGIC
                if (usage_cnt < DEPTH) begin
                    // Node not full, shift and insert
                    for (int i=DEPTH-1; i>=0; i--) begin
                        if (i > insert_idx) slots[i] <= slots[i-1];
                        else if (i == insert_idx) slots[i] <= s1_data;
                    end
                    usage_cnt <= usage_cnt + 1;
                    o_c_valid <= 0;
                end else begin
                    // Node full, kick out the worst (largest) and push to child
                    // Aether optimization: push to child that corresponds to the worst slot
                    o_c_valid <= 1;
                    o_c_op    <= 1'b0;
                    if (s1_comp_res == 4'b0000) begin
                        // New data is worst than all local data
                        o_c_data <= s1_data;
                        o_c_mask <= 4'b1000;
                    end else begin
                        o_c_data <= slots[DEPTH-1];
                        o_c_mask <= 4'b1000;
                        for (int i=DEPTH-1; i>=0; i--) begin
                            if (i > insert_idx) slots[i] <= slots[i-1];
                            else if (i == insert_idx) slots[i] <= s1_data;
                        end
                    end
                end
            end else begin : POP_LOGIC
                // Simply return slots[0], but in register version we need refill
                // (Simplified for register version)
                o_c_valid <= 1;
                o_c_op    <= 1'b1;
                o_c_mask  <= 4'b0001; // Request from child 0
            end
        end else begin
            o_c_valid <= 0;
        end
    end

    assign o_pop_data = slots[0];

endmodule
