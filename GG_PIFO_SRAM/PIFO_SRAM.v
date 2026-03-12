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

   // Bypass logic
   reg [4*(CTW+MTW+PTW)-1:0] last_wdata;
   reg [ADW-1:0]             last_write_addr;
   reg                       last_wvalid;
   wire [4*(CTW+MTW+PTW)-1:0] bypassed_read_data;

   assign bypassed_read_data = (last_wvalid && (i_my_addr == last_write_addr)) ? last_wdata : i_read_data;
   
   // Push to child
   reg                   push;
   reg [(MTW+PTW)-1:0]         push_data;
      
   reg                   pop;
   reg [(MTW+PTW)-1:0]         pop_data;   
	  
   reg [1:0]             min_sub_tree;
   reg [1:0]             min_data_port;
   
   reg [(MTW+PTW)-1:0]         ipushd_latch;

   // Internal Swap logic declarations
   localparam STW = PTW + MTW + CTW;
   wire [PTW-1:0] p0 = bypassed_read_data[PTW-1:0];
   wire [MTW-1:0] d0 = bypassed_read_data[MTW+PTW-1:PTW];
   wire [CTW-1:0] c0 = bypassed_read_data[STW-1:MTW+PTW];
   wire           s0 = (p0 != {PTW{1'b1}});

   wire [PTW-1:0] p1 = bypassed_read_data[STW+PTW-1:STW];
   wire [MTW-1:0] d1 = bypassed_read_data[STW+MTW+PTW-1:STW+PTW];
   wire [CTW-1:0] c1 = bypassed_read_data[2*STW-1:STW+MTW+PTW];
   wire           s1 = (p1 != {PTW{1'b1}});

   wire [PTW-1:0] p2 = bypassed_read_data[2*STW+PTW-1:2*STW];
   wire [MTW-1:0] d2 = bypassed_read_data[2*STW+MTW+PTW-1:2*STW+PTW];
   wire [CTW-1:0] c2 = bypassed_read_data[3*STW-1:2*STW+MTW+PTW];
   wire           s2 = (p2 != {PTW{1'b1}});

   wire [PTW-1:0] p3 = bypassed_read_data[3*STW+PTW-1:3*STW];
   wire [MTW-1:0] d3 = bypassed_read_data[3*STW+MTW+PTW-1:3*STW+PTW];
   wire [CTW-1:0] c3 = bypassed_read_data[4*STW-1:3*STW+MTW+PTW];
   wire           s3 = (p3 != {PTW{1'b1}});

   reg [1:0]             max_data_port;
   reg [PTW-1:0]         max_pri;
   reg [MTW+PTW-1:0]     max_val;

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
         last_wvalid  <= 1'b0;
         last_write_addr <= 'd0;
         last_wdata   <= 'd0;
      end else begin
         last_wvalid  <= write;
         last_write_addr <= my_addr;
         last_wdata   <= wdata;

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
                  default: begin 
                     fsm[1:0]    <= ST_WB;
                     ipushd_latch <= 'd0;	
					 my_addr      <= my_addr; 
				  end
			   endcase   
			end   

            ST_POP: begin
               case ({i_push, i_pop})
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
                  default: begin
  		            fsm[1:0]     <= ST_WB;
                    ipushd_latch <= 'd0;
			        my_addr      <= my_addr;
                  end
               endcase
            end		
            
			ST_WB: begin		       
  		       	case ({i_push, i_pop})
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
                  default: begin 
                     fsm[1:0]    <= ST_IDLE;
                     ipushd_latch <= 'd0;		
					 my_addr      <= 'd0; 
				  end
			   endcase
			end			
 	     endcase
      end	  
   end
   
//-----------------------------------------------------------------------------
// Combinatorial Logic / Continuous Assignments
//-----------------------------------------------------------------------------
   always @ *
   begin
      if (fsm == ST_POP) begin

		 //ADD BEGIN
    	 push      <= 1'd0;
		 push_data <= 'd0;
		 //ADD END

         case (min_data_port[1:0])
            2'b00: begin
 	           pop      <= 1'b1;
               pop_data <= {d0, p0};
		       write     <= 1'b1;
			   child_addr <= 4 * my_addr + 0;
		  	   if (c0 != 0) begin
                  wdata    <= {c3,d3,p3, c2,d2,p2, c1,d1,p1, c0-{{(CTW-1){1'b0}},1'b1}, i_pop_data};
			   end else begin
                  wdata    <= {c3,d3,p3, c2,d2,p2, c1,d1,p1, c0, d0, p0};
               end						   
            end
            2'b01: begin
               pop      <= 1'b1;
               pop_data <= {d1, p1};
	 	       write     <= 1'b1;
			   child_addr <= 4 * my_addr + 1;
			   if (c1 != 0) begin
                  wdata <= {c3,d3,p3, c2,d2,p2, c1-{{(CTW-1){1'b0}},1'b1}, i_pop_data, c0, d0, p0};
	  		   end else begin
                  wdata <= {c3,d3,p3, c2,d2,p2, c1, d1, p1, c0, d0, p0};
               end						   
            end
            2'b10: begin
	   	       pop      <= 1'b1;
               pop_data <= {d2, p2};
 	           write     <= 1'b1;
			   child_addr <= 4 * my_addr + 2;
			   if (c2 != 0) begin
                  wdata <= {c3,d3,p3, c2-{{(CTW-1){1'b0}},1'b1}, i_pop_data, c1, d1, p1, c0, d0, p0};
			   end else begin
                  wdata <= {c3,d3,p3, c2, d2, p2, c1, d1, p1, c0, d0, p0};
               end						   
            end
            2'b11: begin
	   	       pop      <= 1'b1;
               pop_data <= {d3, p3};
   		       write     <= 1'b1;
			   child_addr <= 4 * my_addr + 3;
			   if (c3 != 0) begin
                  wdata <= {c3-{{(CTW-1){1'b0}},1'b1}, i_pop_data, c2, d2, p2, c1, d1, p1, c0, d0, p0};
			   end else begin
                  wdata <= {c3, d3, p3, c2, d2, p2, c1, d1, p1, c0, d0, p0};
               end						   
            end		 
         endcase	  	
      end else if (fsm == ST_PUSH) begin

		 //ADD BEGIN
		 pop  <= 1'b0;                 
		 pop_data  <= -'d1;
		 //ADD END

	     case (min_sub_tree[1:0])
		    2'b00: begin // push 0
			   write     <= 1'b1;
			   child_addr <= 4 * my_addr;

			   if (p0 != {PTW{1'b1}}) begin
                  if (ipushd_latch[PTW-1:0] < max_pri) begin
                     push      <= 1'b1;
		             push_data <= max_val;
                     case (max_data_port)
                        2'b00: wdata <= {c3,d3,p3, c2,d2,p2, c1,d1,p1, c0+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                        2'b01: wdata <= {c3,d3,p3, c2,d2,p2, c1,d0,p0, c0+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                        2'b10: wdata <= {c3,d3,p3, c2,d0,p0, c1,d1,p1, c0+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                        2'b11: wdata <= {c3,d0,p0, c2,d2,p2, c1,d1,p1, c0+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                     endcase
				  end else begin
		             push_data <= ipushd_latch;
                     push      <= 1'b1;
				     wdata     <= {c3,d3,p3, c2,d2,p2, c1,d1,p1, c0+{{(CTW-1){1'b0}},1'b1}, d0,p0};
                  end						
			   end else begin
    		      push      <= 1'd0;
		          push_data <= 'd0;
 				  wdata     <= {c3,d3,p3, c2,d2,p2, c1,d1,p1, c0+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
			   end
			end

			2'b01: begin // push 1
			   write     <= 1'b1;
			   child_addr <= 4 * my_addr + 1;
			   if (p1 != {PTW{1'b1}}) begin
                  if (ipushd_latch[PTW-1:0] < max_pri) begin
    		         push      <= 1'b1;
 		             push_data <= max_val;
                     case (max_data_port)
                        2'b00: wdata <= {c3,d3,p3, c2,d2,p2, c1+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c0,d1,p1};
                        2'b01: wdata <= {c3,d3,p3, c2,d2,p2, c1+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c0,d0,p0};
                        2'b10: wdata <= {c3,d3,p3, c2,d1,p1, c1+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c0,d0,p0};
                        2'b11: wdata <= {c3,d1,p1, c2,d2,p2, c1+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c0,d0,p0};
                     endcase
				  end else begin
		             push_data <= ipushd_latch;
                     push      <= 1'b1;
					 wdata     <= {c3,d3,p3, c2,d2,p2, c1+{{(CTW-1){1'b0}},1'b1}, d1,p1, c0,d0,p0};
				  end
			   end else begin
    		      push      <= 1'd0;
		          push_data <= 'd0;
 				  wdata     <= {c3,d3,p3, c2,d2,p2, c1+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c0,d0,p0};
			   end
			end


			2'b10: begin // push 2
			   write     <= 1'b1;
			   child_addr <= 4 * my_addr + 2;
			   if (p2 != {PTW{1'b1}}) begin
                  if (ipushd_latch[PTW-1:0] < max_pri) begin
    		         push      <= 1'b1;
 		             push_data <= max_val;
                     case (max_data_port)
                        2'b00: wdata <= {c3,d3,p3, c2+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c1,d1,p1, c0,d2,p2};
                        2'b01: wdata <= {c3,d3,p3, c2+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c1,d2,p2, c0,d0,p0};
                        2'b10: wdata <= {c3,d3,p3, c2+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c1,d1,p1, c0,d0,p0};
                        2'b11: wdata <= {c3,d2,p2, c2+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c1,d1,p1, c0,d0,p0};
                     endcase
				  end else begin
 		             push_data <= ipushd_latch;
                     push      <= 1'b1;
  					 wdata     <= {c3,d3,p3, c2+{{(CTW-1){1'b0}},1'b1}, d2,p2, c1,d1,p1, c0,d0,p0};
                  end						
			   end else begin
    		      push      <= 1'd0;
		          push_data <= 'd0;
 				  wdata     <= {c3,d3,p3, c2+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c1,d1,p1, c0,d0,p0};
			   end
			end
			2'b11: begin // push 3
			   write     <= 1'b1;
			   child_addr <= 4 * my_addr + 3;
			   if (p3 != {PTW{1'b1}}) begin
                  if (ipushd_latch[PTW-1:0] < max_pri) begin
     		         push      <= 1'b1;
		             push_data <= max_val;
                     case (max_data_port)
                        2'b00: wdata <= {c3+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c2,d2,p2, c1,d1,p1, c0,d3,p3};
                        2'b01: wdata <= {c3+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c2,d2,p2, c1,d3,p3, c0,d0,p0};
                        2'b10: wdata <= {c3+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c2,d3,p3, c1,d1,p1, c0,d0,p0};
                        2'b11: wdata <= {c3+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c2,d2,p2, c1,d1,p1, c0,d0,p0};
                     endcase
				  end else begin
		             push_data <= ipushd_latch;
                     push      <= 1'b1;
					 wdata     <= {c3+{{(CTW-1){1'b0}},1'b1}, d3,p3, c2,d2,p2, c1,d1,p1, c0,d0,p0};
                  end						
			   end else begin
    		      push      <= 1'd0;
		          push_data <= 'd0;
  				  wdata     <= {c3+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, c2,d2,p2, c1,d1,p1, c0,d0,p0};
			   end
		    end
		 endcase		
      end else begin
    	 push      <= 1'd0;
		 push_data <= 'd0;
		 write     <= 1'b0;
  		 wdata     <= 'd0;         
		 pop       <= 1'b0;                 
		 pop_data  <= -'d1;
		 child_addr  <= -'d1;
      end	  
   end
   
   always @ *
   begin
  
   
      // Find the minimum sub-tree. 
      if (c0 <= c1 && c0 <= c2 && c0 <= c3) begin
	     min_sub_tree[1:0] = 2'b00;	  
      end else if (c1 <= c0 && c1 <= c2 && c1 <= c3) begin
	     min_sub_tree[1:0] = 2'b01;	  
      end else if (c2 <= c0 && c2 <= c1 && c2 <= c3) begin
	     min_sub_tree[1:0] = 2'b10;
      end else begin
	     min_sub_tree[1:0] = 2'b11;
      end		 
	  
      // Find the minimum data and minimum data port.
      if (p0 <= p1 && p0 <= p2 && p0 <= p3) begin
		 min_data_port[1:0]   = 2'b00;
      end else if (p1 <= p0 && p1 <= p2 && p1 <= p3) begin
		 min_data_port[1:0]   = 2'b01;
 	  end else if (p2 <= p0 && p2 <= p1 && p2 <= p3) begin
		 min_data_port[1:0]   = 2'b10;
 	  end else begin
		 min_data_port[1:0]   = 2'b11;
      end

      // Find the maximum data port.
      if (p0 >= p1 && p0 >= p2 && p0 >= p3) begin
         max_data_port = 2'b00;
         max_pri = p0;
         max_val = {d0, p0};
      end else if (p1 >= p0 && p1 >= p2 && p1 >= p3) begin
         max_data_port = 2'b01;
         max_pri = p1;
         max_val = {d1, p1};
      end else if (p2 >= p0 && p2 >= p1 && p2 >= p3) begin
         max_data_port = 2'b10;
         max_pri = p2;
         max_val = {d2, p2};
      end else begin
         max_data_port = 2'b11;
         max_pri = p3;
         max_val = {d3, p3};
      end
   end


   
//-----------------------------------------------------------------------------
// Continous Assignments
//-----------------------------------------------------------------------------
   assign read = (i_push | i_pop);
   
   
      
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
