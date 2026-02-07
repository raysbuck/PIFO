`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: PRISM_Engine.sv
Description: The core processing engine for PRISM-PIFO.
             Features: 
             1. Occupancy-Mask based Path Pruning.
             2. Parallel 4-way Priority Sorting.
             3. Reduced Metadata (Compressed Count).
-----------------------------------------------------------------------------*/

module PRISM_Engine #(
    parameter PTW = 16,  // Priority Width
    parameter MTW = 32,  // Metadata Width
    parameter CTW = 10,  // Count Width
    parameter ADW = 20   // Address Width
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // Interface with Parent Stage
    input  wire                   i_valid,
    input  wire                   i_op_type, // 0: Push, 1: Pop
    input  wire [(MTW+PTW)-1:0]    i_data,
    input  wire [ADW-1:0]         i_node_addr,
    
    // Interface with SRAM
    output wire                   o_rd_en,
    output wire [ADW-1:0]         o_rd_addr,
    input  wire [4*(CTW+MTW+PTW)-1:0] i_rd_data, // {C3,V3, C2,V2, C1,V1, C0,V0}

    output wire                   o_wr_en,
    output wire [ADW-1:0]         o_wr_addr,
    output wire [4*(CTW+MTW+PTW)-1:0] o_wr_data,

    // Interface with Child Stage
    output reg                    o_child_valid,
    output reg                    o_child_op,
    output reg [(MTW+PTW)-1:0]     o_child_data,
    output reg [ADW-1:0]          o_child_addr,

    // Results back to Top
    output reg [(MTW+PTW)-1:0]     o_res_data,
    output reg                    o_res_valid
);

    // Internal wires for decomposed data
    wire [PTW-1:0] p_val [0:3];
    wire [CTW-1:0] p_cnt [0:3];
    wire [MTW-1:0] p_meta [0:3];

    genvar g;
    generate
        for (g=0; g<4; g=g+1) begin : decode
            assign p_val[g]  = i_rd_data[g*(CTW+MTW+PTW) +: PTW];
            assign p_meta[g] = i_rd_data[g*(CTW+MTW+PTW)+PTW +: MTW];
            assign p_cnt[g]  = i_rd_data[g*(CTW+MTW+PTW)+PTW+MTW +: CTW];
        end
    endgenerate

    // 1. Occupancy Mask Logic (PRISM Innovation: Path Pruning)
    wire [3:0] occupancy_mask;
    assign occupancy_mask[0] = (p_cnt[0] > 0);
    assign occupancy_mask[1] = (p_cnt[1] > 0);
    assign occupancy_mask[2] = (p_cnt[2] > 0);
    assign occupancy_mask[3] = (p_cnt[3] > 0);

    // 2. Sorting Logic (Find Minimum Priority)
    wire [1:0] min_idx;
    assign min_idx = (p_val[0] <= p_val[1] && p_val[0] <= p_val[2] && p_val[0] <= p_val[3]) ? 2'd0 :
                     (p_val[1] <= p_val[0] && p_val[1] <= p_val[2] && p_val[1] <= p_val[3]) ? 2'd1 :
                     (p_val[2] <= p_val[0] && p_val[2] <= p_val[1] && p_val[2] <= p_val[3]) ? 2'd2 : 2'd3;

    // 3. Balancing Logic (Find least loaded subtree for Push)
    wire [1:0] target_sub_idx;
    assign target_sub_idx = (p_cnt[0] <= p_cnt[1] && p_cnt[0] <= p_cnt[2] && p_cnt[0] <= p_cnt[3]) ? 2'd0 :
                            (p_cnt[1] <= p_cnt[0] && p_cnt[1] <= p_cnt[2] && p_cnt[1] <= p_cnt[3]) ? 2'd1 :
                            (p_cnt[2] <= p_cnt[0] && p_cnt[2] <= p_cnt[1] && p_cnt[2] <= p_cnt[3]) ? 2'd2 : 2'd3;

    // FSM States
    localparam IDLE = 2'b00, FETCH = 2'b01, PROC = 2'b10, WB = 2'b11;
    reg [1:0] state;

    // Latch inputs
    reg [(MTW+PTW)-1:0] r_data;
    reg [ADW-1:0]       r_addr;
    reg                 r_op;

    always @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            state <= IDLE;
            o_res_valid <= 0;
            o_child_valid <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (i_valid) begin
                        r_data <= i_data;
                        r_addr <= i_node_addr;
                        r_op   <= i_op_type;
                        state  <= FETCH;
                    end
                    o_res_valid <= 0;
                    o_child_valid <= 0;
                end

                FETCH: begin
                    state <= PROC; // Memory latency wait
                end

                PROC: begin
                    if (r_op == 1'b1) begin // POP
                        o_res_data <= {p_meta[min_idx], p_val[min_idx]};
                        o_res_valid <= 1;
                        // Child op setup
                        o_child_valid <= occupancy_mask[min_idx]; // PRUNING: Only go down if child not empty
                        o_child_op    <= 1'b1;
                        o_child_addr  <= (r_addr << 2) + min_idx + 1; // Implicit indexing
                    end else begin // PUSH
                        // Compare and Swap (BMW Tree logic but with implicit addressing)
                        if (r_data[PTW-1:0] < p_val[target_sub_idx]) begin
                            o_child_data  <= {p_meta[target_sub_idx], p_val[target_sub_idx]};
                            // New data stays in this level
                        end else begin
                            o_child_data  <= r_data;
                        end
                        o_child_valid <= 1;
                        o_child_op    <= 1'b0;
                        o_child_addr  <= (r_addr << 2) + target_sub_idx + 1;
                    end
                    state <= WB;
                end

                WB: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    // Output drive
    assign o_rd_en   = (state == IDLE && i_valid);
    assign o_rd_addr = i_node_addr;
    
    assign o_wr_en   = (state == PROC);
    assign o_wr_addr = r_addr;
    
    // Construct write data based on r_op (Simplified for prototype)
    assign o_wr_data = i_rd_data; // This would be the updated node content

endmodule
