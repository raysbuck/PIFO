`timescale 1ns / 10ps

module tb_Aether_PIFO;

    parameter PTW = 16;
    parameter MTW = 32;
    parameter LEVEL = 3; // Use small level for quick simulation

    reg clk;
    reg arst_n;
    reg i_push, i_pop;
    reg [(MTW+PTW)-1:0] i_data;
    wire [(MTW+PTW)-1:0] o_data;
    wire o_ready;

    Aether_PIFO_Top #(
        .PTW(PTW),
        .MTW(MTW),
        .LEVEL(LEVEL)
    ) dut (
        .i_clk(clk),
        .i_arst_n(arst_n),
        .i_push(i_push),
        .i_pop(i_pop),
        .i_data(i_data),
        .o_data(o_data),
        .o_ready(o_ready)
    );

    // 250MHz Clock
    initial clk = 0;
    always #2 clk = ~clk;

    initial begin
        arst_n = 0;
        i_push = 0;
        i_pop = 0;
        i_data = 0;
        #20 arst_n = 1;

        $display("--- Aether_PIFO Functional Test ---");

        // Push some values
        push(16'd100, 32'hA1);
        push(16'd50,  32'hB2);
        push(16'd150, 32'hC3);
        push(16'd10,  32'hD4);

        repeat(20) @(posedge clk);

        // Pop (Should return 10)
        pop();
        
        repeat(10) @(posedge clk);
        $display("Test Done.");
        $finish;
    end

    task push(input [PTW-1:0] p, input [MTW-1:0] m);
        begin
            @(posedge clk);
            i_push = 1; i_data = {m, p};
            @(posedge clk);
            i_push = 0;
        end
    endtask

    task pop();
        begin
            @(posedge clk);
            i_pop = 1;
            @(posedge clk);
            i_pop = 0;
            $display("[POP] Result Data (Priority): %d", o_data[PTW-1:0]);
        end
    endtask

endmodule
