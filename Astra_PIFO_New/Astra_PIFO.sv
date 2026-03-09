`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Astra_PIFO.sv
Description: Register-based Astra-PIFO (Full Flip-Flop Tree).
             Uses high-speed L0 root with immediate refill to achieve 
             1-cycle throughput.
-----------------------------------------------------------------------------*/

module Astra_PIFO #(
    parameter PTW   = 16,
    parameter MTW   = 32,
    parameter CTW   = 10,
    parameter LEVEL = 4  // Total tree levels
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // User Interface
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_ready
);

    // Internal wires connecting L0 to the rest of the FF tree
    wire [3:0]             b_push;
    wire [(MTW+PTW)-1:0]    b_push_data;
    wire [3:0]             b_pop;
    wire [4*(MTW+PTW)-1:0]  b_pop_data;
    wire [3:0]             b_valid;

    // 1. High-speed Root Node (L0)
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

    // 2. Register-based Backend (Sub-trees)
    // Here we use the previously defined Backend_Reg which instantiates Zenith nodes
    Astra_Backend_Reg #(
        .PTW(PTW), .MTW(MTW), .CTW(CTW), .DEPTH(LEVEL-1)
    ) u_backend (
        .i_clk(i_clk),
        .i_arst_n(i_arst_n),
        .i_push(b_push),
        .i_push_data(b_push_data),
        .i_pop(b_pop),
        .o_pop_data(b_pop_data),
        .o_valid(b_valid)
    );

endmodule
