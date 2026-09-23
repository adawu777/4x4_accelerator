`timescale 1ns/1ps

module tb_accelerator_4x4_interconnect;
    localparam int DATA_W = 8;
    localparam int ACC_W = 32;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic clear_acc = 1'b0;
    logic signed [DATA_W-1:0] a_in [0:3];
    logic signed [DATA_W-1:0] b_in [0:3];
    logic a_valid_in [0:3];
    logic b_valid_in [0:3];
    wire signed [ACC_W-1:0] c_out [0:3][0:3];
    logic signed [ACC_W-1:0] expected [0:3][0:3];

    systolic_array_4x4 #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc),
        .a_in(a_in), .a_valid_in(a_valid_in),
        .b_in(b_in), .b_valid_in(b_valid_in), .c_out(c_out)
    );

    always #5 clk = ~clk;  // 10 ns clock period; all inputs share one drive edge.

    task automatic idle_inputs;
        for (int i = 0; i < 4; i++) begin
            // Nonzero invalid data helps expose incorrect valid gating.
            a_in[i] = 8'sd99;
            b_in[i] = 8'sd99;
            a_valid_in[i] = 1'b0;
            b_valid_in[i] = 1'b0;
        end
    endtask

    // Continuous nonzero probes expose early, late, or repeated valid arrivals.
    // These are direct boundary stimuli, not a matrix input-skew network.
    task automatic probe_a_path;
        idle_inputs();
        for (int j = 0; j < 4; j++)
            b_valid_in[j] = 1'b1;
        b_in[0] = 8'sd3;
        b_in[1] = 8'sd5;
        b_in[2] = 8'sd7;
        b_in[3] = 8'sd11;
    endtask

    task automatic probe_b_path;
        idle_inputs();
        for (int i = 0; i < 4; i++) begin
            a_valid_in[i] = 1'b1;
            a_in[i] = DATA_W'(2 * (i + 1));
        end
    endtask

    task automatic zero_expected;
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                expected[i][j] = '0;
    endtask

    task automatic check_all(input string label);
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 4; j++) begin
                if (c_out[i][j] !== expected[i][j])
                    $fatal(1, "FAIL %s: PE(%0d,%0d) expected %0d, got %0d at %0t",
                           label, i, j, expected[i][j], c_out[i][j], $time);
            end
        end
        $display("PASS %s: all 16 accumulators match at %0t", label, $time);
    endtask

    task automatic sample_cycle(input string label);
        @(posedge clk);
        #1;  // Observe completed nonblocking register updates.
        check_all(label);
    endtask

    task automatic clear_cycle(input string label);
        @(negedge clk);
        idle_inputs();
        clear_acc = 1'b1;
        zero_expected();
        sample_cycle(label);
        @(negedge clk);
        clear_acc = 1'b0;
    endtask

    initial begin
        idle_inputs();
        zero_expected();
        // Check asynchronous reset before any rising clock edge.
        #1 rst_n = 1'b0;
        #1;
        check_all("reset");
        @(negedge clk);
        rst_n = 1'b1;
        clear_cycle("initial clear");

        // A moves along row 0. Top-edge B probes reveal its arrival cycle.
        // Cycle A0: only PE00 receives a valid A/B pair.
        @(negedge clk);
        idle_inputs();
        a_in[0] = 8'sd2;
        a_valid_in[0] = 1'b1;
        b_in[0] = 8'sd3;
        b_valid_in[0] = 1'b1;
        expected[0][0] = 32'sd6;
        sample_cycle("A0: PE00 = 6; all others zero");

        // Cycle A1: A=2 has crossed exactly one PE boundary.
        @(negedge clk);
        probe_a_path();
        expected[0][1] = 32'sd10;
        sample_cycle("A1: A reaches PE01");

        @(negedge clk);
        probe_a_path();
        expected[0][2] = 32'sd14;
        sample_cycle("A2: A reaches PE02");

        @(negedge clk);
        probe_a_path();
        expected[0][3] = 32'sd22;
        sample_cycle("A3: A reaches PE03");

        // Keep probes active after A exits to catch a stretched/repeated A valid.
        repeat (4) begin
            @(negedge clk);
            probe_a_path();
            sample_cycle("A probes: no repeated accumulation");
        end

        // Drain valid pulses before the independent B propagation test.
        // clear_acc clears accumulators, not the forwarding registers.
        repeat (4) begin
            @(negedge clk);
            idle_inputs();
            sample_cycle("A drain: accumulators hold");
        end
        clear_cycle("clear between propagation tests");

        // B moves down column 0. Left-edge A probes reveal its arrival cycle.
        @(negedge clk);
        idle_inputs();
        b_in[0] = 8'sd3;
        b_valid_in[0] = 1'b1;
        a_in[0] = 8'sd2;
        a_valid_in[0] = 1'b1;
        expected[0][0] = 32'sd6;
        sample_cycle("B0: B enters PE00");

        @(negedge clk);
        probe_b_path();
        expected[1][0] = 32'sd12;
        sample_cycle("B1: B reaches PE10");

        @(negedge clk);
        probe_b_path();
        expected[2][0] = 32'sd18;
        sample_cycle("B2: B reaches PE20");

        @(negedge clk);
        probe_b_path();
        expected[3][0] = 32'sd24;
        sample_cycle("B3: B reaches PE30");

        // Keep probes active after B exits to catch a stretched/repeated B valid.
        repeat (4) begin
            @(negedge clk);
            probe_b_path();
            sample_cycle("B probes: no repeated accumulation");
        end

        clear_cycle("final clear: all 16 accumulators zero");
        repeat (4) begin
            @(negedge clk);
            idle_inputs();
            sample_cycle("final drain: all accumulators remain zero");
        end

        $display("PASS: all systolic_array_4x4 interconnect tests completed");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL: testbench timeout");
    end
endmodule
