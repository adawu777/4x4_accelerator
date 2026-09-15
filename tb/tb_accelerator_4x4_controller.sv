`timescale 1ns/1ps

module tb_accelerator_4x4_controller;
    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic start = 1'b0;
    wire busy, done, clear_acc, feed_valid;
    wire [1:0] k_counter;

    accelerator_4x4_controller dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .busy(busy), .done(done), .clear_acc(clear_acc),
        .feed_valid(feed_valid), .k_counter(k_counter)
    );

    always #5 clk = ~clk;

    task automatic check_bit(
        input string test_name, signal_name,
        input logic expected_value, actual_value
    );
        if (actual_value !== expected_value)
            $fatal(1, "%s: %s expected=%b actual=%b time=%0t",
                   test_name, signal_name, expected_value, actual_value, $time);
    endtask

    task automatic check_controls(
        input string test_name,
        input logic expected_busy, expected_done,
        input logic expected_clear, expected_feed
    );
        check_bit(test_name, "busy", expected_busy, busy);
        check_bit(test_name, "done", expected_done, done);
        check_bit(test_name, "clear_acc", expected_clear, clear_acc);
        check_bit(test_name, "feed_valid", expected_feed, feed_valid);
    endtask

    task automatic check_k(input string test_name, input logic [1:0] expected_k);
        if (k_counter !== expected_k)
            $fatal(1, "%s: k_counter expected=%0d actual=%0d time=%0t",
                   test_name, expected_k, k_counter, $time);
    endtask

    task automatic check_idle(input string test_name);
        check_controls(test_name, 0, 0, 0, 0);
        check_k(test_name, 2'd0);
    endtask

    // All synchronous stimulus changes on falling edges. Return after NBA.
    task automatic step(input logic start_value);
        @(negedge clk);
        start = start_value;
        @(posedge clk);
        #1;
    endtask

    task automatic launch(input string test_name);
        check_idle({test_name, " before start"});
        step(1'b1);
        check_controls({test_name, " CLEAR"}, 1, 0, 1, 0);
        step(1'b0);
        check_controls({test_name, " FEED entry"}, 1, 0, 0, 1);
        check_k({test_name, " FEED entry"}, 2'd0);
        $display("PASS %s: one-cycle start and one-cycle CLEAR", test_name);
    endtask

    task automatic run_operation(input string test_name, input bit inject_start);
        int feed_cycles, drain_edges;
        string label;
        launch(test_name);
        feed_cycles = 0;
        for (int k = 0; k < 4; k++) begin
            label = $sformatf("%s FEED cycle %0d", test_name, k + 1);
            check_controls(label, 1, 0, 0, 1);
            check_k(label, 2'(k));
            feed_cycles++;
            // Pulse start for one cycle while already in FEED (k=1).
            step(inject_start && k == 1);
        end
        check_controls({test_name, " DRAIN entry"}, 1, 0, 0, 0);
        if (feed_cycles != 4)
            $fatal(1, "%s: FEED count expected=4 actual=%0d time=%0t",
                   test_name, feed_cycles, $time);
        $display("PASS %s: exactly four FEED cycles, k=0,1,2,3", test_name);

        // Entry into DRAIN is the last FEED edge, not a drain edge.
        // Count six subsequent rising edges explicitly. DONE must remain
        // low before each edge and may assert only after the sixth edge.
        drain_edges = 0;
        for (int edge_number = 1; edge_number <= 6; edge_number++) begin
            label = $sformatf("%s before DRAIN edge %0d", test_name, edge_number);
            check_controls(label, 1, 0, 0, 0);
            @(negedge clk);
            start = inject_start && edge_number == 3;
            #1;
            check_controls(label, 1, 0, 0, 0);
            @(posedge clk);
            drain_edges++;
            #1;
            if (edge_number < 6)
                check_controls($sformatf("%s after DRAIN edge %0d", test_name,
                                        edge_number), 1, 0, 0, 0);
            else
                check_controls({test_name, " DONE after sixth DRAIN edge"},
                               0, 1, 0, 0);
        end
        if (drain_edges != 6)
            $fatal(1, "%s: DRAIN count expected=6 actual=%0d time=%0t",
                   test_name, drain_edges, $time);
        $display("PASS %s: exactly six DRAIN edges", test_name);

        step(1'b0);
        check_idle({test_name, " IDLE after one DONE cycle"});
        repeat (3) begin
            step(1'b0);
            check_idle({test_name, " IDLE with no queued restart"});
        end
        $display("PASS %s: exactly one DONE cycle and return to IDLE", test_name);
        if (inject_start)
            $display("PASS %s: FEED and DRAIN start pulses ignored", test_name);
    endtask

    task automatic reset_during_operation(input bit in_drain);
        string test_name;
        test_name = in_drain ? "asynchronous reset in DRAIN" :
                               "asynchronous reset in FEED";
        launch(test_name);
        if (in_drain) begin
            repeat (4) step(1'b0);
            check_controls({test_name, " before reset"}, 1, 0, 0, 0);
        end else begin
            step(1'b0);
            check_controls({test_name, " before reset"}, 1, 0, 0, 1);
            check_k({test_name, " nonzero k before reset"}, 2'd1);
        end
        // step returned 1 ns after a rising edge. Assert at +2 ns and
        // check at +3 ns, before either the falling or next rising edge.
        #1 rst_n = 1'b0;
        #1;
        check_idle({test_name, " immediately after reset"});
        step(1'b0);
        check_idle({test_name, " held reset"});
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        check_idle({test_name, " reset released"});
        repeat (3) begin
            step(1'b0);
            check_idle({test_name, " waiting for new start"});
        end
        $display("PASS %s: immediate reset and IDLE until new start", test_name);
    endtask

    initial begin
        // Establish a falling reset transition before the first clock edge.
        #1 rst_n = 1'b0;
        #1;
        check_idle("initial asynchronous reset");
        step(1'b0);
        check_idle("initial reset held");
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        check_idle("initial reset released");
        $display("PASS RESET: all outputs and k_counter reset to zero");

        run_operation("normal operation", 1'b0);
        run_operation("start while busy", 1'b1);
        reset_during_operation(1'b0);
        reset_during_operation(1'b1);
        run_operation("operation after reset", 1'b0);

        $display("PASS: all accelerator_4x4_controller tests completed");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout: expected=all tests completed actual=still running time=%0t",
               $time);
    end
endmodule
