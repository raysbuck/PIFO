`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: PIFO_SRAM.v
Description: Optimized 2-cycle throughput PIFO with independent write-back 
             and data forwarding logic.
-----------------------------------------------------------------------------*/

module PIFO_SRAM 
#(
   parameter PTW  = 16,  // DATA WIDTH
   parameter MTW  = 32,
   parameter CTW  = 10,  // COUNT WIDTH
   parameter ADW  = 20   // ADDRESS WDITH
)
(
   input                    i_clk,
   input                    i_arst_n,
  
   input                    i_push,
   input [(MTW+PTW)-1:0]    i_push_data,
   input                    i_pop,
   output [(MTW+PTW)-1:0]   o_pop_data,
   
   output                   o_push,
   output [(MTW+PTW)-1:0]   o_push_data,
   output                   o_pop,
   input [(MTW+PTW)-1:0]    i_pop_data,
   
   output                   o_read,
   input [4*(CTW+MTW+PTW)-1:0]  i_read_data,
   
   output                   o_write,
   output [4*(CTW+MTW+PTW)-1:0] o_write_data,

   input  [ADW-1:0]         i_my_addr,
   output  [ADW-1:0]        o_child_addr,
   output  [ADW-1:0]        o_read_addr,
   output  [ADW-1:0]        o_write_addr
);

//-----------------------------------------------------------------------------
// Parameters & States
//-----------------------------------------------------------------------------
localparam ST_IDLE = 2'b00,
           ST_PUSH = 2'b01,
           ST_POP  = 2'b11; 
           // ST_WB is removed from the main flow to achieve 2-cycle throughput

//-----------------------------------------------------------------------------
// Registers
//-----------------------------------------------------------------------------
reg [1:0]             fsm;
reg [(MTW+PTW)-1:0]   ipushd_latch;
reg [ADW-1:0]         my_addr;
reg [ADW-1:0]         child_addr_reg;

// Write-back Pipeline Registers (Independent Write Logic)
reg                   wb_vld;
reg [ADW-1:0]         wb_addr;
reg [4*(CTW+MTW+PTW)-1:0] wb_data;

// For POP operations, we need to store metadata to compute final wdata when i_pop_data arrives
reg                   wb_is_pop;
reg [1:0]             wb_pop_port;
reg [4*(CTW+MTW+PTW)-1:0] wb_orig_read_data;

// Internal signals for comparison
wire [4*(CTW+MTW+PTW)-1:0] fwd_read_data;
reg  [1:0]             min_sub_tree;
reg  [1:0]             min_data_port;

//-----------------------------------------------------------------------------
// Forwarding / Bypass Logic
//-----------------------------------------------------------------------------
// If the next operation reads the same address currently in the write-back pipe, 
// forward the pending write data.
assign fwd_read_data = (wb_vld && (i_my_addr == wb_addr)) ? wb_data : i_read_data;

//-----------------------------------------------------------------------------
// FSM Sequential Logic
//-----------------------------------------------------------------------------
always @ (posedge i_clk or negedge i_arst_n) begin
    if (!i_arst_n) begin
        fsm          <= ST_IDLE;
        ipushd_latch <= 'd0;	
        my_addr      <= 'd0;
    end else begin
        case (fsm)
            ST_IDLE: begin
                if (i_push && !i_pop) begin
                    fsm          <= ST_PUSH;
                    ipushd_latch <= i_push_data;
                    my_addr      <= i_my_addr;
                end else if (i_pop && !i_push) begin
                    fsm          <= ST_POP;
                    my_addr      <= i_my_addr;
                end
            end
            ST_PUSH, ST_POP: begin
                // Return to IDLE or handle next command immediately (2-cycle throughput)
                if (i_push && !i_pop) begin
                    fsm          <= ST_PUSH;
                    ipushd_latch <= i_push_data;
                    my_addr      <= i_my_addr;
                end else if (i_pop && !i_push) begin
                    fsm          <= ST_POP;
                    my_addr      <= i_my_addr;
                end else begin
                    fsm          <= ST_IDLE;
                end
            end
            default: fsm <= ST_IDLE;
        endcase
    end
end

//-----------------------------------------------------------------------------
// Independent Write-back Pipeline Logic
//-----------------------------------------------------------------------------
reg                   next_wb_vld;
reg [ADW-1:0]         next_wb_addr;
reg [4*(CTW+MTW+PTW)-1:0] next_wb_data;
reg                   next_wb_is_pop;
reg [1:0]             next_wb_pop_port;
reg [4*(CTW+MTW+PTW)-1:0] next_wb_orig_data;

always @ (posedge i_clk or negedge i_arst_n) begin
    if (!i_arst_n) begin
        wb_vld            <= 1'b0;
        wb_addr           <= 'd0;
        wb_data           <= 'd0;
        wb_is_pop         <= 1'b0;
        wb_pop_port       <= 2'b00;
        wb_orig_read_data <= 'd0;
    end else begin
        // If we are currently handling a POP WB that was waiting for i_pop_data,
        // it completes now. New WB requests from FSM take priority.
        wb_vld            <= next_wb_vld;
        wb_addr           <= next_wb_addr;
        wb_data           <= next_wb_data;
        wb_is_pop         <= next_wb_is_pop;
        wb_pop_port       <= next_wb_pop_port;
        wb_orig_read_data <= next_wb_orig_data;
    end
end

//-----------------------------------------------------------------------------
// Combinatorial Logic for Request & Write-back Generation
//-----------------------------------------------------------------------------
reg                   push_out;
reg [(MTW+PTW)-1:0]   push_data_out;
reg                   pop_out;
reg [(MTW+PTW)-1:0]   pop_data_out;
reg [ADW-1:0]         child_addr_next;

always @ * begin
    // Defaults
    push_out        = 1'b0;
    push_data_out   = 'd0;
    pop_out         = 1'b0;
    pop_data_out    = 'd0;
    child_addr_next = 'd0;
    
    next_wb_vld       = 1'b0;
    next_wb_addr      = wb_addr;
    next_wb_data      = wb_data;
    next_wb_is_pop    = 1'b0;
    next_wb_pop_port  = 2'b00;
    next_wb_orig_data = 'd0;

    // 1. Process Main FSM Commands (Cycle 2)
    if (fsm == ST_PUSH) begin
        child_addr_next = 4 * my_addr + min_sub_tree;
        next_wb_vld     = 1'b1;
        next_wb_addr    = my_addr;
        next_wb_is_pop  = 1'b0;
        
        case (min_sub_tree)
            2'b00: begin
                if (fwd_read_data[PTW-1:0] != {PTW{1'b1}}) begin
                    push_out      = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[PTW-1:0]) begin
                        push_data_out = fwd_read_data[(MTW+PTW)-1:0];
                        next_wb_data  = {fwd_read_data[4*(MTW+PTW+CTW)-1:(MTW+PTW+CTW)], fwd_read_data[(MTW+PTW+CTW)-1:(MTW+PTW)]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                    end else begin
                        push_data_out = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(MTW+PTW+CTW)-1:(MTW+PTW+CTW)], fwd_read_data[(MTW+PTW+CTW)-1:(MTW+PTW)]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[(MTW+PTW)-1:0]};
                    end
                end else begin
                    next_wb_data  = {fwd_read_data[4*(MTW+PTW+CTW)-1:(MTW+PTW+CTW)], fwd_read_data[(MTW+PTW+CTW)-1:(MTW+PTW)]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                end
            end
            2'b01: begin
                if (fwd_read_data[2*PTW+(MTW+CTW)-1:(MTW+PTW+CTW)] != {PTW{1'b1}}) begin
                    push_out = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[2*PTW+MTW+CTW-1:(MTW+PTW+CTW)]) begin
                        push_data_out = fwd_read_data[(2*(MTW+PTW)+CTW)-1:(CTW+MTW+PTW)];
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:2*(CTW+MTW+PTW)], fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[(CTW+MTW+PTW)-1:0]};
                    end else begin
                        push_data_out = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:2*(CTW+MTW+PTW)], fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[2*(MTW+PTW)+CTW-1:0]};
                    end
                end else begin
                    next_wb_data = {fwd_read_data[4*(CTW+MTW+PTW)-1:2*(CTW+MTW+PTW)], fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[(CTW+MTW+PTW)-1:0]};
                end
            end
            2'b10: begin
                if (fwd_read_data[(3*PTW+2*(MTW+CTW))-1:2*(MTW+PTW+CTW)] != {PTW{1'b1}}) begin
                    push_out = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[(3*PTW+2*(MTW+CTW))-1:2*(MTW+PTW+CTW)]) begin
                        push_data_out = fwd_read_data[(3*(MTW+PTW)+2*CTW)-1:2*(CTW+MTW+PTW)];
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:3*(CTW+MTW+PTW)], fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[2*(CTW+MTW+PTW)-1:0]};
                    end else begin
                        push_data_out = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:3*(CTW+MTW+PTW)], fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[3*(MTW+PTW)+2*CTW-1:0]};
                    end
                end else begin
                    next_wb_data = {fwd_read_data[4*(CTW+MTW+PTW)-1:3*(CTW+MTW+PTW)], fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[2*(CTW+MTW+PTW)-1:0]};
                end
            end
            2'b11: begin
                if (fwd_read_data[(4*PTW+3*(MTW+CTW))-1:3*(MTW+PTW+CTW)] != {PTW{1'b1}}) begin
                    push_out = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[(4*PTW+3*(MTW+CTW))-1:3*(MTW+PTW+CTW)]) begin
                        push_data_out = fwd_read_data[(4*(MTW+PTW)+3*CTW)-1:3*(CTW+MTW+PTW)];
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[3*(CTW+MTW+PTW)-1:0]};
                    end else begin
                        push_data_out = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[4*(MTW+PTW)+3*CTW-1:0]};
                    end
                end else begin
                    next_wb_data = {fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[3*(CTW+MTW+PTW)-1:0]};
                end
            end
        endcase
    end else if (fsm == ST_POP) begin
        pop_out           = 1'b1;
        child_addr_next   = 4 * my_addr + min_data_port;
        next_wb_vld       = 1'b1;
        next_wb_addr      = my_addr;
        next_wb_is_pop    = 1'b1;
        next_wb_pop_port  = min_data_port;
        next_wb_orig_data = fwd_read_data; // Store to construct final data when i_pop_data arrives
        
        case (min_data_port)
            2'b00: pop_data_out = fwd_read_data[(MTW+PTW)-1:0];
            2'b01: pop_data_out = fwd_read_data[2*(MTW+PTW)+CTW-1:(CTW+MTW+PTW)];
            2'b10: pop_data_out = fwd_read_data[3*(MTW+PTW)+2*CTW-1:2*(CTW+MTW+PTW)];
            2'b11: pop_data_out = fwd_read_data[4*(MTW+PTW)+3*CTW-1:3*(CTW+MTW+PTW)];
        endcase
    end

    // 2. Background Write-back Finalization (Handling Cycle 3 for POP)
    // If the current wb_pipe is a POP, we combine the saved data with current i_pop_data
    if (wb_vld && wb_is_pop) begin
        next_wb_vld = 1'b0; // This WB is now being committed to SRAM
        case (wb_pop_port)
            2'b00: begin
                if (wb_orig_read_data[(MTW+PTW+CTW)-1:(MTW+PTW)] != 0)
                    next_wb_data = {wb_orig_read_data[4*(CTW+MTW+PTW)-1:(CTW+MTW+PTW)], wb_orig_read_data[(CTW+MTW+PTW)-1:(MTW+PTW)]-{{(CTW-1){1'b0}},1'b1}, i_pop_data};
                else
                    next_wb_data = wb_orig_read_data;
            end
            2'b01: begin
                if (wb_orig_read_data[2*(MTW+PTW+CTW)-1:2*(MTW+PTW)+CTW] != 0)
                    next_wb_data = {wb_orig_read_data[4*(CTW+MTW+PTW)-1:2*(CTW+MTW+PTW)], wb_orig_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW]-{{(CTW-1){1'b0}},1'b1}, i_pop_data, wb_orig_read_data[(MTW+PTW+CTW)-1:0]};
                else
                    next_wb_data = wb_orig_read_data;
            end
            2'b10: begin
                if (wb_orig_read_data[3*(MTW+PTW+CTW)-1:3*(MTW+PTW)+2*CTW] != 0)
                    next_wb_data = {wb_orig_read_data[4*(CTW+MTW+PTW)-1:3*(CTW+MTW+PTW)], wb_orig_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW]-{{(CTW-1){1'b0}},1'b1}, i_pop_data, wb_orig_read_data[2*(MTW+PTW+CTW)-1:0]};
                else
                    next_wb_data = wb_orig_read_data;
            end
            2'b11: begin
                if (wb_orig_read_data[4*(MTW+PTW+CTW)-1:4*(MTW+PTW)+3*CTW] != 0)
                    next_wb_data = {wb_orig_read_data[4*(MTW+PTW+CTW)-1:4*(MTW+PTW)+3*CTW]-{{(CTW-1){1'b0}},1'b1}, i_pop_data, wb_orig_read_data[3*(MTW+PTW+CTW)-1:0]};
                else
                    next_wb_data = wb_orig_read_data;
            end
        endcase
    end
end

//-----------------------------------------------------------------------------
// Priority Comparison Logic (Using Forwarded Data)
//-----------------------------------------------------------------------------
always @ * begin
    // Find the minimum sub-tree (for PUSH)
    if (fwd_read_data[(CTW+MTW+PTW)-1:(MTW+PTW)] <= fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW] &&
        fwd_read_data[(CTW+MTW+PTW)-1:(MTW+PTW)] <= fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW] &&
        fwd_read_data[(CTW+MTW+PTW)-1:(MTW+PTW)] <= fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW])
        min_sub_tree = 2'b00;
    else if (fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW] <= fwd_read_data[(CTW+MTW+PTW)-1:(MTW+PTW)] &&
        fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW] <= fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW] &&
        fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW] <= fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW])
        min_sub_tree = 2'b01;
    else if (fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW] <= fwd_read_data[(CTW+MTW+PTW)-1:(MTW+PTW)] &&
        fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW] <= fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW] &&
        fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW] <= fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW])
        min_sub_tree = 2'b10;
    else
        min_sub_tree = 2'b11;

    // Find the minimum data port (for POP)
    if (fwd_read_data[PTW-1:0] <= fwd_read_data[2*PTW+(CTW+MTW)-1:(CTW+MTW+PTW)] &&
        fwd_read_data[PTW-1:0] <= fwd_read_data[3*PTW+2*(CTW+MTW)-1:2*(CTW+MTW+PTW)] &&
        fwd_read_data[PTW-1:0] <= fwd_read_data[4*PTW+3*(CTW+MTW)-1:3*(CTW+MTW+PTW)])
        min_data_port = 2'b00;
    else if (fwd_read_data[2*PTW+(CTW+MTW)-1:(CTW+MTW+PTW)] <= fwd_read_data[PTW-1:0] &&
        fwd_read_data[2*PTW+(CTW+MTW)-1:(CTW+MTW+PTW)] <= fwd_read_data[3*PTW+2*(CTW+MTW)-1:2*(CTW+MTW+PTW)] &&
        fwd_read_data[2*PTW+(CTW+MTW)-1:(CTW+MTW+PTW)] <= fwd_read_data[4*PTW+3*(CTW+MTW)-1:3*(CTW+MTW+PTW)])
        min_data_port = 2'b01;
    else if (fwd_read_data[3*PTW+2*(CTW+MTW)-1:2*(CTW+MTW+PTW)] <= fwd_read_data[PTW-1:0] &&
        fwd_read_data[3*PTW+2*(CTW+MTW)-1:2*(CTW+MTW+PTW)] <= fwd_read_data[2*PTW+(CTW+MTW)-1:(CTW+MTW+PTW)] &&
        fwd_read_data[3*PTW+2*(CTW+MTW)-1:2*(CTW+MTW+PTW)] <= fwd_read_data[4*PTW+3*(CTW+MTW)-1:3*(CTW+MTW+PTW)])
        min_data_port = 2'b10;
    else
        min_data_port = 2'b11;
end

//-----------------------------------------------------------------------------
// Outputs
//-----------------------------------------------------------------------------
assign o_read       = (i_push | i_pop) && (fsm == ST_IDLE || fsm == ST_PUSH || fsm == ST_POP);
assign o_read_addr  = i_my_addr;

// SRAM Write happens 1 cycle after ST_PUSH or ST_POP (or when POP WB is finalized)
assign o_write      = (fsm == ST_PUSH) || (fsm == ST_POP && !wb_is_pop) || (wb_vld && wb_is_pop);
assign o_write_addr = (wb_vld && wb_is_pop) ? wb_addr : my_addr;
assign o_write_data = next_wb_data;

assign o_push       = push_out;
assign o_push_data  = push_data_out;
assign o_pop        = pop_out;
assign o_pop_data   = pop_data_out;
assign o_child_addr = child_addr_next;

endmodule
