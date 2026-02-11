`timescale 1ns / 10ps

module tb_Astra_PIFO;

    // Parameters
    parameter PTW = 16;
    parameter MTW = 32;
    parameter CTW = 10;

    // Signals
    reg                   clk;
    reg                   arst_n;
    reg                   i_push;
    reg  [(MTW+PTW)-1:0]  i_push_data;
    reg                   i_pop;
    wire [(MTW+PTW)-1:0]  o_pop_data;
    wire                  o_ready;
    reg  [4*(MTW+PTW)-1:0] i_pop_data; // Simulated child data

    // Instantiate DUT (Device Under Test)
    Astra_PIFO #(
        .PTW(PTW),
        .MTW(MTW),
        .CTW(CTW)
    ) dut (
        .i_clk(clk),
        .i_arst_n(arst_n),
        .i_push(i_push),
        .i_push_data(i_push_data),
        .i_pop(i_pop),
        .o_pop_data(o_pop_data),
        .o_ready(o_ready),
        .o_push(),      // Ignored in this simple TB
        .o_push_data(),
        .o_pop(),
        .i_pop_data(i_pop_data),
        .o_best_data()
    );

    // Clock Generation (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // Task: Push Data
    task push(input [PTW-1:0] prio, input [MTW-1:0] meta);
        begin
            @(posedge clk);
            i_push = 1;
            i_push_data = {meta, prio};
            $display("[PUSH] Priority: %d, Meta: %h", prio, meta);
            @(posedge clk);
            i_push = 0;
        end
    endtask

    // Task: Pop Data
    task pop();
        begin
            @(posedge clk);
            i_pop = 1;
            @(posedge clk);
            i_pop = 0;
            $display("[POP]  Data Received: Priority=%d, Meta=%h", o_pop_data[PTW-1:0], o_pop_data[MTW+PTW-1:PTW]);
        end
    endtask

    // Task: Concurrent Push and Pop
    task push_pop(input [PTW-1:0] prio, input [MTW-1:0] meta);
        begin
            @(posedge clk);
            i_push = 1;
            i_pop = 1;
            i_push_data = {meta, prio};
            $display("[CONC] PUSH Priority: %d | POP issued", prio);
            @(posedge clk);
            i_push = 0;
            i_pop = 0;
            $display("[CONC] Result Pop: Priority=%d", o_pop_data[PTW-1:0]);
        end
    endtask

    // Test Sequence
    initial begin
        // Initialize
        arst_n = 0;
        i_push = 0;
        i_pop = 0;
        i_push_data = 0;
        i_pop_data = {(4*(MTW+PTW)){1'b1}}; // All children empty (high priority value)

        repeat(5) @(posedge clk);
        arst_n = 1; // Release Reset
        $display("--- Starting Astra_PIFO Test ---");

        // 1. Sequential Pushes
        push(16'd50, 32'hAAAA);
        push(16'd20, 32'hBBBB);
        push(16'd80, 32'hCCCC);
        push(16'd10, 32'hDDDD);

        repeat(2) @(posedge clk);

        // 2. Normal Pop (Should get 10)
        pop();

        // 3. Astra Special: Concurrent Push(5) and Pop
        // Since 5 is smaller than the current minimum (20), 
        // Astra-Tree should trigger the "Bypass" logic.
        push_pop(16'd5, 32'hEEEE);

        // 4. Final Pop
        pop();

        #50;
        $display("--- Test Completed ---");
        $finish;
    end

endmodule
