`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Astra_Node_L0.sv
Description: Level 0 (Root) node for Astra-PIFO. 
             Optimized for 1-cycle throughput by hiding backend SRAM latency.
-----------------------------------------------------------------------------*/

module Astra_Node_L0 #(
    parameter PTW = 16,
    parameter MTW = 32,
    parameter CTW = 10
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // User Interface (1-cycle Pop)
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    input  wire                   i_pop,
    output reg  [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_ready,

    // Backend (SRAM) Interface
    output reg  [3:0]             o_b_push,
    output reg  [(MTW+PTW)-1:0]    o_b_push_data,
    output reg  [3:0]             o_b_pop,
    input  wire [4*(MTW+PTW)-1:0]  i_b_pop_data,
    input  wire [3:0]             i_b_valid      // Backend data valid
);

    // --- Storage ---
    reg [(MTW+PTW)-1:0] slots [0:3];
    reg [CTW-1:0]       counts [0:3];
    
    // Shadow registers: Fed by the Backend
    reg [(MTW+PTW)-1:0] shadow_mins [0:3];
    reg [3:0]           shadow_valid;

    // --- Logic: Selection ---
    wire [1:0] best_slot_idx;
    wire [1:0] min_load_idx;
    
    // Find min priority among 4 internal slots
    assign best_slot_idx = (slots[0][PTW-1:0] <= slots[1][PTW-1:0] && 
                            slots[0][PTW-1:0] <= slots[2][PTW-1:0] && 
                            slots[0][PTW-1:0] <= slots[3][PTW-1:0]) ? 2'd0 :
                           (slots[1][PTW-1:0] <= slots[2][PTW-1:0] && 
                            slots[1][PTW-1:0] <= slots[3][PTW-1:0]) ? 2'd1 :
                           (slots[2][PTW-1:0] <= slots[3][PTW-1:0]) ? 2'd2 : 2'd3;

    assign min_load_idx  = (counts[0] <= counts[1] && counts[0] <= counts[2] && counts[0] <= counts[3]) ? 2'd0 :
                           (counts[1] <= counts[2] && counts[1] <= counts[3]) ? 2'd1 :
                           (counts[2] <= counts[3]) ? 2'd2 : 2'd3;

    assign o_ready = (counts[0] < {CTW{1'b1}}); // Simple ready logic

    // --- Control Logic ---
    always @(posedge i_clk or negedge i_arst_n) begin
        if (~i_arst_n) begin
            for (int i=0; i<4; i++) begin
                slots[i] <= {(MTW+PTW){1'b1}};
                counts[i] <= 0;
                shadow_mins[i] <= {(MTW+PTW){1'b1}};
            end
            shadow_valid <= 0;
            o_pop_data <= 0;
            o_b_push <= 0;
            o_b_pop  <= 0;
        end else begin
            // Update shadow registers when backend returns data
            for (int i=0; i<4; i++) begin
                if (i_b_valid[i]) begin
                    shadow_mins[i] <= i_b_pop_data[i*(MTW+PTW) +: (MTW+PTW)];
                    shadow_valid[i] <= 1'b1;
                end
            end

            // Default pulses
            o_b_push <= 0;
            o_b_pop  <= 0;

            case ({i_push, i_pop})
                2'b10: begin // PUSH
                    if (i_push_data[PTW-1:0] < slots[min_load_idx][PTW-1:0]) begin
                        o_b_push_data <= slots[min_load_idx];
                        slots[min_load_idx] <= i_push_data;
                    end else begin
                        o_b_push_data <= i_push_data;
                    end
                    o_b_push[min_load_idx] <= 1'b1;
                    counts[min_load_idx] <= counts[min_load_idx] + 1'b1;
                end

                2'b01: begin // POP
                    o_pop_data <= slots[best_slot_idx];
                    
                    // Critical: Immediate refill from Shadow
                    if (shadow_valid[best_slot_idx]) begin
                        slots[best_slot_idx] <= shadow_mins[best_slot_idx];
                        shadow_valid[best_slot_idx] <= 1'b0; // Consumed
                        o_b_pop[best_slot_idx] <= 1'b1;      // Trigger asynchronous refill
                    end else begin
                        slots[best_slot_idx] <= {(MTW+PTW){1'b1}};
                    end
                    counts[best_slot_idx] <= (counts[best_slot_idx] > 0) ? counts[best_slot_idx] - 1'b1 : 0;
                end
            endcase
        end
    end

endmodule
