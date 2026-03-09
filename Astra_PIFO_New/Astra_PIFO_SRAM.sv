`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Astra_PIFO_SRAM.sv
Description: SRAM-based Astra-PIFO.
             Uses L0 Flip-Flops to hide the latency of the SRAM body.
             Ideal for massive flow counts (e.g., 64K flows).
-----------------------------------------------------------------------------*/

module Astra_PIFO_SRAM #(
    parameter PTW = 16,
    parameter MTW = 32,
    parameter CTW = 10,
    parameter ADW = 15  // Address width for large SRAM
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // User Interface (1-cycle throughput)
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_ready
);

    wire [3:0]             b_push;
    wire [(MTW+PTW)-1:0]    b_push_data;
    wire [3:0]             b_pop;
    wire [4*(MTW+PTW)-1:0]  b_pop_data;
    wire [3:0]             b_valid;

    // 1. High-speed Root Node (L0) - Shared with Register version
    Astra_Node_L0 #(
        .PTW(PTW), .MTW(MTW), .CTW(CTW)
    ) u_root (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_push(i_push),
        .i_push_data(i_push_data),
        .i_pop(i_pop),
        .o_pop_data(o_pop_data),
        .o_ready(o_ready),
        .o_b_push(b_push),
        .o_b_push_data(b_push_data),
        .o_b_pop(b_pop),
        .i_b_pop_data(b_pop_data),
        .i_b_valid(b_valid)
    );

    // 2. SRAM-based Backend
    // This maps the 4 sub-tree requests to an SRAM structure.
    Astra_Backend_SRAM #(
        .PTW(PTW), .MTW(MTW), .CTW(CTW), .ADW(ADW)
    ) u_backend_sram (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_push(b_push),
        .i_push_data(b_push_data),
        .i_pop(b_pop),
        .o_pop_data(b_pop_data),
        .o_valid(b_valid)
    );

endmodule
