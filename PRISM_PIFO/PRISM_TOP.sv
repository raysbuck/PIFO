`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: PRISM_TOP.sv
Description: Top-level for PRISM-PIFO. 
             Demonstrates logic folding and implicit heap-based indexing.
-----------------------------------------------------------------------------*/

module PRISM_TOP #(
    parameter PTW = 16,
    parameter MTW = 32,
    parameter CTW = 10,
    parameter ADW = 20,
    parameter LEVEL = 8
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,

    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_valid
);

    // Pipeline signals between levels
    wire [LEVEL:0] vld_pipe;
    wire [LEVEL:0] op_pipe;
    wire [(MTW+PTW)-1:0] data_pipe [0:LEVEL];
    wire [ADW-1:0] addr_pipe [0:LEVEL];

    assign vld_pipe[0]  = i_push | i_pop;
    assign op_pipe[0]   = i_pop; // 1 for Pop
    assign data_pipe[0] = i_push_data;
    assign addr_pipe[0] = 'd0; // Root node is always at address 0

    // Instantiate Engines for each level (Modular but using Shared Logic principles)
    genvar i;
    generate
        for (i=0; i<LEVEL; i=i+1) begin : lv
            PRISM_Engine #(
                .PTW(PTW), .MTW(MTW), .CTW(CTW), .ADW(ADW)
            ) u_engine (
                .i_clk(i_clk),
                .i_arst_n(i_arst_n),
                
                .i_valid(vld_pipe[i]),
                .i_op_type(op_pipe[i]),
                .i_data(data_pipe[i]),
                .i_node_addr(addr_pipe[i]),

                // Memory Interface (Abstracted for prototype)
                .o_rd_en(),
                .o_rd_addr(),
                .i_rd_data({4{{CTW{1'b0}},{MTW{1'b0}},{PTW{1'b1}}}}), // Dummy data for template

                .o_wr_en(),
                .o_wr_addr(),
                .o_wr_data(),

                // Pipeline to next level
                .o_child_valid(vld_pipe[i+1]),
                .o_child_op(op_pipe[i+1]),
                .o_child_data(data_pipe[i+1]),
                .o_child_addr(addr_pipe[i+1]),

                // Result (only Level 0 output matters for Pop)
                .o_res_data( (i == 0) ? o_pop_data : ),
                .o_res_valid( (i == 0) ? o_valid : )
            );
        end
    endgenerate

endmodule
