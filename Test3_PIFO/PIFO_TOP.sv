`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: PIFO_TOP.sv (Test3_PIFO - Structured High-Speed Top)
Description: 
    Hierarchical BMW-Tree with explicit pipeline connections.
    Optimized for Test3_PIFO nodes.
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

   // --- Input Isolation ---
   reg r_push, r_pop;
   reg [(MTW+PTW)-1:0] r_push_data;
   always @(posedge i_clk or negedge i_arst_n) begin
      if (!i_arst_n) begin
         r_push <= 0; r_pop <= 0; r_push_data <= 0;
      end else begin
         r_push <= i_push; r_pop <= i_pop; r_push_data <= i_push_data;
      end
   end

   // Node Arrays
   wire [TOTAL_NODES-1:0] n_push, n_pop;
   wire [(MTW+PTW)-1:0]   n_push_data [0:TOTAL_NODES-1];
   wire [(MTW+PTW)-1:0]   n_pop_data  [0:TOTAL_NODES-1];
   wire [(MTW+PTW)-1:0]   n_result    [0:TOTAL_NODES-1];

   wire [3:0]             n_push_to_c [0:TOTAL_NODES-1];
   wire [(MTW+PTW)-1:0]   n_data_to_c [0:TOTAL_NODES-1];
   wire [3:0]             n_pop_to_c  [0:TOTAL_NODES-1];
   wire [4*(MTW+PTW)-1:0] c_data_to_n [0:TOTAL_NODES-1];

   // --- Instantiation ---
   genvar i;
   generate
      for (i = 0; i < TOTAL_NODES; i = i + 1) begin : g_nodes
         PIFO #(
            .PTW(PTW), .MTW(MTW), .CTW(CTW)
         ) u_node (
            .i_clk          (i_clk),
            .i_arst_n       (i_arst_n),
            .i_push         (n_push[i]),
            .i_push_data    (n_push_data[i]),
            .i_pop          (n_pop[i]),
            .o_pop_data     (n_pop_data[i]),
            .o_push         (n_push_to_c[i]),
            .o_push_data    (n_data_to_c[i]),
            .o_pop          (n_pop_to_c[i]),
            .i_pop_data     (c_data_to_n[i]),
            .o_result       (n_result[i])
         );
      end
   endgenerate

   // --- Explicit Hierarchical Mapping ---
   genvar p;
   generate
      for (p = 0; p < LEAF_START; p = p + 1) begin : g_conn
         assign n_push[4*p+1] = n_push_to_c[p][0];
         assign n_push[4*p+2] = n_push_to_c[p][1];
         assign n_push[4*p+3] = n_push_to_c[p][2];
         assign n_push[4*p+4] = n_push_to_c[p][3];

         assign n_push_data[4*p+1] = n_data_to_c[p];
         assign n_push_data[4*p+2] = n_data_to_c[p];
         assign n_push_data[4*p+3] = n_data_to_c[p];
         assign n_push_data[4*p+4] = n_data_to_c[p];

         assign n_pop[4*p+1] = n_pop_to_c[p][0];
         assign n_pop[4*p+2] = n_pop_to_c[p][1];
         assign n_pop[4*p+3] = n_pop_to_c[p][2];
         assign n_pop[4*p+4] = n_pop_to_c[p][3];

         assign c_data_to_n[p] = {
            n_result[4*p+4],
            n_result[4*p+3],
            n_result[4*p+2],
            n_result[4*p+1]
         };
      end

      for (p = LEAF_START; p < TOTAL_NODES; p = p + 1) begin : g_leaf
         assign c_data_to_n[p] = {4{ {(MTW){1'b0}}, {(PTW){1'b1}} }};
      end
   endgenerate

   assign n_push[0]      = r_push;
   assign n_push_data[0] = r_push_data;
   assign n_pop[0]       = r_pop;
   assign o_pop_data     = n_pop_data[0];

endmodule
