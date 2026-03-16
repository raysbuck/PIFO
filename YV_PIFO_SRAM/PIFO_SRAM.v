`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------

Proprietary and Confidential Information

Module: PIFO_SRAM.v
Author: Xiaoguang Li
Date  : 06/11/2019

Description: Instead of using FFs to implement PIFO, this module uses SRAM
             so that the whole PIFO tree can be extended to more layers. 
			 
-----------------------------------------------------------------------------*/

//-----------------------------------------------------------------------------
// Module Port Definition
//-----------------------------------------------------------------------------
module PIFO_SRAM 
#(
   parameter PTW  = 16,  // DATA WIDTH
   parameter MTW  = 32,
   parameter CTW  = 10,  // COUNT WIDTH
   parameter ADW  = 20   // ADDRESS WDITH
)
(
   // Clock and Reset
   input                    i_clk,         // I - Clock
   input                    i_arst_n,      // I - Active Low Async Reset
  
   // From/To Parent 
   input                    i_push,        // I - Push Command from Parent
   input [(MTW+PTW)-1:0]    i_push_data,   // I - Push Data from Parent
   
   input                    i_pop,         // I - Pop Command from Parent
   output [(MTW+PTW)+2-1:0] o_pop_data,    // O - Pop Data from Parent (with 2-bit source port)
   
   // From/To Child
   output                   o_push,        // O - Push Command to Child
   output [(MTW+PTW)-1:0]   o_push_data,   // O - Push Data to Child
   
   output                   o_pop,         // O - Pop Command to Child   
   input [(MTW+PTW)+2-1:0]  i_pop_data,    // I - Pop Data from Child (with 2-bit source port)
   
   // From/To SRAM 1
   output                   o_read_1,
   input [4*(CTW+MTW+PTW+2)-1:0] i_read_data_1,
   output                   o_write_1,
   output [4*(CTW+MTW+PTW+2)-1:0] o_write_data_1,
   output [ADW-1:0]         o_read_addr_1,
   output [ADW-1:0]         o_write_addr_1,

   // From/To SRAM 2
   output                   o_read_2,
   input [4*(CTW+MTW+PTW+2)-1:0] i_read_data_2,
   output                   o_write_2,
   output [4*(CTW+MTW+PTW+2)-1:0] o_write_data_2,
   output [ADW-1:0]         o_read_addr_2,
   output [ADW-1:0]         o_write_addr_2,

   input  [ADW-1:0]         i_my_addr,
   output  [ADW-1:0]        o_child_addr
);

//-----------------------------------------------------------------------------
// Parameters
//-----------------------------------------------------------------------------
localparam    ST_IDLE     = 2'b00,
			  ST_PUSH     = 2'b01,
              ST_POP_T2   = 2'b11;

localparam EW = CTW + MTW + PTW + 2; // Entry Width

//-----------------------------------------------------------------------------
// Register and Wire Declarations
//-----------------------------------------------------------------------------
   reg [1:0]             fsm;
   
   reg [(MTW+PTW)-1:0]   ipushd_latch;
   reg [ADW-1:0]         my_addr_q;
   reg [1:0]             pop_port_q;
   
   // Latch for SRAM 2 data to be used in T1
   reg [4*EW-1:0]        sram2_data_q;

   reg                   push;
   reg [(MTW+PTW)-1:0]   push_data;

//-----------------------------------------------------------------------------
// Sequential Logic
//-----------------------------------------------------------------------------
   always @ (posedge i_clk or negedge i_arst_n)
   begin
      if (!i_arst_n) begin
         fsm          <= ST_IDLE;
         ipushd_latch <= 'd0;	
         my_addr_q    <= 'd0;
         pop_port_q   <= 'd0;
         sram2_data_q <= {4{{CTW{1'b0}}, {(MTW+PTW){1'b1}}, 2'b00}};
      end else begin
         case (fsm)
            ST_IDLE: begin
               if (i_push) begin
                  fsm          <= ST_PUSH;
                  ipushd_latch <= i_push_data;
                  my_addr_q    <= i_my_addr;
               end else if (i_pop) begin
                  fsm          <= ST_POP_T2;
                  my_addr_q    <= i_my_addr;
                  // pop_port_q updated in comb logic or here
               end
            end

            ST_PUSH: begin
               fsm <= ST_IDLE;
            end

            ST_POP_T2: begin
               fsm <= ST_IDLE;
               sram2_data_q <= i_read_data_2; // Capture SRAM 2 data for next T1
            end
         endcase
      end
   end

   // Latch pop_port_q
   wire [1:0] t1_pop_port;
   always @ (posedge i_clk or negedge i_arst_n) begin
      if (!i_arst_n) pop_port_q <= 0;
      else if (fsm == ST_IDLE && i_pop) pop_port_q <= t1_pop_port;
   end

//-----------------------------------------------------------------------------
// Combinatorial Logic
//-----------------------------------------------------------------------------
   
   // --- Slicing for SRAM 1 (Read in T2, available in next T1) ---
   wire [CTW-1:0]     s1_size [0:3];
   wire [MTW+PTW-1:0] s1_val  [0:3];
   wire [PTW-1:0]     s1_prio [0:3];
   
   genvar gi;
   generate
      for (gi=0; gi<4; gi=gi+1) begin : s1_slice
         assign s1_size[gi] = i_read_data_1[gi*EW + (MTW+PTW+2) +: CTW];
         assign s1_val[gi]  = i_read_data_1[gi*EW + 2 +: (MTW+PTW)];
         assign s1_prio[gi] = i_read_data_1[gi*EW + 2 +: PTW];
      end
   endgenerate

   // --- Slicing for SRAM 2 (Read in T1, available in T2) ---
   wire [CTW-1:0]     s2_size [0:3];
   wire [MTW+PTW-1:0] s2_val  [0:3];
   wire [PTW-1:0]     s2_prio [0:3];
   wire [1:0]         s2_src  [0:3];
   
   generate
      for (gi=0; gi<4; gi=gi+1) begin : s2_slice
         assign s2_size[gi] = i_read_data_2[gi*EW + (MTW+PTW+2) +: CTW];
         assign s2_val[gi]  = i_read_data_2[gi*EW + 2 +: (MTW+PTW)];
         assign s2_prio[gi] = i_read_data_2[gi*EW + 2 +: PTW];
         assign s2_src[gi]  = i_read_data_2[gi*EW +: 2];
      end
   endgenerate

   // --- Slicing for Latch of SRAM 2 (Used in T1) ---
   wire [1:0]         s2_src_q [0:3];
   wire [PTW-1:0]     s2_prio_q [0:3];
   generate
      for (gi=0; gi<4; gi=gi+1) begin : s2q_slice
         assign s2_prio_q[gi] = sram2_data_q[gi*EW + 2 +: PTW];
         assign s2_src_q[gi]  = sram2_data_q[gi*EW +: 2];
      end
   endgenerate

   // --- Min finding logic for T1 (using SRAM 1 and forbidden port from SRAM 2) ---
   reg [1:0] forbidden_port;
   always @ * begin
      // Find min of current SRAM 2 to get its source port
      if (s2_prio_q[0] <= s2_prio_q[1] && s2_prio_q[0] <= s2_prio_q[2] && s2_prio_q[0] <= s2_prio_q[3])
         forbidden_port = s2_src_q[0];
      else if (s2_prio_q[1] <= s2_prio_q[2] && s2_prio_q[1] <= s2_prio_q[3])
         forbidden_port = s2_src_q[1];
      else if (s2_prio_q[2] <= s2_prio_q[3])
         forbidden_port = s2_src_q[2];
      else
         forbidden_port = s2_src_q[3];
   end

   assign t1_pop_port = (forbidden_port == 2'b00) ? ((s1_prio[1] <= s1_prio[2] && s1_prio[1] <= s1_prio[3]) ? 2'b01 : (s1_prio[2] <= s1_prio[3] ? 2'b10 : 2'b11)) :
                        (forbidden_port == 2'b01) ? ((s1_prio[0] <= s1_prio[2] && s1_prio[0] <= s1_prio[3]) ? 2'b00 : (s1_prio[2] <= s1_prio[3] ? 2'b10 : 2'b11)) :
                        (forbidden_port == 2'b10) ? ((s1_prio[0] <= s1_prio[1] && s1_prio[0] <= s1_prio[3]) ? 2'b00 : (s1_prio[1] <= s1_prio[3] ? 2'b01 : 2'b11)) :
                                                    ((s1_prio[0] <= s1_prio[1] && s1_prio[0] <= s1_prio[2]) ? 2'b00 : (s1_prio[1] <= s1_prio[2] ? 2'b01 : 2'b10));

   // --- Min finding logic for Push (using SRAM 2) ---
   reg [1:0] push_port;
   always @ * begin
      if (s2_size[0] <= s2_size[1] && s2_size[0] <= s2_size[2] && s2_size[0] <= s2_size[3]) push_port = 2'b00;
      else if (s2_size[1] <= s2_size[2] && s2_size[1] <= s2_size[3]) push_port = 2'b01;
      else if (s2_size[2] <= s2_size[3]) push_port = 2'b10;
      else push_port = 2'b11;
   end

   // --- Main Control Logic ---
   reg [EW-1:0] next_s [0:3];
   reg [4*EW-1:0] wdata_1, wdata_2;
   reg write_1, write_2;
   reg [ADW-1:0] child_addr;
   reg [(MTW+PTW)+2-1:0] pop_data_out;
   reg pop_sig;
   integer k;

   always @ * begin
      // Defaults
      push = 1'b0;
      push_data = {(MTW+PTW){1'b0}};
      pop_sig = 1'b0;
      write_1 = 1'b0;
      write_2 = 1'b0;
      wdata_1 = i_read_data_1;
      wdata_2 = i_read_data_2;
      child_addr = {ADW{1'b1}};
      pop_data_out = {(MTW+PTW+2){1'b1}};
      
      for (k=0; k<4; k=k+1) next_s[k] = {s2_size[k], s2_val[k], s2_src[k]};

      // T=1 Logic (In IDLE when i_pop is high)
      if (fsm == ST_IDLE && i_pop) begin
         pop_sig = 1'b1;
         child_addr = 4 * i_my_addr + t1_pop_port;
         write_1 = 1'b1;
         wdata_1 = i_read_data_2; // 寫入SRAM 1的值為SRAM 2的值
      end

      // T=2 Logic (In ST_POP_T2)
      if (fsm == ST_POP_T2) begin
         write_2 = 1'b1;
         pop_data_out = {s2_val[pop_port_q], s2_src[pop_port_q]};
         
         // Update SRAM 2 with i_pop_data
         if (s2_size[pop_port_q] != 0) next_s[pop_port_q] = {s2_size[pop_port_q] - 1'b1, i_pop_data};
         wdata_2 = {next_s[3], next_s[2], next_s[1], next_s[0]};
      end

      // Push Logic
      if (fsm == ST_PUSH) begin
         write_2 = 1'b1;
         child_addr = 4 * my_addr_q + push_port;
         if (s2_prio[push_port] != {PTW{1'b1}}) begin
            push = 1'b1;
            if (ipushd_latch[PTW-1:0] < s2_prio[push_port]) begin
               push_data = s2_val[push_port];
               next_s[push_port] = {s2_size[push_port] + 1'b1, ipushd_latch, push_port}; 
            end else begin
               push_data = ipushd_latch;
               next_s[push_port] = {s2_size[push_port] + 1'b1, s2_val[push_port], s2_src[push_port]};
            end
         end else begin
            next_s[push_port] = {s2_size[push_port] + 1'b1, ipushd_latch, push_port};
         end
         wdata_2 = {next_s[3], next_s[2], next_s[1], next_s[0]};
      end
   end

//-----------------------------------------------------------------------------
// Output Assignments
//-----------------------------------------------------------------------------
   assign o_read_1       = (fsm == ST_POP_T2); // T=2: 執行SRAM_READ 讀取SRAM 1
   assign o_read_addr_1  = my_addr_q;
   assign o_write_1      = write_1;
   assign o_write_addr_1 = i_my_addr;
   assign o_write_data_1 = wdata_1;

   assign o_read_2       = (fsm == ST_IDLE && i_pop); // T=1: 執行SRAM_READ 讀取SRAM 2
   assign o_read_addr_2  = i_my_addr;
   assign o_write_2      = write_2;
   assign o_write_addr_2 = my_addr_q;
   assign o_write_data_2 = wdata_2;

   assign o_push         = push;
   assign o_push_data    = push_data;
   assign o_pop          = pop_sig;
   assign o_pop_data     = pop_data_out;
   assign o_child_addr   = child_addr;

endmodule
