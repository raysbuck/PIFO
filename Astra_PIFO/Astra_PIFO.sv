`timescale 1ns / 10ps
/*-----------------------------------------------------------------------------
Module: Astra_PIFO.sv
Description: Accelerated Segment-based PIFO node with SEC (Smallest Element Cache)
             and concurrent Push-Pop support.
-----------------------------------------------------------------------------*/

module Astra_PIFO #(
    parameter PTW = 16,  // Priority Tag Width
    parameter MTW = 32,  // Metadata Width
    parameter CTW = 10   // Counter Width
)(
    input  wire                   i_clk,
    input  wire                   i_arst_n,

    // Parent Interface
    input  wire                   i_push,
    input  wire [(MTW+PTW)-1:0]    i_push_data,
    input  wire                   i_pop,
    output reg  [(MTW+PTW)-1:0]    o_pop_data,
    output wire                   o_ready,      // Node is ready for next op

    // Child Interface
    output reg  [3:0]             o_push,
    output reg  [(MTW+PTW)-1:0]    o_push_data,
    output reg  [3:0]             o_pop,
    input  wire [4*(MTW+PTW)-1:0]  i_pop_data,
    
    // Internal State Export (for TOP level)
    output wire [(MTW+PTW)-1:0]    o_best_data
);

    // Node storage: 4 elements + 1 SEC (Smallest Element Cache)
    reg [(CTW+MTW+PTW)-1:0] slot0, slot1, slot2, slot3;
    reg [(MTW+PTW)-1:0]     sec_data;
    reg                     sec_valid;

    // Internal Wires
    reg [1:0] min_load_idx;
    reg [1:0] min_val_idx;
    wire [(MTW+PTW)-1:0] incoming_data = i_push_data;
    
    // -------------------------------------------------------------------------
    // Combinatorial Logic: Find Minimums
    // -------------------------------------------------------------------------
    
    // 1. Find sub-tree with minimum load (for Push balance)
    always_comb begin
        if (slot0[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot1[(CTW+MTW+PTW)-1:(MTW+PTW)] &&
            slot0[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot2[(CTW+MTW+PTW)-1:(MTW+PTW)] &&
            slot0[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot3[(CTW+MTW+PTW)-1:(MTW+PTW)])
            min_load_idx = 2'b00;
        else if (slot1[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot2[(CTW+MTW+PTW)-1:(MTW+PTW)] &&
                 slot1[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot3[(CTW+MTW+PTW)-1:(MTW+PTW)])
            min_load_idx = 2'b01;
        else if (slot2[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot3[(CTW+MTW+PTW)-1:(MTW+PTW)])
            min_load_idx = 2'b10;
        else
            min_load_idx = 2'b11;
    end

    // 2. Find slot with minimum value (for Pop)
    always_comb begin
        if (slot0[PTW-1:0] <= slot1[PTW-1:0] &&
            slot0[PTW-1:0] <= slot2[PTW-1:0] &&
            slot0[PTW-1:0] <= slot3[PTW-1:0])
            min_val_idx = 2'b00;
        else if (slot1[PTW-1:0] <= slot2[PTW-1:0] &&
                 slot1[PTW-1:0] <= slot3[PTW-1:0])
            min_val_idx = 2'b01;
        else if (slot2[PTW-1:0] <= slot3[PTW-1:0])
            min_val_idx = 2'b10;
        else
            min_val_idx = 2'b11;
    end

    // Pre-select min slot data
    reg [(MTW+PTW)-1:0] min_slot_data;
    always_comb begin
        case (min_val_idx)
            2'b00: min_slot_data = slot0[(MTW+PTW)-1:0];
            2'b01: min_slot_data = slot1[(MTW+PTW)-1:0];
            2'b10: min_slot_data = slot2[(MTW+PTW)-1:0];
            2'b11: min_slot_data = slot3[(MTW+PTW)-1:0];
        endcase
    end

    // o_best_data for external use
    assign o_best_data = (sec_valid && (sec_data[PTW-1:0] < min_slot_data[PTW-1:0])) ? sec_data : min_slot_data;

    // -------------------------------------------------------------------------
    // Sequential Logic: Push, Pop, and Refill
    // -------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_arst_n) begin
        if (~i_arst_n) begin
            slot0 <= {{CTW{1'b0}}, {MTW{1'b0}}, {PTW{1'b1}}};
            slot1 <= {{CTW{1'b0}}, {MTW{1'b0}}, {PTW{1'b1}}};
            slot2 <= {{CTW{1'b0}}, {MTW{1'b0}}, {PTW{1'b1}}};
            slot3 <= {{CTW{1'b0}}, {MTW{1'b0}}, {PTW{1'b1}}};
            sec_data  <= {(MTW+PTW){1'b1}};
            sec_valid <= 1'b0;
            o_pop_data <= 0;
            o_push <= 0;
            o_pop <= 0;
            o_push_data <= 0;
        end else begin
            // Default signals
            o_push <= 0;
            o_pop <= 0;

            case ({i_push, i_pop})
                2'b10: begin // PUSH ONLY
                    case (min_load_idx)
                        2'b00: begin
                            if (incoming_data[PTW-1:0] < slot0[PTW-1:0]) begin
                                slot0 <= {slot0[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1, incoming_data};
                                o_push_data <= slot0[(MTW+PTW)-1:0];
                            end else begin
                                slot0[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot0[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1;
                                o_push_data <= incoming_data;
                            end
                            o_push <= 4'b0001;
                        end
                        2'b01: begin
                            if (incoming_data[PTW-1:0] < slot1[PTW-1:0]) begin
                                slot1 <= {slot1[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1, incoming_data};
                                o_push_data <= slot1[(MTW+PTW)-1:0];
                            end else begin
                                slot1[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot1[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1;
                                o_push_data <= incoming_data;
                            end
                            o_push <= 4'b0010;
                        end
                        2'b10: begin
                            if (incoming_data[PTW-1:0] < slot2[PTW-1:0]) begin
                                slot2 <= {slot2[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1, incoming_data};
                                o_push_data <= slot2[(MTW+PTW)-1:0];
                            end else begin
                                slot2[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot2[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1;
                                o_push_data <= incoming_data;
                            end
                            o_push <= 4'b0100;
                        end
                        2'b11: begin
                            if (incoming_data[PTW-1:0] < slot3[PTW-1:0]) begin
                                slot3 <= {slot3[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1, incoming_data};
                                o_push_data <= slot3[(MTW+PTW)-1:0];
                            end else begin
                                slot3[(CTW+MTW+PTW)-1:(MTW+PTW)] <= slot3[(CTW+MTW+PTW)-1:(MTW+PTW)] + 1'b1;
                                o_push_data <= incoming_data;
                            end
                            o_push <= 4'b1000;
                        end
                    endcase
                end

                2'b01: begin // POP ONLY
                    if (sec_valid && (sec_data[PTW-1:0] < min_slot_data[PTW-1:0])) begin
                        o_pop_data <= sec_data;
                        sec_valid <= 1'b0;
                        o_pop[min_val_idx] <= 1'b1;
                    end else begin
                        o_pop_data <= min_slot_data;
                        case (min_val_idx)
                            2'b00: slot0 <= {slot0[(CTW+MTW+PTW)-1:(MTW+PTW)] - 1'b1, i_pop_data[0*(MTW+PTW) +: (MTW+PTW)]};
                            2'b01: slot1 <= {slot1[(CTW+MTW+PTW)-1:(MTW+PTW)] - 1'b1, i_pop_data[1*(MTW+PTW) +: (MTW+PTW)]};
                            2'b10: slot2 <= {slot2[(CTW+MTW+PTW)-1:(MTW+PTW)] - 1'b1, i_pop_data[2*(MTW+PTW) +: (MTW+PTW)]};
                            2'b11: slot3 <= {slot3[(CTW+MTW+PTW)-1:(MTW+PTW)] - 1'b1, i_pop_data[3*(MTW+PTW) +: (MTW+PTW)]};
                        endcase
                        o_pop[min_val_idx] <= 1'b1;
                    end
                end

                2'b11: begin // CONCURRENT PUSH-POP (SWAP)
                    if (incoming_data[PTW-1:0] < o_best_data[PTW-1:0]) begin
                        o_pop_data <= incoming_data;
                    end else begin
                        o_pop_data <= o_best_data;
                        if (sec_valid && (sec_data[PTW-1:0] < min_slot_data[PTW-1:0])) begin
                            sec_data <= incoming_data;
                        end else begin
                            case (min_val_idx)
                                2'b00: slot0[(MTW+PTW)-1:0] <= incoming_data;
                                2'b01: slot1[(MTW+PTW)-1:0] <= incoming_data;
                                2'b10: slot2[(MTW+PTW)-1:0] <= incoming_data;
                                2'b11: slot3[(MTW+PTW)-1:0] <= incoming_data;
                            endcase
                        end
                    end
                end
                
                default: begin
                    // Idle: Try to refill SEC if invalid
                    if (!sec_valid) begin
                        // Pre-fetch logic could go here
                    end
                end
            endcase
        end
    end

    assign o_ready = 1'b1;

endmodule
