`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Zenith_Node.sv
Description: The "Ultimate" 4-way PIFO Node. 
             Pipelined and Optimized for dual-enhancement (Function & Frequency).
             
Key Improvements:
1. Two-Stage Pipeline: Splits decision (Stage 1) and execution (Stage 2).
2. Frequency Boost: Breaks critical path by pipelining indices and inputs.
3. Decoupled Interface: Registered inputs and outputs cut inter-level coupling.
4. Concurrent Ready: Supports simultaneous Push and Pop with pipelined logic.
-----------------------------------------------------------------------------*/

module Zenith_Node #(
    parameter PTW = 16,  // Priority Width
    parameter MTW = 32,  // Metadata Width
    parameter CTW = 10   // Counter Width
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // Parent Interface
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    input  wire                   i_pop,
    output reg  [(MTW+PTW)-1:0]    o_pop_data,

    // Child Interface (4-way)
    output reg  [3:0]             o_c_push,
    output reg  [(MTW+PTW)-1:0]    o_c_push_data,
    output reg  [3:0]             o_c_pop,
    input  wire [4*(MTW+PTW)-1:0]  i_c_pop_data
);

    // --- Storage ---
    reg [(MTW+PTW)-1:0] slots [0:3];
    reg [CTW-1:0]       counts [0:3];
    reg [(MTW+PTW)-1:0] shadow_mins [0:3];

    // --- Stage 1: Pipeline Registers ---
    reg [1:0]           best_child_idx_q;
    reg [1:0]           min_load_idx_q;
    reg                 i_push_q, i_pop_q;
    reg [(MTW+PTW)-1:0] i_push_data_q;

    // --- Stage 1: Decision Logic with Bypass ---
    // Bypass is needed to handle back-to-back operations within the 2-stage pipeline
    wire [CTW-1:0] effective_counts [0:3];
    wire [1:0]     next_min_load_idx;
    wire [1:0]     next_best_child_idx;

    generate
        for (genvar i=0; i<4; i++) begin : g_eff_counts
            assign effective_counts[i] = (i_push_q && min_load_idx_q == i[1:0]) ? counts[i] + 1'b1 :
                                         (i_pop_q  && best_child_idx_q == i[1:0]) ? counts[i] - 1'b1 :
                                         counts[i];
        end
    endgenerate

    // Accuracy: Find min priority among shadow mins (Stage 1)
    assign next_best_child_idx = (shadow_mins[0][PTW-1:0] <= shadow_mins[1][PTW-1:0] && 
                                  shadow_mins[0][PTW-1:0] <= shadow_mins[2][PTW-1:0] && 
                                  shadow_mins[0][PTW-1:0] <= shadow_mins[3][PTW-1:0]) ? 2'd0 :
                                 (shadow_mins[1][PTW-1:0] <= shadow_mins[2][PTW-1:0] && 
                                  shadow_mins[1][PTW-1:0] <= shadow_mins[3][PTW-1:0]) ? 2'd1 :
                                 (shadow_mins[2][PTW-1:0] <= shadow_mins[3][PTW-1:0]) ? 2'd2 : 2'd3;

    // Balance: Find min load among counts (Stage 1)
    assign next_min_load_idx  = (effective_counts[0] <= effective_counts[1] && 
                                 effective_counts[0] <= effective_counts[2] && 
                                 effective_counts[0] <= effective_counts[3]) ? 2'd0 :
                                (effective_counts[1] <= effective_counts[2] && 
                                 effective_counts[1] <= effective_counts[3]) ? 2'd1 :
                                (effective_counts[2] <= effective_counts[3]) ? 2'd2 : 2'd3;

    // --- Stage 1: Update Pipeline Registers ---
    always @(posedge i_clk or negedge i_arst_n) begin
        if (~i_arst_n) begin
            best_child_idx_q <= 0;
            min_load_idx_q <= 0;
            i_push_q <= 0;
            i_pop_q <= 0;
            i_push_data_q <= 0;
        end else begin
            best_child_idx_q <= next_best_child_idx;
            min_load_idx_q  <= next_min_load_idx;
            i_push_q        <= i_push;
            i_pop_q         <= i_pop;
            i_push_data_q   <= i_push_data;
        end
    end

    // --- Stage 2: Execution & Output Drive ---
    always @(posedge i_clk or negedge i_arst_n) begin
        if (~i_arst_n) begin
            for (int i=0; i<4; i++) begin
                slots[i] <= {(MTW+PTW){1'b1}};
                counts[i] <= 0;
                shadow_mins[i] <= {(MTW+PTW){1'b1}};
            end
            o_pop_data <= 0;
            o_c_push <= 0;
            o_c_push_data <= 0;
            o_c_pop  <= 0;
        end else begin
            // Update shadow registers from children (Always-on update from i_c_pop_data)
            for (int i=0; i<4; i++) begin
                shadow_mins[i] <= i_c_pop_data[i*(MTW+PTW) +: (MTW+PTW)];
            end

            // Default pulses
            o_c_push <= 0;
            o_c_pop  <= 0;

            case ({i_push_q, i_pop_q})
                2'b10: begin // PUSH
                    if (i_push_data_q[PTW-1:0] < slots[min_load_idx_q][PTW-1:0]) begin
                        o_c_push_data <= slots[min_load_idx_q];
                        slots[min_load_idx_q] <= i_push_data_q;
                    end else begin
                        o_c_push_data <= i_push_data_q;
                    end
                    o_c_push[min_load_idx_q] <= 1'b1;
                    counts[min_load_idx_q] <= counts[min_load_idx_q] + 1'b1;
                end

                2'b01: begin // POP
                    o_pop_data <= slots[best_child_idx_q];
                    slots[best_child_idx_q] <= shadow_mins[best_child_idx_q];
                    o_c_pop[best_child_idx_q] <= 1'b1;
                    counts[best_child_idx_q] <= counts[best_child_idx_q] - 1'b1;
                end

                2'b11: begin // CONCURRENT (The "Zenith" Power)
                    o_pop_data <= (i_push_data_q[PTW-1:0] < slots[best_child_idx_q][PTW-1:0]) ? i_push_data_q : slots[best_child_idx_q];
                    if (i_push_data_q[PTW-1:0] >= slots[best_child_idx_q][PTW-1:0]) begin
                        slots[best_child_idx_q] <= i_push_data_q;
                    end
                    // Counts remain unchanged in concurrent mode
                end
            endcase
        end
    end

endmodule
