`timescale 1ns / 10ps

// Simple Priority Encoder for 16 bits (Low index has priority)
module priority_encoder_16 (
    input  wire [15:0] i_data,
    output reg  [3:0]  o_index,
    output wire        o_valid
);
    assign o_valid = |i_data;
    always @* begin
        if      (i_data[0])  o_index = 4'd0;
        else if (i_data[1])  o_index = 4'd1;
        else if (i_data[2])  o_index = 4'd2;
        else if (i_data[3])  o_index = 4'd3;
        else if (i_data[4])  o_index = 4'd4;
        else if (i_data[5])  o_index = 4'd5;
        else if (i_data[6])  o_index = 4'd6;
        else if (i_data[7])  o_index = 4'd7;
        else if (i_data[8])  o_index = 4'd8;
        else if (i_data[9])  o_index = 4'd9;
        else if (i_data[10]) o_index = 4'd10;
        else if (i_data[11]) o_index = 4'd11;
        else if (i_data[12]) o_index = 4'd12;
        else if (i_data[13]) o_index = 4'd13;
        else if (i_data[14]) o_index = 4'd14;
        else                 o_index = 4'd15;
    end
endmodule
