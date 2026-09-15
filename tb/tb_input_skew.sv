`timescale 1ns/1ps

module tb_input_skew;
    localparam int DATA_W = 8;
    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic signed [DATA_W-1:0] a_in [0:3], b_in [0:3];
    logic a_valid_in [0:3], b_valid_in [0:3];
    wire signed [DATA_W-1:0] a_out [0:3], b_out [0:3];
    wire a_valid_out [0:3], b_valid_out [0:3];

    // Boundary sample history: age 0 is the most recent rising-edge input.
    logic signed [DATA_W-1:0] a_history [0:2][0:3];
    logic signed [DATA_W-1:0] b_history [0:2][0:3];
    logic av_history [0:2][0:3], bv_history [0:2][0:3];

    input_skew #(.DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .a_in(a_in), .a_valid_in(a_valid_in),
        .b_in(b_in), .b_valid_in(b_valid_in),
        .a_out(a_out), .a_valid_out(a_valid_out),
        .b_out(b_out), .b_valid_out(b_valid_out)
    );

    always #5 clk = ~clk;

    task automatic clear_history;
        for (int age = 0; age < 3; age++)
            for (int lane = 0; lane < 4; lane++) begin
                a_history[age][lane] = '0;
                b_history[age][lane] = '0;
                av_history[age][lane] = 1'b0;
                bv_history[age][lane] = 1'b0;
            end
    endtask

    task automatic record_inputs;
        for (int age = 2; age > 0; age--)
            for (int lane = 0; lane < 4; lane++) begin
                a_history[age][lane] = a_history[age-1][lane];
                b_history[age][lane] = b_history[age-1][lane];
                av_history[age][lane] = av_history[age-1][lane];
                bv_history[age][lane] = bv_history[age-1][lane];
            end
        for (int lane = 0; lane < 4; lane++) begin
            a_history[0][lane] = a_in[lane];
            b_history[0][lane] = b_in[lane];
            av_history[0][lane] = a_valid_in[lane];
            bv_history[0][lane] = b_valid_in[lane];
        end
    endtask

    task automatic check_outputs(input string label);
        logic signed [DATA_W-1:0] expected_a, expected_b;
        logic expected_av, expected_bv;
        for (int lane = 0; lane < 4; lane++) begin
            if (lane == 0) begin
                // The bypass follows inputs even while reset is asserted.
                expected_a = a_in[0];
                expected_b = b_in[0];
                expected_av = a_valid_in[0];
                expected_bv = b_valid_in[0];
            end else begin
                expected_a = a_history[lane-1][lane];
                expected_b = b_history[lane-1][lane];
                expected_av = av_history[lane-1][lane];
                expected_bv = bv_history[lane-1][lane];
            end
            // Check data even when invalid, independently for A and B.
            if (a_out[lane] !== expected_a || a_valid_out[lane] !== expected_av)
                $fatal(1, "%s A lane %0d at %0t: expected data=%0d valid=%b, got data=%0d valid=%b",
                       label, lane, $time, expected_a, expected_av, a_out[lane], a_valid_out[lane]);
            if (b_out[lane] !== expected_b || b_valid_out[lane] !== expected_bv)
                $fatal(1, "%s B lane %0d at %0t: expected data=%0d valid=%b, got data=%0d valid=%b",
                       label, lane, $time, expected_b, expected_bv, b_out[lane], b_valid_out[lane]);
        end
    endtask

    task automatic cycle(
        input int a_base, a_step, b_base, b_step,
        input logic [3:0] a_valid_mask, b_valid_mask,
        input string label
    );
        @(negedge clk);
        for (int lane = 0; lane < 4; lane++) begin
            a_in[lane] = DATA_W'(a_base + a_step * lane);
            b_in[lane] = DATA_W'(b_base + b_step * lane);
            a_valid_in[lane] = a_valid_mask[lane];
            b_valid_in[lane] = b_valid_mask[lane];
        end
        #1;
        // Lane 0 must already respond; registered lanes must still hold.
        check_outputs({label, " before posedge"});
        @(posedge clk);
        if (!rst_n) clear_history();
        else record_inputs();
        #1; // Sample after DUT nonblocking assignments have settled.
        check_outputs({label, " after posedge"});
    endtask

    initial begin
        for (int lane = 0; lane < 4; lane++) begin
            a_in[lane] = DATA_W'(10 + lane);
            b_in[lane] = DATA_W'(-10 - lane);
            a_valid_in[lane] = 1'b1;
            b_valid_in[lane] = 1'b1;
        end
        clear_history();
        #1 rst_n = 1'b0;
        #1;
        check_outputs("initial asynchronous reset before first clock");
        @(negedge clk);
        rst_n = 1'b1;
        // Account for the edge before the first cycle task drives inputs.
        @(posedge clk);
        record_inputs();
        #1;
        check_outputs("reset release");

        // Fill every delay stage with nonzero, valid data before resetting.
        repeat (3)
            cycle(50, 1, -60, -1, 4'b1111, 4'b1111, "reset prefill");
        #1 rst_n = 1'b0; // t=47 ns: between posedge 45 and negedge 50.
        clear_history();
        #1;
        check_outputs("asynchronous reset of occupied pipelines");
        cycle(-12, -1, 23, 1, 4'b1111, 4'b0000, "bypass during reset");
        @(negedge clk);
        for (int lane = 0; lane < 4; lane++) begin
            a_in[lane] = '0;
            b_in[lane] = '0;
            a_valid_in[lane] = 1'b0;
            b_valid_in[lane] = 1'b0;
        end
        rst_n = 1'b1;
        @(posedge clk);
        record_inputs();
        #1;
        check_outputs("reset release with zero inputs");
        repeat (3)
            cycle(0, 0, 0, 0, 4'b0000, 4'b0000, "no stale reset data");
        $display("PASS Test 1: asynchronous reset and combinational lane 0");

        cycle(10, 10, 1, 1, 4'b1111, 4'b1111, "single valid pulse");
        repeat (4)
            cycle(0, 0, 0, 0, 4'b0000, 4'b0000, "single pulse drain");
        $display("PASS Test 2: independent A/B delays of 0, 1, 2, 3 cycles");

        cycle(-40, 3, 11, 2, 4'b1111, 4'b1111, "first valid");
        cycle(70, 1, -70, -1, 4'b0000, 4'b0000, "invalid bubble");
        cycle(21, 4, -31, -2, 4'b1111, 4'b1111, "second valid");
        repeat (4)
            cycle(0, 0, 0, 0, 4'b0000, 4'b0000, "bubble drain");
        // Different A/B valid patterns also detect accidental cross-coupling.
        cycle(-10, 2, 30, 3, 4'b0101, 4'b1010, "independent valids 1");
        cycle(60, -3, -50, 2, 4'b1010, 4'b0101, "independent valids 2");
        repeat (4)
            cycle(0, 0, 0, 0, 4'b0000, 4'b0000, "independent valid drain");
        $display("PASS Test 3: bubbles preserved and signed data/valid aligned");
        $display("PASS: all input_skew tests completed");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "FAIL: input_skew testbench timeout");
    end
endmodule
