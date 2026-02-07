`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Turbo_Engine.sv
Description: Optimized BMW Engine with Hybrid Storage Support.
             Supports Register-based (Level 0) and SRAM-based (Level 1+) modes.
-----------------------------------------------------------------------------*/

module Turbo_Engine #(
    parameter PTW = 16,
    parameter MTW = 32,
    parameter CTW = 10,
    parameter ADW = 16,
    parameter IS_ROOT = 0 // 1: Use Registers, 0: Use SRAM Interface
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // Control Interface
    input  wire                   i_valid,
    input  wire                   i_op_type, // 0: Push, 1: Pop
    input  wire [(MTW+PTW)-1:0]    i_data,
    input  wire [ADW-1:0]         i_node_addr,

    // SRAM Interface (Only used if IS_ROOT = 0)
    output wire                   o_sram_rd,
    output wire [ADW-1:0]         o_sram_addr,
    input  wire [4*(CTW+MTW+PTW)-1:0] i_sram_data,

    // Downstream Interface
    output reg                    o_next_valid,
    output reg                    o_next_op,
    output reg [(MTW+PTW)-1:0]     o_next_data,
    output reg [ADW-1:0]          o_next_addr,

    // Final Result (for Pop)
    output reg [(MTW+PTW)-1:0]     o_res_data,
    output reg                    o_res_valid
);

    // Internal Storage for Root Level
    reg [4*(CTW+MTW+PTW)-1:0] root_regs;
    
    // Data decomposition
    wire [PTW-1:0] p_val [0:3];
    wire [CTW-1:0] p_cnt [0:3];
    wire [MTW-1:0] p_meta [0:3];
    
    wire [4*(CTW+MTW+PTW)-1:0] current_node_data = IS_ROOT ? root_regs : i_sram_data;

    genvar g;
    generate
        for (g=0; g<4; g=g+1) begin : decode
            assign p_val[g]  = current_node_data[g*(CTW+MTW+PTW) +: PTW];
            assign p_meta[g] = current_node_data[g*(CTW+MTW+PTW)+PTW +: MTW];
            assign p_cnt[g]  = current_node_data[g*(CTW+MTW+PTW)+PTW+MTW +: CTW];
        end
    endgenerate

    // Sorting & Balancing Logic
    wire [1:0] min_idx = (p_val[0] <= p_val[1] && p_val[0] <= p_val[2] && p_val[0] <= p_val[3]) ? 2'd0 :
                         (p_val[1] <= p_val[0] && p_val[1] <= p_val[2] && p_val[1] <= p_val[3]) ? 2'd1 :
                         (p_val[2] <= p_val[0] && p_val[2] <= p_val[1] && p_val[2] <= p_val[3]) ? 2'd2 : 2'd3;

    wire [1:0] tgt_idx = (p_cnt[0] <= p_cnt[1] && p_cnt[0] <= p_cnt[2] && p_cnt[0] <= p_cnt[3]) ? 2'd0 :
                         (p_cnt[1] <= p_cnt[0] && p_cnt[1] <= p_cnt[2] && p_cnt[1] <= p_cnt[3]) ? 2'd1 :
                         (p_cnt[2] <= p_cnt[0] && p_cnt[2] <= p_cnt[1] && p_cnt[2] <= p_cnt[3]) ? 2'd2 : 2'd3;

    // Execution Logic
    always @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            o_next_valid <= 0;
            o_res_valid  <= 0;
            if (IS_ROOT) root_regs <= {4{ {CTW{1'b0}}, {MTW{1'b0}}, {PTW{1'b1}} }};
        end else if (i_valid) begin
            if (i_op_type == 1'b1) begin // POP
                o_res_data  <= {p_meta[min_idx], p_val[min_idx]};
                o_res_valid <= 1;
                o_next_op    <= 1'b1;
                o_next_addr  <= (i_node_addr << 2) + min_idx + 1;
                o_next_valid <= (p_cnt[min_idx] > 0);
            end else begin // PUSH
                // Simplified BMW Swap
                if (i_data[PTW-1:0] < p_val[tgt_idx]) begin
                    o_next_data <= {p_meta[tgt_idx], p_val[tgt_idx]};
                    // In real implementation, update current_node_data here
                end else begin
                    o_next_data <= i_data;
                end
                o_next_op    <= 1'b0;
                o_next_addr  <= (i_node_addr << 2) + tgt_idx + 1;
                o_next_valid <= 1;
            end
        end else begin
            o_next_valid <= 0;
            o_res_valid  <= 0;
        end
    end

    assign o_sram_rd   = !IS_ROOT && i_valid;
    assign o_sram_addr = i_node_addr;

endmodule
