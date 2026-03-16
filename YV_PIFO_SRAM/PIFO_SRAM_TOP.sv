`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------

Proprietary and Confidential Information

Module: PIFO_SRAM_TOP.v
Author: Xiaoguang Li
Date  : 06/16/2019

Description: Top-level module that contains n levels (n is parameterizable) 
             of PIFO components.
			 
-----------------------------------------------------------------------------*/

//-----------------------------------------------------------------------------
// Module Port Definition
//-----------------------------------------------------------------------------
module PIFO_SRAM_TOP
#(
   parameter PTW = 16,  // Payload data width
   parameter MTW    = 32,  // METADATA
   parameter CTW = 10,  // Sub-tree width
   parameter ADW  = 20, // ADDRESS WDITH
   parameter LEVEL  = 8 // Sub-tree level
)(
   // Clock and Reset
   input               i_clk,
   input               i_arst_n,
   
   // Push and Pop port to the whole PIFO tree
   input               i_push,
   input [(MTW+PTW)-1:0]     i_push_data,
   
   input               i_pop,
   output [(MTW+PTW)-1:0]    o_pop_data      
);

//-----------------------------------------------------------------------------
// Functions
//-----------------------------------------------------------------------------

function integer addr_idx_high;
input integer pifo_level;
integer i,j,k;
begin
   j=0;
   k=0;
   for (i=0;i<pifo_level;i=i+1) begin
      if (i==0) begin
         k=0;
	   end else begin
	     k=$clog2(4**i);
	   end
	   j=j+k;
   end
   addr_idx_high = j;
end
endfunction

function integer addr_idx_low;
input integer pifo_level;
integer i,j,k;
begin
   j=0;
   k=0;
   for (i=0;i<pifo_level;i=i+1) begin
      if (i==0) begin
         k=0;
	  end else begin
	     k=$clog2(4**(i-1));
	  end
	  j=j+k;
   end
   if (pifo_level == 1) begin
      addr_idx_low = 0;
   end else begin
      addr_idx_low = j+1;
   end
end
endfunction

//-----------------------------------------------------------------------------
// Parameters
//-----------------------------------------------------------------------------
localparam EW = CTW + MTW + PTW + 2;

//-----------------------------------------------------------------------------
// Register and Wire Declarations
//-----------------------------------------------------------------------------

   wire [LEVEL-1:0]    push_up;
   wire [(MTW+PTW)-1:0]                push_data_up [0:LEVEL-1];
   wire [LEVEL-1:0]    pop_up;
   wire [(MTW+PTW)+2-1:0]              pop_data_up  [0:LEVEL-1];
   wire                          push_dn      [0:LEVEL-1];
   wire [(MTW+PTW)-1:0]                push_data_dn [0:LEVEL-1];
   wire                          pop_dn       [0:LEVEL-1];
   wire [(MTW+PTW)+2-1:0]              pop_data_dn  [0:LEVEL-1];
   
   wire [LEVEL - 1:0]            read_1, read_2;
   wire [LEVEL - 1:0]            write_1, write_2;
   wire [4*EW-1:0]               read_data_1 [0:LEVEL - 1];
   wire [4*EW-1:0]               read_data_2 [0:LEVEL - 1];
   wire [4*EW-1:0]               write_data_1 [0:LEVEL - 1];
   wire [4*EW-1:0]               write_data_2 [0:LEVEL - 1];   

   wire [ADW-1:0]                read_addr_1 [0:LEVEL-1];
   wire [ADW-1:0]                read_addr_2 [0:LEVEL-1];
   wire [ADW-1:0]                write_addr_1 [0:LEVEL-1];
   wire [ADW-1:0]                write_addr_2 [0:LEVEL-1];
   
   wire [ADW-1:0]                my_addr    [0:LEVEL-1];
   wire [ADW-1:0]                child_addr   [0:LEVEL-1];

   // Flattened address signals for SDPRAM instances
   wire [addr_idx_high(LEVEL):0] waddr_1, waddr_2, raddr_1, raddr_2;

//-----------------------------------------------------------------------------
// Instantiations
//-----------------------------------------------------------------------------
genvar i;
generate
   for (i=0;i<LEVEL;i=i+1) begin : pifo_loop
         PIFO_SRAM #(
		    .PTW (PTW),
          .MTW (MTW),
			.CTW (CTW),
         .ADW (ADW)
		 ) u_PIFO (
            .i_clk           ( i_clk                        ),
            .i_arst_n        ( i_arst_n                     ),

            .i_push          ( push_up      [i] ),
            .i_push_data     ( push_data_up [i] ),
            .i_pop           ( pop_up       [i] ),
            .o_pop_data      ( pop_data_up  [i] ),

            .o_push          ( push_dn      [i] ),
            .o_push_data     ( push_data_dn [i] ),
            .o_pop           ( pop_dn       [i] ),
            .i_pop_data      ( pop_data_dn  [i] ),
			
            .o_read_1        ( read_1       [i] ), 
            .i_read_data_1   ( read_data_1  [i] ), 
            .o_write_1       ( write_1      [i] ), 
            .o_write_data_1  ( write_data_1 [i] ),
            .o_read_addr_1   ( read_addr_1  [i] ),
            .o_write_addr_1  ( write_addr_1 [i] ),

            .o_read_2        ( read_2       [i] ), 
            .i_read_data_2   ( read_data_2  [i] ), 
            .o_write_2       ( write_2      [i] ), 
            .o_write_data_2  ( write_data_2 [i] ),
            .o_read_addr_2   ( read_addr_2  [i] ),
            .o_write_addr_2  ( write_addr_2 [i] ),

            .i_my_addr       ( my_addr      [i] ),
            .o_child_addr    ( child_addr   [i] )
         );
   end
   
   assign push_up[0]            = i_push;
   assign push_data_up[0]       = i_push_data;
   assign pop_up[0]             = i_pop;
   assign o_pop_data            = pop_data_up[0][(MTW+PTW)+2-1:2]; // Strip source port for top output
   assign my_addr[0]            = 1'b0;

   for (i=1;i<LEVEL;i=i+1) begin : loop1
      assign push_up[i]            = push_dn[i-1];
      assign push_data_up[i]       = push_data_dn[i-1];
      assign pop_up[i]             = pop_dn[i-1];
      assign pop_data_dn[i-1]      = pop_data_up[i];
      assign my_addr[i]            = child_addr[i - 1];
   end   
   assign pop_data_dn[LEVEL - 1] = {((MTW+PTW)+2){1'b1}};

   // --- SRAM 1 Instantiations ---
   for (i=0; i<LEVEL; i=i+1) begin : sram1_inst
      INFER_SDPRAM #( 
	      .DATA_WIDTH ( 4*EW                             ), 
         .ADDR_WIDTH ( (i==0) ? 2 : 2 * i               ), 
         .ARCH       ( 0                                ), 
         .RDW_MODE   ( 1                                ),
         .INIT_VALUE ( {4{{CTW{1'b0}},{(MTW+PTW){1'b1}},2'b00}} )
	  ) u_SDPRAM1
	  (
         .i_clk      ( i_clk                                   ),     
         .i_arst_n   ( i_arst_n                                ),  
         .i_we       ( write_1[i]                              ), 
         .i_waddr    ( write_addr_1[i][((i==0)?2:2*i)-1:0]     ), 
         .i_wdata    ( write_data_1[i]                         ), 
         .i_re       ( read_1[i]                               ),                                        
         .i_raddr    ( read_addr_1[i][((i==0)?2:2*i)-1:0]      ),    
         .o_rdata    ( read_data_1[i]                          ) 
      );  
   end

   // --- SRAM 2 Instantiations ---
   for (i=0; i<LEVEL; i=i+1) begin : sram2_inst
      INFER_SDPRAM #( 
	      .DATA_WIDTH ( 4*EW                             ), 
         .ADDR_WIDTH ( (i==0) ? 2 : 2 * i               ), 
         .ARCH       ( 0                                ), 
         .RDW_MODE   ( 1                                ),
         .INIT_VALUE ( {4{{CTW{1'b0}},{(MTW+PTW){1'b1}},2'b00}} )
	  ) u_SDPRAM2
	  (
         .i_clk      ( i_clk                                   ),     
         .i_arst_n   ( i_arst_n                                ),  
         .i_we       ( write_2[i]                              ), 
         .i_waddr    ( write_addr_2[i][((i==0)?2:2*i)-1:0]     ), 
         .i_wdata    ( write_data_2[i]                         ), 
         .i_re       ( read_2[i]                               ),                                        
         .i_raddr    ( read_addr_2[i][((i==0)?2:2*i)-1:0]      ),    
         .o_rdata    ( read_data_2[i]                          ) 
      );  
   end

endgenerate

endmodule
