`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: PIFO_TOP.sv (Test2_PIFO - Hierarchical Optimized)
Description: 
    Systolic BMW-Tree Top Level.
    Uses balanced 4-way branching with registered inter-node communication.
-----------------------------------------------------------------------------*/

module PIFO_TOP #(
   parameter PTW    = 16,
   parameter MTW    = 32,
   parameter CTW    = 10,
   parameter LEVEL  = 6 
 )(
   input               i_clk,
   input               i_arst_n,
   
   input               i_push,
   input [(MTW+PTW)-1:0]  i_push_data,
   
   input               i_pop,
   output [(MTW+PTW)-1:0] o_pop_data      
);

   localparam TOTAL_NODES = ( (4**LEVEL) - 1 ) / 3;
   localparam LEAF_START  = ( (4**(LEVEL-1)) - 1 ) / 3;

   // --- Input Isolation Registers ---
   reg r_push, r_pop;
   reg [(MTW+PTW)-1:0] r_push_data;
   
   always @(posedge i_clk or negedge i_arst_n) begin
      if (!i_arst_n) begin
         r_push      <= 1'b0;
         r_pop       <= 1'b0;
         r_push_data <= 'd0;
      end else begin
         r_push      <= i_push;
         r_pop       <= i_pop;
         r_push_data <= i_push_data;
      end
   end

   // Node Arrays
   wire [TOTAL_NODES-1:0] node_push_in, node_pop_in;
   wire [(MTW+PTW)-1:0]   node_push_data_in [0:TOTAL_NODES-1];
   wire [(MTW+PTW)-1:0]   node_pop_data_out [0:TOTAL_NODES-1];
   wire [(MTW+PTW)-1:0]   node_result_out   [0:TOTAL_NODES-1];

   wire [3:0]             node_push_to_child [0:TOTAL_NODES-1];
   wire [(MTW+PTW)-1:0]   node_data_to_child [0:TOTAL_NODES-1];
   wire [3:0]             node_pop_to_child  [0:TOTAL_NODES-1];
   wire [4*(MTW+PTW)-1:0] child_data_to_node [0:TOTAL_NODES-1];

   // --- Node Instantiation ---
   generate
      genvar i;
      for (i = 0; i < TOTAL_NODES; i = i + 1) begin : gen_tree
         PIFO #(
            .PTW(PTW), .MTW(MTW), .CTW(CTW)
         ) u_node (
            .i_clk          (i_clk),
            .i_arst_n       (i_arst_n),
            .i_push         (node_push_in[i]),
            .i_push_data    (node_push_data_in[i]),
            .i_pop          (node_pop_in[i]),
            .o_pop_data     (node_pop_data_out[i]),
            .o_push         (node_push_to_child[i]),
            .o_push_data    (node_data_to_child[i]),
            .o_pop          (node_pop_to_child[i]),
            .i_pop_data     (child_data_to_node[i]),
            .o_result       (node_result_out[i])
         );
      end
   endgenerate

   // --- High-Speed Connection Mapping ---
   generate
      genvar p;
      for (p = 0; p < LEAF_START; p = p + 1) begin : gen_conn
         assign node_push_in[4*p+1] = node_push_to_child[p][0];
         assign node_push_in[4*p+2] = node_push_to_child[p][1];
         assign node_push_in[4*p+3] = node_push_to_child[p][2];
         assign node_push_in[4*p+4] = node_push_to_child[p][3];

         assign node_push_data_in[4*p+1] = node_data_to_child[p];
         assign node_push_data_in[4*p+2] = node_data_to_child[p];
         assign node_push_data_in[4*p+3] = node_data_to_child[p];
         assign node_push_data_in[4*p+4] = node_data_to_child[p];

         assign node_pop_in[4*p+1] = node_pop_to_child[p][0];
         assign node_pop_in[4*p+2] = node_pop_to_child[p][1];
         assign node_pop_in[4*p+3] = node_pop_to_child[p][2];
         assign node_pop_in[4*p+4] = node_pop_to_child[p][3];

         // Child o_result is the cached value for the parent.
         assign child_data_to_node[p] = {
            node_result_out[4*p+4],
            node_result_out[4*p+3],
            node_result_out[4*p+2],
            node_result_out[4*p+1]
         };
      end

      // Leaf Nodes (Bottom Level Termination)
      for (p = LEAF_START; p < TOTAL_NODES; p = p + 1) begin : gen_leaf_term
         assign child_data_to_node[p] = {4{ {(MTW){1'b0}}, {(PTW){1'b1}} }};
      end
   endgenerate

   // --- Top Level Connectivity ---
   assign node_push_in[0]      = r_push;
   assign node_push_data_in[0] = r_push_data;
   assign node_pop_in[0]       = r_pop;

   // Global Pop Result
   // We use the root's pop data directly for minimum latency on the final exit.
   assign o_pop_data = node_pop_data_out[0];

endmodule
