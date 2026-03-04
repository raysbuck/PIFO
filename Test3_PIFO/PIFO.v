`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: PIFO.v (Test3_PIFO - High Performance Version)
Description: 
    1. Zero-Stall Concurrency: Push & Pop in 1 cycle via Swap-down.
    2. Predictive Selection: 2-level comparator tree for Fmax.
    3. RR-Balancing: Simplified 2-bit balancing.
-----------------------------------------------------------------------------*/

module PIFO #(
   parameter PTW    = 16,
   parameter MTW    = 32,
   parameter CTW    = 10
)
(
   input                      i_clk,
   input                      i_arst_n,

   input                      i_push,
   input  [(MTW+PTW)-1:0]     i_push_data,
   input                      i_pop,
   output reg [(MTW+PTW)-1:0] o_pop_data,

   output reg [3:0]           o_push,
   output reg [(MTW+PTW)-1:0] o_push_data,
   output reg [3:0]           o_pop,
   input  [4*(MTW+PTW)-1:0]   i_pop_data, 
   output reg [(MTW+PTW)-1:0] o_result    
);

   reg [PTW-1:0] p [0:3];
   reg [MTW-1:0] m [0:3];
   reg [3:0]     vld;
   reg [1:0]     rr_ptr;

   // --- Predictive Look-ahead ---
   wire [1:0] b01 = (vld[0] && (!vld[1] || p[0] <= p[1])) ? 2'd0 : 2'd1;
   wire [1:0] b23 = (vld[2] && (!vld[3] || p[2] <= p[3])) ? 2'd2 : 2'd3;
   wire [PTW-1:0] p01 = (b01 == 2'd0) ? p[0] : p[1];
   wire [PTW-1:0] p23 = (b23 == 2'd2) ? p[2] : p[3];
   wire [1:0] best_idx = (vld[b01] && (!vld[b23] || p01 <= p23)) ? b01 : b23;

   wire [PTW-1:0] best_p = p[best_idx];
   wire [MTW-1:0] best_m = m[best_idx];

   integer i;
   always @(posedge i_clk or negedge i_arst_n) begin
      if (!i_arst_n) begin
         vld <= 4'b0; rr_ptr <= 2'b0;
         o_push <= 4'b0; o_pop <= 4'b0; o_pop_data <= 0;
         o_result <= { {MTW{1'b0}}, {PTW{1'b1}} };
         for (i=0; i<4; i=i+1) begin p[i] <= {PTW{1'b1}}; m[i] <= 0; end
      end else begin
         o_push <= 4'b0; o_pop <= 4'b0;
         // o_result 始終反映當前最優解，供父節點預測使用
         o_result <= vld[best_idx] ? {m[best_idx], p[best_idx]} : { {MTW{1'b0}}, {PTW{1'b1}} };

         case ({i_push, i_pop})
            2'b10: begin // PUSH
               if (!vld[rr_ptr]) begin
                  p[rr_ptr] <= i_push_data[PTW-1:0];
                  m[rr_ptr] <= i_push_data[MTW+PTW-1:PTW];
                  vld[rr_ptr] <= 1'b1;
               end else if (i_push_data[PTW-1:0] < p[rr_ptr]) begin
                  p[rr_ptr] <= i_push_data[PTW-1:0];
                  m[rr_ptr] <= i_push_data[MTW+PTW-1:PTW];
                  o_push_data <= {m[rr_ptr], p[rr_ptr]};
                  o_push[rr_ptr] <= 1'b1;
               end else begin
                  o_push_data <= i_push_data;
                  o_push[rr_ptr] <= 1'b1;
               end
               rr_ptr <= rr_ptr + 1;
            end

            2'b01: begin // POP
               if (vld[best_idx]) begin
                  o_pop_data <= {m[best_idx], p[best_idx]};
                  if (i_pop_data[best_idx*(MTW+PTW) +: PTW] == {PTW{1'b1}}) begin
                     vld[best_idx] <= 1'b0;
                     p[best_idx] <= {PTW{1'b1}};
                  end else begin
                     p[best_idx] <= i_pop_data[best_idx*(MTW+PTW) +: PTW];
                     m[best_idx] <= i_pop_data[best_idx*(MTW+PTW)+PTW +: MTW];
                     o_pop[best_idx] <= 1'b1;
                  end
               end
            end

            2'b11: begin // CONCURRENT SWAP (Innovation)
               o_pop_data <= {m[best_idx], p[best_idx]};
               // 將新資料填入坑位並向下推
               p[best_idx] <= i_push_data[PTW-1:0];
               m[best_idx] <= i_push_data[MTW+PTW-1:PTW];
               o_push_data <= i_push_data;
               o_push[best_idx] <= 1'b1;
               // 注意：這裡不發送 o_pop 給子樹，而是用 Push 取代了 Pop 的空位
            end
         endcase
      end
   end
endmodule
