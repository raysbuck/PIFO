`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Turbo_TOP.sv
Description: Extreme Throughput PIFO Top-level.
             Interleaves 2 BMW pipelines with Hybrid (Reg/SRAM) storage.
-----------------------------------------------------------------------------*/

module Turbo_TOP #(
    parameter PTW = 16,
    parameter MTW = 32,
    parameter ADW = 16
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,

    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_valid
);

    // 1. Dispatcher
    wire p0_push, p1_push, p0_pop, p1_pop;
    wire [(MTW+PTW)-1:0] p0_push_data, p1_push_data;

    Turbo_Dispatcher #(.DW(MTW+PTW)) u_dispatcher (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_push(i_push),
        .i_push_data(i_push_data),
        .i_pop(i_pop),
        .o_p0_push(p0_push),
        .o_p0_data(p0_push_data),
        .o_p0_pop(p0_pop),
        .o_p1_push(p1_push),
        .o_p1_data(p1_push_data),
        .o_p1_pop(p1_pop)
    );

    // 2. Pipeline 0 (Root=Reg, Level 1=SRAM)
    wire [(MTW+PTW)-1:0] p0_res_data;
    wire p0_res_valid;

    Turbo_Engine #(.IS_ROOT(1), .PTW(PTW), .MTW(MTW)) u_p0_l0 (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_valid(p0_push || p0_pop),
        .i_op_type(p0_pop),
        .i_data(p0_push_data),
        .i_node_addr({ADW{1'b0}}),
        .o_res_data(p0_res_data),
        .o_res_valid(p0_res_valid)
        // Level 1 connections would go here
    );

    // 3. Pipeline 1 (Root=Reg, Level 1=SRAM)
    wire [(MTW+PTW)-1:0] p1_res_data;
    wire p1_res_valid;

    Turbo_Engine #(.IS_ROOT(1), .PTW(PTW), .MTW(MTW)) u_p1_l0 (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_valid(p1_push || p1_pop),
        .i_op_type(p1_pop),
        .i_data(p1_push_data),
        .i_node_addr({ADW{1'b0}}),
        .o_res_data(p1_res_data),
        .o_res_valid(p1_res_valid)
    );

    // 4. Final Output Arbitration (Compare result from both pipelines)
    // For extreme performance, this can be a single cycle comparator
    assign o_valid    = p0_res_valid || p1_res_valid;
    assign o_pop_data = (p0_res_valid && p1_res_valid) ? 
                        ((p0_res_data[PTW-1:0] < p1_res_data[PTW-1:0]) ? p0_res_data : p1_res_data) :
                        (p0_res_valid ? p0_res_data : p1_res_data);

endmodule
