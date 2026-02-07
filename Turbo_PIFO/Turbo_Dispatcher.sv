`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Turbo_Dispatcher.sv
Description: High-speed Dispatcher for Interleaved PIFO Pipelines.
             Distributes Push requests to balance load and doubles throughput.
-----------------------------------------------------------------------------*/

module Turbo_Dispatcher #(
    parameter DW = 48 // MTW + PTW
)(
    input  wire          i_clk,
    input  wire          i_arst_n,

    // Input Port
    input  wire          i_push,
    input  wire [DW-1:0] i_push_data,
    input  wire          i_pop,

    // Pipeline 0 Interface
    output reg           o_p0_push,
    output reg [DW-1:0]  o_p0_data,
    output reg           o_p0_pop,

    // Pipeline 1 Interface
    output reg           o_p1_push,
    output reg [DW-1:0]  o_p1_data,
    output reg           o_p1_pop
);

    reg rr_ptr; // Round-robin pointer for Push distribution

    always @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            rr_ptr <= 0;
            o_p0_push <= 0;
            o_p1_push <= 0;
            o_p0_pop  <= 0;
            o_p1_pop  <= 0;
        end else begin
            // Push Distribution (Load Balancing)
            if (i_push) begin
                if (rr_ptr == 0) begin
                    o_p0_push <= 1;
                    o_p0_data <= i_push_data;
                    o_p1_push <= 0;
                end else begin
                    o_p1_push <= 1;
                    o_p1_data <= i_push_data;
                    o_p0_push <= 0;
                end
                rr_ptr <= ~rr_ptr;
            end else begin
                o_p0_push <= 0;
                o_p1_push <= 0;
            end

            // Pop Logic (Always check both or follow a priority policy)
            // In interleaved mode, a Pop usually needs to compare heads of all pipes.
            // Here we trigger both to let TOP handle the comparison.
            o_p0_pop <= i_pop;
            o_p1_pop <= i_pop;
        end
    end

endmodule
