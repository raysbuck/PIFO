`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: PIFO_SRAM.v (GG Optimized Version)
Description: 2-cycle throughput PIFO with decoupled write-back and 
             data forwarding logic to eliminate ST_WB blocking.
-----------------------------------------------------------------------------*/

module PIFO_SRAM 
#(
   parameter PTW  = 16,  // DATA WIDTH
   parameter MTW  = 32,
   parameter CTW  = 10,  // COUNT WIDTH
   parameter ADW  = 20   // ADDRESS WDITH
)
(
   // Clock and Reset
   input                    i_clk,
   input                    i_arst_n,
  
   // From/To Parent 
   input                    i_push,
   input [(MTW+PTW)-1:0]    i_push_data,
   input                    i_pop,
   output [(MTW+PTW)-1:0]   o_pop_data,
   
   // From/To Child
   output                   o_push,
   output [(MTW+PTW)-1:0]   o_push_data,
   output                   o_pop,
   input [(MTW+PTW)-1:0]    i_pop_data,
   
   // From/To SRAM
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

//-----------------------------------------------------------------------------
// Registers
//-----------------------------------------------------------------------------
reg [1:0]             fsm;
reg [(MTW+PTW)-1:0]   ipushd_latch;
reg [ADW-1:0]         my_addr_reg;

// Write-back Pipeline Registers
reg                   wb_vld;
reg [ADW-1:0]         wb_addr;
reg [4*(CTW+MTW+PTW)-1:0] wb_data;

// POP specific Pipeline Registers
reg                   wb_is_pop;
reg [1:0]             wb_pop_port;
reg [4*(CTW+MTW+PTW)-1:0] wb_orig_read_data;

// Internal signals
wire [4*(CTW+MTW+PTW)-1:0] fwd_read_data;
reg  [1:0]             min_sub_tree;
reg  [1:0]             min_data_port;

//-----------------------------------------------------------------------------
// Forwarding Logic (Read-After-Write Hazard Mitigation)
//-----------------------------------------------------------------------------
assign fwd_read_data = (wb_vld && (i_my_addr == wb_addr)) ? wb_data : i_read_data;

//-----------------------------------------------------------------------------
// Main FSM
//-----------------------------------------------------------------------------
always @ (posedge i_clk or negedge i_arst_n) begin
    if (!i_arst_n) begin
        fsm          <= ST_IDLE;
        ipushd_latch <= 'd0;	
        my_addr_reg  <= 'd0;
    end else begin
        case (fsm)
            ST_IDLE, ST_PUSH, ST_POP: begin
                if (i_push && !i_pop) begin
                    fsm          <= ST_PUSH;
                    ipushd_latch <= i_push_data;
                    my_addr_reg  <= i_my_addr;
                end else if (i_pop && !i_push) begin
                    fsm          <= ST_POP;
                    my_addr_reg  <= i_my_addr;
                end else begin
                    fsm          <= ST_IDLE;
                end
            end
            default: fsm <= ST_IDLE;
        endcase
    end
end

//-----------------------------------------------------------------------------
// Combinatorial Logic & Write-back Pipeline
//-----------------------------------------------------------------------------
reg                   push_q;
reg [(MTW+PTW)-1:0]   push_data_q;
reg                   pop_q;
reg [(MTW+PTW)-1:0]   pop_data_q;
reg [ADW-1:0]         child_addr_q;

reg                   next_wb_vld;
reg [ADW-1:0]         next_wb_addr;
reg [4*(CTW+MTW+PTW)-1:0] next_wb_data;
reg                   next_wb_is_pop;
reg [1:0]             next_wb_pop_port;
reg [4*(CTW+MTW+PTW)-1:0] next_wb_orig_data;

always @ * begin
    // Defaults
    push_q          = 1'b0;
    push_data_q     = 'd0;
    pop_q           = 1'b0;
    pop_data_q      = 'd0;
    child_addr_q    = 'd0;
    
    next_wb_vld       = 1'b0;
    next_wb_addr      = wb_addr;
    next_wb_data      = wb_data;
    next_wb_is_pop    = 1'b0;
    next_wb_pop_port  = 2'b00;
    next_wb_orig_data = 'd0;

    // 1. Process Main Logic (Cycle 2)
    if (fsm == ST_PUSH) begin
        child_addr_q    = 4 * my_addr_reg + min_sub_tree;
        next_wb_vld     = 1'b1;
        next_wb_addr    = my_addr_reg;
        next_wb_is_pop  = 1'b0;
        
        case (min_sub_tree)
            2'b00: begin
                if (fwd_read_data[PTW-1:0] != {PTW{1'b1}}) begin
                    push_q      = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[PTW-1:0]) begin
                        push_data_q = fwd_read_data[(MTW+PTW)-1:0];
                        next_wb_data  = {fwd_read_data[4*(MTW+PTW+CTW)-1:(MTW+PTW+CTW)], fwd_read_data[(MTW+PTW+CTW)-1:(MTW+PTW)]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                    end else begin
                        push_data_q = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(MTW+PTW+CTW)-1:(MTW+PTW+CTW)], fwd_read_data[(MTW+PTW+CTW)-1:(MTW+PTW)]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[(MTW+PTW)-1:0]};
                    end
                end else begin
                    next_wb_data  = {fwd_read_data[4*(MTW+PTW+CTW)-1:(MTW+PTW+CTW)], fwd_read_data[(MTW+PTW+CTW)-1:(MTW+PTW)]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch};
                end
            end
            2'b01: begin
                if (fwd_read_data[2*PTW+(MTW+CTW)-1:(MTW+PTW+CTW)] != {PTW{1'b1}}) begin
                    push_q = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[2*PTW+MTW+CTW-1:(MTW+PTW+CTW)]) begin
                        push_data_q = fwd_read_data[(2*(MTW+PTW)+CTW)-1:(CTW+MTW+PTW)];
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:2*(CTW+MTW+PTW)], fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[(CTW+MTW+PTW)-1:0]};
                    end else begin
                        push_data_q = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:2*(CTW+MTW+PTW)], fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[2*(MTW+PTW)+CTW-1:0]};
                    end
                end else begin
                    next_wb_data = {fwd_read_data[4*(CTW+MTW+PTW)-1:2*(CTW+MTW+PTW)], fwd_read_data[2*(CTW+MTW+PTW)-1:2*(MTW+PTW)+CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[(CTW+MTW+PTW)-1:0]};
                end
            end
            2'b10: begin
                if (fwd_read_data[(3*PTW+2*(MTW+CTW))-1:2*(MTW+PTW+CTW)] != {PTW{1'b1}}) begin
                    push_q = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[(3*PTW+2*(MTW+CTW))-1:2*(MTW+PTW+CTW)]) begin
                        push_data_q = fwd_read_data[(3*(MTW+PTW)+2*CTW)-1:2*(CTW+MTW+PTW)];
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:3*(CTW+MTW+PTW)], fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[2*(CTW+MTW+PTW)-1:0]};
                    end else begin
                        push_data_q = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:3*(CTW+MTW+PTW)], fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[3*(MTW+PTW)+2*CTW-1:0]};
                    end
                end else begin
                    next_wb_data = {fwd_read_data[4*(CTW+MTW+PTW)-1:3*(CTW+MTW+PTW)], fwd_read_data[3*(CTW+MTW+PTW)-1:3*(MTW+PTW)+2*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[2*(CTW+MTW+PTW)-1:0]};
                end
            end
            2'b11: begin
                if (fwd_read_data[(4*PTW+3*(MTW+CTW))-1:3*(MTW+PTW+CTW)] != {PTW{1'b1}}) begin
                    push_q = 1'b1;
                    if (ipushd_latch[PTW-1:0] < fwd_read_data[(4*PTW+3*(MTW+CTW))-1:3*(MTW+PTW+CTW)]) begin
                        push_data_q = fwd_read_data[(4*(MTW+PTW)+3*CTW)-1:3*(CTW+MTW+PTW)];
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[3*(CTW+MTW+PTW)-1:0]};
                    end else begin
                        push_data_q = ipushd_latch;
                        next_wb_data  = {fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW]+{{(CTW-1){1'b0}},1'b1}, fwd_read_data[4*(MTW+PTW)+3*CTW-1:0]};
                    end
                end else begin
                    next_wb_data = {fwd_read_data[4*(CTW+MTW+PTW)-1:4*(MTW+PTW)+3*CTW]+{{(CTW-1){1'b0}},1'b1}, ipushd_latch, fwd_read_data[3*(CTW+MTW+PTW)-1:0]};
                end
            end
        endcase
    end else if (fsm == ST_POP) begin
        pop_q             = 1'b1;
        child_addr_q      = 4 * my_addr_reg + min_data_port;
        next_wb_vld       = 1'b1;
        next_wb_addr      = my_addr_reg;
        next_wb_is_pop    = 1'b1;
        next_wb_pop_port  = min_data_port;
        next_wb_orig_data = fwd_read_data;
        
        case (min_data_port)
            2'b00: pop_data_q = fwd_read_data[(MTW+PTW)-1:0];
            2'b01: pop_data_q = fwd_read_data[2*(MTW+PTW)+CTW-1:(CTW+MTW+PTW)];
            2'b10: pop_data_q = fwd_read_data[3*(MTW+PTW)+2*CTW-1:2*(CTW+MTW+PTW)];
            2'b11: pop_data_q = fwd_read_data[4*(MTW+PTW)+3*CTW-1:3*(CTW+MTW+PTW)];
        endcase
    end

    // 2. Resolve Pop Write-back when i_pop_data arrives (Cycle 3)
    if (wb_vld && wb_is_pop) begin
        next_wb_vld = 1'b0; 
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

// Sequential update of Write-back Pipeline
always @ (posedge i_clk or negedge i_arst_n) begin
    if (!i_arst_n) begin
        wb_vld            <= 1'b0;
        wb_addr           <= 'd0;
        wb_data           <= 'd0;
        wb_is_pop         <= 1'b0;
        wb_pop_port       <= 2'b00;
        wb_orig_read_data <= 'd0;
    end else begin
        wb_vld            <= next_wb_vld;
        wb_addr           <= next_wb_addr;
        wb_data           <= next_wb_data;
        wb_is_pop         <= next_wb_is_pop;
        wb_pop_port       <= next_wb_pop_port;
        wb_orig_read_data <= next_wb_orig_data;
    end
end

//-----------------------------------------------------------------------------
// Comparator Logic
//-----------------------------------------------------------------------------
always @ * begin
    // Min Sub-tree (for PUSH)
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

    // Min Data (for POP)
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
// Output Assignments
//-----------------------------------------------------------------------------
assign o_read        = (i_push | i_pop) && (fsm == ST_IDLE || fsm == ST_PUSH || fsm == ST_POP);
assign o_read_addr   = i_my_addr;

assign o_write       = (fsm == ST_PUSH) || (fsm == ST_POP && !wb_is_pop) || (wb_vld && wb_is_pop);
assign o_write_addr  = (wb_vld && wb_is_pop) ? wb_addr : my_addr_reg;
assign o_write_data  = next_wb_data;

assign o_push        = push_q;
assign o_push_data   = push_data_q;
assign o_pop         = pop_q;
assign o_pop_data    = pop_data_q;
assign o_child_addr  = child_addr_q;

endmodule
