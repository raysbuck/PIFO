`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Aether_PIFO_Top.sv
Description: Top-level tree structure for Aether_PIFO.
             Designed for ultra-high frequency and large scale.
             Default LEVEL=8 supports 87,380 flows.
-----------------------------------------------------------------------------*/

module Aether_PIFO_Top #(
    parameter PTW   = 16,
    parameter MTW   = 32,
    parameter LEVEL = 8   // Level 8 = 87,380 flows (4 flows per node)
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    input  wire                   i_push,
    input  wire                   i_pop,
    input  wire [(MTW+PTW)-1:0]    i_data,
    
    output wire [(MTW+PTW)-1:0]    o_data,
    output wire                   o_ready
);

    // Calculate total nodes: (4^LEVEL - 1) / 3
    function integer get_total_nodes(input integer l);
        integer total, i;
        begin
            total = 0;
            for (i=0; i<l; i++) total = total + (4**i);
            get_total_nodes = total;
        end
    endfunction

    localparam NODES = get_total_nodes(LEVEL);

    // Interconnect wires
    wire [NODES-1:0]          n_valid;
    wire [NODES-1:0]          n_op;
    wire [(MTW+PTW)-1:0]      n_data [0:NODES-1];
    wire [3:0]                n_mask [0:NODES-1];
    
    wire [(MTW+PTW)-1:0]      n_pop_out [0:NODES-1];

    // Node Input Buffers (To break critical paths between levels)
    reg                       n_valid_r [0:NODES-1];
    reg                       n_op_r    [0:NODES-1];
    reg [(MTW+PTW)-1:0]       n_data_r  [0:NODES-1];

    generate
        for (genvar i=0; i<NODES; i++) begin : gen_nodes
            Aether_PIFO_Node #(
                .PTW(PTW),
                .MTW(MTW)
            ) u_node (
                .i_clk(i_clk),
                .i_arst_n(i_arst_n),
                .i_valid(n_valid_r[i]),
                .i_op(n_op_r[i]),
                .i_data(n_data_r[i]),
                
                .o_c_valid(n_valid[i]),
                .o_c_op(n_op[i]),
                .o_c_data(n_data[i]),
                .o_c_mask(n_mask[i]),
                .o_pop_data(n_pop_out[i])
            );

            // Level-to-Level Registering (Systolic Architecture)
            // This ensures Fmax is independent of tree depth
            if (i == 0) begin : gen_root
                always @(posedge i_clk or negedge i_arst_n) begin
                    if (~i_arst_n) begin
                        n_valid_r[0] <= 1'b0;
                        n_op_r[0]    <= 1'b0;
                        n_data_r[0]  <= {(MTW+PTW){1'b0}};
                    end else begin
                        n_valid_r[0] <= (i_push | i_pop);
                        n_op_r[0]    <= i_pop;
                        n_data_r[0]  <= i_data;
                    end
                end
            end else begin : gen_child
                localparam integer P_IDX = (i-1)/4;
                localparam integer C_POS = (i-1)%4;
                always @(posedge i_clk or negedge i_arst_n) begin
                    if (~i_arst_n) begin
                        n_valid_r[i] <= 1'b0;
                        n_op_r[i]    <= 1'b0;
                        n_data_r[i]  <= {(MTW+PTW){1'b0}};
                    end else begin
                        n_valid_r[i] <= n_valid[P_IDX] && n_mask[P_IDX][C_POS];
                        n_op_r[i]    <= n_op[P_IDX];
                        n_data_r[i]  <= n_data[P_IDX];
                    end
                end
            end
        end
    endgenerate

    assign o_data  = n_pop_out[0];
    assign o_ready = 1'b1; // Systolic array is always ready to accept input

endmodule
