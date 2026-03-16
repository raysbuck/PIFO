`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------

Proprietary and Confidential Information

Module: PIFO_SRAM.v
Author: Xiaoguang Li
Date  : 06/11/2019

Description: Instead of using FFs to implement PIFO, this module uses SRAM
             so that the whole PIFO tree can be extended to more layers. 
			 
Issues:  

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
   input [(MTW+PTW)-1:0]          i_push_data,   // I - Push Data from Parent
   
   input                    i_pop,         // I - Pop Command from Parent
   output [(MTW+PTW)-1:0]         o_pop_data,    // O - Pop Data from Parent
   
   // From/To Child
   output                   o_push,        // O - Push Command to Child
   output [(MTW+PTW)-1:0]         o_push_data,   // O - Push Data to Child
   
   output                   o_pop,         // O - Pop Command to Child   
   input [(MTW+PTW)-1:0]          i_pop_data,    // I - Pop Data from Child
   
   // From/To SRAM
   output                   o_read,        // O - SRAM Read
   input [4*(CTW+MTW+PTW)-1:0]  i_read_data,   // I - SRAM Read Data {sub_tree_size3,pifo_val3,sub_tree_size2,pifo_val2,sub_tree_size1,pifo_val1,sub_tree_size0,pifo_val0}
   
   output                   o_write,       // O - SRAM Write
   output [4*(CTW+MTW+PTW)-1:0] o_write_data,   // O - SRAM Write Data {sub_tree_size3,pifo_val3,sub_tree_size2,pifo_val2,sub_tree_size1,pifo_val1,sub_tree_size0,pifo_val0}

   input  [ADW-1:0]         i_my_addr,
   output  [ADW-1:0]        o_child_addr,

   output  [ADW-1:0]        o_read_addr,
   output  [ADW-1:0]        o_write_addr
);

//-----------------------------------------------------------------------------
// Include Files
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// Parameters
//-----------------------------------------------------------------------------
localparam    ST_IDLE     = 2'b00,
			  ST_PUSH     = 2'b01,
              ST_POP      = 2'b11,
	 	 	  ST_WB       = 2'b10;

//-----------------------------------------------------------------------------
// Register and Wire Declarations
//-----------------------------------------------------------------------------
   // State Machine
   reg [1:0]             fsm;
   
   // SRAM Read/Write   
   wire                  read;
   reg                   write;
   reg [4*(CTW+MTW+PTW)-1:0] wdata;
   
   // Push to child
   reg                   push;
   reg [(MTW+PTW)-1:0]         push_data;
      
   reg                   pop;
   reg [(MTW+PTW)-1:0]         pop_data;   
	  
   reg [1:0]             min_sub_tree;
   reg [1:0]             min_data_port;
   
   reg [(MTW+PTW)-1:0]         ipushd_latch;

	//for parent/child node
   reg [ADW-1:0]         my_addr;
   reg [ADW-1:0]         child_addr;
   
   

   
   

     
//-----------------------------------------------------------------------------
// Instantiations
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// Functions and Tasks
//-----------------------------------------------------------------------------

//-----------------------------------------------------------------------------
// Sequential Logic
//-----------------------------------------------------------------------------
   always @ (posedge i_clk or negedge i_arst_n)
   begin
      if (!i_arst_n) begin
         fsm[1:0]     <= ST_IDLE;
         ipushd_latch <= 'd0;	
		 my_addr      <= 'd0;

      end else begin
	     case (fsm[1:0])
            ST_IDLE: begin
			   case ({i_push, i_pop})
                  2'b00,
				  2'b11: begin // Not allow concurrent read and write
                     fsm[1:0]    <= ST_IDLE;
                     ipushd_latch <= 'd0;
					my_addr      <= 'd0;		 
				  end
                  2'b01: begin // pop
                    fsm[1:0]    <= ST_POP;
                    ipushd_latch <= 'd0;
					my_addr      <= i_my_addr;	 
				  end
				  2'b10: begin // push
                    fsm[1:0]     <= ST_PUSH;
                    ipushd_latch <= i_push_data;		
					my_addr      <= i_my_addr; 
				  end
			   endcase
            end

            ST_PUSH: begin       	
               case ({i_push, i_pop})
                  2'b00,
				  2'b11: begin 
                     fsm[1:0]    <= ST_IDLE;
                     ipushd_latch <= 'd0;	
					 my_addr      <= 'd0; 
				  end
                  2'b01: begin
                    fsm[1:0]    <= ST_POP;
                    ipushd_latch <= 'd0;		 
					my_addr      <= i_my_addr;
				  end
				  2'b10: begin 
                    fsm[1:0]    <= ST_PUSH;
                    ipushd_latch <= i_push_data;
					my_addr      <= i_my_addr;			 
				  end
			   endcase   
			end   

            ST_POP: begin
               ipushd_latch <= ipushd_latch;		
			   my_addr      <= my_addr;
  		       fsm[1:0]     <= ST_WB;
            end		
            
			ST_WB: begin		       
  		       	case ({i_push, i_pop})
                  2'b00,
				  2'b11: begin 
                     fsm[1:0]    <= ST_IDLE;
                     ipushd_latch <= 'd0;		
					 my_addr      <= 'd0; 
				  end
                  2'b01: begin
                    fsm[1:0]    <= ST_POP;
                    ipushd_latch <= 'd0;	
					my_addr      <= i_my_addr;		 
				  end
				  2'b10: begin 
                    fsm[1:0]    <= ST_PUSH;
                    ipushd_latch <= i_push_data;	
					my_addr      <= i_my_addr; 
				  end
			   endcase
			end			
 	     endcase
      end	  
   end
   
//-----------------------------------------------------------------------------
// Combinatorial Logic / Continuous Assignments
//-----------------------------------------------------------------------------
   
   // Slice SRAM data into components for easier processing and lower fan-in
   wire [CTW-1:0]        s0_size = i_read_data[1*(CTW+MTW+PTW)-1 : 1*(CTW+MTW+PTW)-CTW];
   wire [MTW+PTW-1:0]    s0_val  = i_read_data[1*(CTW+MTW+PTW)-CTW-1 : 0*(CTW+MTW+PTW)];
   wire [PTW-1:0]        s0_prio = s0_val[PTW-1:0];

   wire [CTW-1:0]        s1_size = i_read_data[2*(CTW+MTW+PTW)-1 : 2*(CTW+MTW+PTW)-CTW];
   wire [MTW+PTW-1:0]    s1_val  = i_read_data[2*(CTW+MTW+PTW)-CTW-1 : 1*(CTW+MTW+PTW)];
   wire [PTW-1:0]        s1_prio = s1_val[PTW-1:0];

   wire [CTW-1:0]        s2_size = i_read_data[3*(CTW+MTW+PTW)-1 : 3*(CTW+MTW+PTW)-CTW];
   wire [MTW+PTW-1:0]    s2_val  = i_read_data[3*(CTW+MTW+PTW)-1-CTW : 2*(CTW+MTW+PTW)];
   wire [PTW-1:0]        s2_prio = s2_val[PTW-1:0];

   wire [CTW-1:0]        s3_size = i_read_data[4*(CTW+MTW+PTW)-1 : 4*(CTW+MTW+PTW)-CTW];
   wire [MTW+PTW-1:0]    s3_val  = i_read_data[4*(CTW+MTW+PTW)-1-CTW : 3*(CTW+MTW+PTW)];
   wire [PTW-1:0]        s3_prio = s3_val[PTW-1:0];

   // Minimum Sub-tree size calculation using a 2-stage comparison tree (Reduced Fan-in)
   wire c01_st = (s0_size <= s1_size);
   wire [1:0] idx01_st = c01_st ? 2'b00 : 2'b01;
   wire [CTW-1:0] val01_st = c01_st ? s0_size : s1_size;

   wire c23_st = (s2_size <= s3_size);
   wire [1:0] idx23_st = c23_st ? 2'b10 : 2'b11;
   wire [CTW-1:0] val23_st = c23_st ? s2_size : s3_size;

   wire c_st_final = (val01_st <= val23_st);
   wire [1:0] res_st_idx = c_st_final ? idx01_st : idx23_st;

   // --- Precise PIFO with Minimal Fan-in (Balanced Binary Tree) ---
   // Stage 1: Parallel Binary Comparisons
   // Node A: Compare Port 0 and Port 1
   wire        win01_sel = (s0_prio <= s1_prio);
   wire [1:0]  idx01     = win01_sel ? 2'b00 : 2'b01;
   wire [PTW-1:0] val01  = win01_sel ? s0_prio : s1_prio;

   // Node B: Compare Port 2 and Port 3
   wire        win23_sel = (s2_prio <= s3_prio);
   wire [1:0]  idx23     = win23_sel ? 2'b10 : 2'b11;
   wire [PTW-1:0] val23  = win23_sel ? s2_prio : s3_prio;

   // Stage 2: Final Binary Comparison
   // Node C: Compare Winners of Stage 1
   wire        win_final_sel = (val01 <= val23);
   wire [1:0]  res_dp_idx    = win_final_sel ? idx01 : idx23;

   // Similar logic for Sub-tree size (Push path)
   wire        win01_st_sel = (s0_size <= s1_size);
   wire [1:0]  idx01_st     = win01_st_sel ? 2'b00 : 2'b01;
   wire [CTW-1:0] val01_st  = win01_st_sel ? s0_size : s1_size;

   wire        win23_st_sel = (s2_size <= s3_size);
   wire [1:0]  idx23_st     = win23_st_sel ? 2'b10 : 2'b11;
   wire [CTW-1:0] val23_st  = win23_st_sel ? s2_size : s3_size;

   wire        win_st_final_sel = (val01_st <= val23_st);
   wire [1:0]  res_st_idx       = win_st_final_sel ? idx01_st : idx23_st;

   reg [CTW+MTW+PTW-1:0] next_s0, next_s1, next_s2, next_s3;

   always @ *
   begin
      // Update Min selection
      min_sub_tree  = res_st_idx;
      min_data_port = res_dp_idx;

      // Default values
      push      = 1'b0;
      push_data = 0;
      pop       = 1'b0;
      pop_data  = {(MTW+PTW){1'b1}};
      write     = 1'b0;
      wdata     = i_read_data;
      child_addr = {(ADW){1'b1}};
      
      next_s0 = {s0_size, s0_val};
      next_s1 = {s1_size, s1_val};
      next_s2 = {s2_size, s2_val};
      next_s3 = {s3_size, s3_val};

      if (fsm == ST_POP || fsm == ST_WB) begin
         pop   = 1'b1;
         write = 1'b1;
         case (min_data_port)
            2'b00: begin
               pop_data = s0_val;
               child_addr = 4 * my_addr + 0;
               if (s0_size != 0) next_s0 = {s0_size - 1'b1, i_pop_data};
            end
            2'b01: begin
               pop_data = s1_val;
               child_addr = 4 * my_addr + 1;
               if (s1_size != 0) next_s1 = {s1_size - 1'b1, i_pop_data};
            end
            2'b10: begin
               pop_data = s2_val;
               child_addr = 4 * my_addr + 2;
               if (s2_size != 0) next_s2 = {s2_size - 1'b1, i_pop_data};
            end
            2'b11: begin
               pop_data = s3_val;
               child_addr = 4 * my_addr + 3;
               if (s3_size != 0) next_s3 = {s3_size - 1'b1, i_pop_data};
            end
         endcase
         wdata = {next_s3, next_s2, next_s1, next_s0};

      end else if (fsm == ST_PUSH) begin
         write = 1'b1;
         case (min_sub_tree)
            2'b00: begin
               child_addr = 4 * my_addr + 0;
               if (s0_prio != {PTW{1'b1}}) begin
                  push = 1'b1;
                  if (ipushd_latch[PTW-1:0] < s0_prio) begin
                     push_data = s0_val;
                     next_s0 = {s0_size + 1'b1, ipushd_latch};
                  end else begin
                     push_data = ipushd_latch;
                     next_s0 = {s0_size + 1'b1, s0_val};
                  end
               end else begin
                  next_s0 = {s0_size + 1'b1, ipushd_latch};
               end
            end
            2'b01: begin
               child_addr = 4 * my_addr + 1;
               if (s1_prio != {PTW{1'b1}}) begin
                  push = 1'b1;
                  if (ipushd_latch[PTW-1:0] < s1_prio) begin
                     push_data = s1_val;
                     next_s1 = {s1_size + 1'b1, ipushd_latch};
                  end else begin
                     push_data = ipushd_latch;
                     next_s1 = {s1_size + 1'b1, s1_val};
                  end
               end else begin
                  next_s1 = {s1_size + 1'b1, ipushd_latch};
               end
            end
            2'b10: begin
               child_addr = 4 * my_addr + 2;
               if (s2_prio != {PTW{1'b1}}) begin
                  push = 1'b1;
                  if (ipushd_latch[PTW-1:0] < s2_prio) begin
                     push_data = s2_val;
                     next_s2 = {s2_size + 1'b1, ipushd_latch};
                  end else begin
                     push_data = ipushd_latch;
                     next_s2 = {s2_size + 1'b1, s2_val};
                  end
               end else begin
                  next_s2 = {s2_size + 1'b1, ipushd_latch};
               end
            end
            2'b11: begin
               child_addr = 4 * my_addr + 3;
               if (s3_prio != {PTW{1'b1}}) begin
                  push = 1'b1;
                  if (ipushd_latch[PTW-1:0] < s3_prio) begin
                     push_data = s3_val;
                     next_s3 = {s3_size + 1'b1, ipushd_latch};
                  end else begin
                     push_data = ipushd_latch;
                     next_s3 = {s3_size + 1'b1, s3_val};
                  end
               end else begin
                  next_s3 = {s3_size + 1'b1, ipushd_latch};
               end
            end
         endcase
         wdata = {next_s3, next_s2, next_s1, next_s0};
      end
   end



   
//-----------------------------------------------------------------------------
// Continous Assignments
//-----------------------------------------------------------------------------
   assign read = (i_push | i_pop) & (fsm == ST_IDLE | fsm == ST_WB | fsm == ST_PUSH);
   
   
      
//-----------------------------------------------------------------------------
// Output Assignments
//-----------------------------------------------------------------------------
   assign o_read        = read;
   assign o_write       = write;
   assign o_write_data  = wdata;
   
   assign o_push        = push;
   assign o_push_data   = push_data;
   assign o_pop         = pop;
   
   assign o_pop_data    = pop_data;

   assign o_read_addr   = i_my_addr;
   assign o_write_addr  = my_addr;
   assign o_child_addr  = child_addr;
endmodule
