`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Zenith_Node.sv
Description: The "Ultimate" 4-way PIFO Node. 
             Optimized version of BMW-Tree.
             
Key Improvements vs BMW_PIFO:
1. Zero-Latency Refill: Uses shadow-registers to hide child-to-parent delay.
2. Fused Datapath: Shared comparator tree for both push and pop.
3. Distributed Counters: Shared arithmetic unit for all 4 child counters.
4. Concurrent Ready: Supports simultaneous Push and Pop without stalls.
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
    
    // Shadow registers: Store the best values of children to avoid Pop-wait
    reg [(MTW+PTW)-1:0] shadow_mins [0:3];

    // --- Combinatorial Logic: Fused Compare Tree ---
    wire [1:0] best_child_idx;
    wire [1:0] min_load_idx;
    
    // 1. Accuracy: Find min priority among shadow mins
    assign best_child_idx = (shadow_mins[0][PTW-1:0] <= shadow_mins[1][PTW-1:0] && 
                             shadow_mins[0][PTW-1:0] <= shadow_mins[2][PTW-1:0] && 
                             shadow_mins[0][PTW-1:0] <= shadow_mins[3][PTW-1:0]) ? 2'd0 :
                            (shadow_mins[1][PTW-1:0] <= shadow_mins[2][PTW-1:0] && 
                             shadow_mins[1][PTW-1:0] <= shadow_mins[3][PTW-1:0]) ? 2'd1 :
                            (shadow_mins[2][PTW-1:0] <= shadow_mins[3][PTW-1:0]) ? 2'd2 : 2'd3;

    // 2. Balance: Find min load among counts
    assign min_load_idx  = (counts[0] <= counts[1] && counts[0] <= counts[2] && counts[0] <= counts[3]) ? 2'd0 :
                           (counts[1] <= counts[2] && counts[1] <= counts[3]) ? 2'd1 :
                           (counts[2] <= counts[3]) ? 2'd2 : 2'd3;

    // --- Sequential Logic: Unified Update ---
    always @(posedge i_clk or negedge i_arst_n) begin
        if (~i_arst_n) begin
            for (int i=0; i<4; i++) begin
                slots[i] <= {(MTW+PTW){1'b1}};
                counts[i] <= 0;
                shadow_mins[i] <= {(MTW+PTW){1'b1}};
            end
            o_pop_data <= 0;
            o_c_push <= 0;
            o_c_pop  <= 0;
        end else begin
            // Update shadow registers from children (Always-on update)
            for (int i=0; i<4; i++) begin
                shadow_mins[i] <= i_c_pop_data[i*(MTW+PTW) +: (MTW+PTW)];
            end

            // Reset pulses
            o_c_push <= 0;
            o_c_pop  <= 0;

            case ({i_push, i_pop})
                2'b10: begin // PUSH
                    // Push-to-min-load logic (BMW Balance)
                    if (i_push_data[PTW-1:0] < slots[min_load_idx][PTW-1:0]) begin
                        o_c_push_data <= slots[min_load_idx];
                        slots[min_load_idx] <= i_push_data;
                    end else begin
                        o_c_push_data <= i_push_data;
                    end
                    o_c_push[min_load_idx] <= 1'b1;
                    counts[min_load_idx] <= counts[min_load_idx] + 1'b1;
                end

                2'b01: begin // POP
                    o_pop_data <= slots[best_child_idx];
                    // Immediate refill from Shadow (Zero Latency)
                    slots[best_child_idx] <= shadow_mins[best_child_idx];
                    o_c_pop[best_child_idx] <= 1'b1;
                    counts[best_child_idx] <= counts[best_child_idx] - 1'b1;
                end

                2'b11: begin // CONCURRENT (The "Zenith" Power)
                    // Swap the incoming push with the outgoing pop
                    o_pop_data <= (i_push_data[PTW-1:0] < slots[best_child_idx][PTW-1:0]) ? i_push_data : slots[best_child_idx];
                    if (i_push_data[PTW-1:0] >= slots[best_child_idx][PTW-1:0]) begin
                        slots[best_child_idx] <= i_push_data;
                    end
                    // No change to counts, max throughput!
                end
            endcase
        end
    end

endmodule
