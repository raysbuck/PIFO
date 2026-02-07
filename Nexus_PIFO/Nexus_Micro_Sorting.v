`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Nexus_Micro_Sorting.v
Description: High-speed Sort-and-Shift Register for micro-level PIFO.
             Maintains 16 entries in sorted order.
-----------------------------------------------------------------------------*/

module Nexus_Micro_Sorting #(
    parameter PTW = 16, // PRIORITY WIDTH
    parameter MTW = 32, // METADATA WIDTH
    parameter ENTRIES = 16
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,
    
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    
    input  wire                   i_pop,
    output wire [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_full,
    output wire                   o_empty
);

    reg [(MTW+PTW)-1:0] registers [0:ENTRIES-1];
    reg [4:0] count; // Current number of valid entries

    wire [PTW-1:0] push_prio = i_push_data[PTW-1:0];
    
    assign o_full  = (count == ENTRIES);
    assign o_empty = (count == 0);
    assign o_pop_data = registers[0]; // Highest priority always at index 0

    // Insertion Logic: Parallel comparison to find the insert position
    wire [ENTRIES-1:0] insert_pos;
    genvar g;
    generate
        for (g=0; g<ENTRIES; g=g+1) begin : gen_pos
            // We insert at the first position where the existing priority is greater than the new priority
            // (Assuming lower value = higher priority)
            assign insert_pos[g] = (g < count) ? (push_prio < registers[g][PTW-1:0]) : (g == count);
        end
    endgenerate

    // Find the first bit set in insert_pos to get the exact index
    wire [3:0] target_idx;
    priority_encoder_16 u_pe_insert (
        .i_data(insert_pos),
        .o_index(target_idx),
        .o_valid()
    );

    integer i;
    always @(posedge i_clk or negedge i_arst_n) begin
        if (!i_arst_n) begin
            count <= 0;
            for (i=0; i<ENTRIES; i++) registers[i] <= {PTW+MTW{1'b1}}; // Initialize with max priority
        end else begin
            if (i_push && !o_full) begin
                // Shift-and-Insert Logic
                for (i=0; i<ENTRIES; i++) begin
                    if (i == target_idx) begin
                        registers[i] <= i_push_data;
                    end else if (i > target_idx) begin
                        registers[i] <= registers[i-1];
                    end
                end
                count <= count + 1;
            end else if (i_pop && !o_empty) begin
                // Shift-up Logic
                for (i=0; i<ENTRIES-1; i++) begin
                    registers[i] <= registers[i+1];
                end
                registers[ENTRIES-1] <= {PTW+MTW{1'b1}};
                count <= count - 1;
            end
        end
    end

endmodule
