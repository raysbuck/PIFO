`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Zenith_PIFO_Top.sv
Description: High-performance Zenith-Tree Top Level.
             Optimized for Vivado 2023.2 Implementation.
-----------------------------------------------------------------------------*/

module Zenith_PIFO_Top #(
    parameter PTW    = 16,  // Priority Tag Width
    parameter MTW    = 32,  // Metadata Width
    parameter CTW    = 10,  // Counter Width
    parameter LEVEL  = 6    // Default level (supports ~5460 nodes)
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // Parent Interface (External)
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data
);

    // Calculate total nodes in a 4-way tree
    localparam TOTAL_NODES = ((4**LEVEL) - 1) / 3;
    localparam NON_LEAF_NODES = ((4**(LEVEL-1)) - 1) / 3;

    // --- Internal Interconnects ---
    wire                   node_push      [0:TOTAL_NODES-1];
    wire [(MTW+PTW)-1:0]    node_push_data [0:TOTAL_NODES-1];
    wire                   node_pop       [0:TOTAL_NODES-1];
    wire [(MTW+PTW)-1:0]    node_pop_out   [0:TOTAL_NODES-1];

    wire [3:0]             c_push_bus     [0:TOTAL_NODES-1];
    wire [(MTW+PTW)-1:0]    c_push_data    [0:TOTAL_NODES-1];
    wire [3:0]             c_pop_bus      [0:TOTAL_NODES-1];
    wire [4*(MTW+PTW)-1:0] c_pop_data_in  [0:TOTAL_NODES-1];

    // --- Tree Instantiation ---
    genvar i;
    generate
        for (i = 0; i < TOTAL_NODES; i = i + 1) begin : g_pifo_nodes
            Zenith_Node #(
                .PTW(PTW),
                .MTW(MTW),
                .CTW(CTW)
            ) u_node (
                .i_clk          (i_clk),
                .i_arst_n       (i_arst_n),
                
                // Interface to Parent
                .i_push         (node_push[i]),
                .i_push_data    (node_push_data[i]),
                .i_pop          (node_pop[i]),
                .o_pop_data     (node_pop_out[i]),

                // Interface to Children
                .o_c_push       (c_push_bus[i]),
                .o_c_push_data  (c_push_data[i]),
                .o_c_pop        (c_pop_bus[i]),
                .i_c_pop_data   (c_pop_data_in[i])
            );
        end
    endgenerate

    // --- Structural Connectivity Logic ---
    genvar p;
    generate
        for (p = 0; p < NON_LEAF_NODES; p = p + 1) begin : g_tree_conn
            // Push/Pop distribution to 4 children
            for (genvar c = 0; c < 4; c = c + 1) begin : g_child_link
                assign node_push[4*p + 1 + c]      = c_push_bus[p][c];
                assign node_push_data[4*p + 1 + c] = c_push_data[p];
                assign node_pop[4*p + 1 + c]       = c_pop_bus[p][c];
                
                // Collect child outputs into parent's input bus
                assign c_pop_data_in[p][(c+1)*(MTW+PTW)-1 : c*(MTW+PTW)] = node_pop_out[4*p + 1 + c];
            end
        end

        // Leaf Node Handling (No children)
        for (p = NON_LEAF_NODES; p < TOTAL_NODES; p = p + 1) begin : g_leaf_fix
            assign c_pop_data_in[p] = {4{(MTW+PTW)'(1'b1)}}; // Fill with max priority (empty)
        end
    endgenerate

    // --- Top-Level Root Connection ---
    assign node_push[0]      = i_push;
    assign node_push_data[0] = i_push_data;
    assign node_pop[0]       = i_pop;
    assign o_pop_data        = node_pop_out[0];

endmodule
