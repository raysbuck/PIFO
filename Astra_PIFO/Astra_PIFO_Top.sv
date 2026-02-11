`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Astra_PIFO_Top.sv
Description: Top-level module for Astra_PIFO tree structure.
             Supports parameterized levels. 
             Level=6 provides 5460 flows (nodes=1365).
             Level=8 provides 87380 flows (nodes=21845).
-----------------------------------------------------------------------------*/

module Astra_PIFO_Top #(
    parameter PTW    = 16,  // Priority Tag Width
    parameter MTW    = 32,  // Metadata Width
    parameter CTW    = 10,  // Counter Width
    parameter LEVEL  = 6    // Default level for 87380 flows (matches BMW_PIFO)
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // Parent Interface
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data
);

    // Helper Functions for indexing
    function integer flat_max(input integer l);
        integer total, i;
        begin
            total = 0;
            for (i=0; i<l; i=i+1) total = total + (4**i);
            flat_max = total;
        end
    endfunction

    function integer get_level(input integer idx);
        integer i, total;
        begin
            total = 0;
            get_level = 0;
            for (i=0; i<LEVEL; i=i+1) begin
                total = total + (4**i);
                if (idx < total) begin
                    get_level = i;
                    i = LEVEL; // break
                end
            end
        end
    endfunction

    localparam TOTAL_NODES = flat_max(LEVEL);

    // Interconnect wires
    wire [TOTAL_NODES-1:0]          node_push;
    wire [(MTW+PTW)-1:0]            node_push_data_in [0:TOTAL_NODES-1];
    wire [TOTAL_NODES-1:0]          node_pop;
    wire [(MTW+PTW)-1:0]            node_pop_data_out [0:TOTAL_NODES-1];
    
    wire [3:0]                      child_push [0:TOTAL_NODES-1];
    wire [(MTW+PTW)-1:0]            child_push_data_out [0:TOTAL_NODES-1];
    wire [3:0]                      child_pop [0:TOTAL_NODES-1];
    wire [4*(MTW+PTW)-1:0]          child_pop_data_in [0:TOTAL_NODES-1];
    
    wire [(MTW+PTW)-1:0]            node_best_data [0:TOTAL_NODES-1];

    // Instantiate Nodes
    generate
        for (genvar i=0; i<TOTAL_NODES; i=i+1) begin : gen_nodes
            Astra_PIFO #(
                .PTW(PTW),
                .MTW(MTW),
                .CTW(CTW)
            ) u_node (
                .i_clk(i_clk),
                .i_arst_n(i_arst_n),
                .i_push(node_push[i]),
                .i_push_data(node_push_data_in[i]),
                .i_pop(node_pop[i]),
                .o_pop_data(node_pop_data_out[i]),
                .o_ready(),
                .o_push(child_push[i]),
                .o_push_data(child_push_data_out[i]),
                .o_pop(child_pop[i]),
                .i_pop_data(child_pop_data_in[i]),
                .o_best_data(node_best_data[i])
            );
        end
    endgenerate

    // Connect Nodes
    generate
        for (genvar i=0; i<TOTAL_NODES; i=i+1) begin : gen_conn
            if (i == 0) begin
                // Root Node
                assign node_push[0] = i_push;
                assign node_push_data_in[0] = i_push_data;
                assign node_pop[0] = i_pop;
            end
            
            // Connect to 4 children
            for (genvar c=0; c<4; c=c+1) begin : gen_child_conn
                localparam CHILD_IDX = i*4 + 1 + c;
                if (CHILD_IDX < TOTAL_NODES) begin
                    // Child exists
                    assign node_push[CHILD_IDX] = child_push[i][c];
                    assign node_push_data_in[CHILD_IDX] = child_push_data_out[i];
                    assign node_pop[CHILD_IDX] = child_pop[i][c];
                    
                    assign child_pop_data_in[i][(c+1)*(MTW+PTW)-1 : c*(MTW+PTW)] = node_pop_data_out[CHILD_IDX];
                end else begin
                    // Leaf node behavior for this child slot
                    if (c == 0) assign child_pop_data_in[i] = {(4*(MTW+PTW)){1'b1}};
                end
            end
        end
    endgenerate

    // Root Output
    assign o_pop_data = node_pop_data_out[0];

endmodule
