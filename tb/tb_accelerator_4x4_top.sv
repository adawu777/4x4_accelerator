`timescale 1ns/1ps

module tb_accelerator_4x4_top;
    localparam int DATA_W = 8;
    localparam int ACC_W = 32;
    localparam int BUSY_CYCLES = 1 + 4 + 6;
    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic load = 1'b0;
    logic start = 1'b0;
    logic signed [DATA_W-1:0] a_matrix [0:3][0:3];
    logic signed [DATA_W-1:0] b_matrix [0:3][0:3];
    wire busy, done;
    wire signed [ACC_W-1:0] c_out [0:3][0:3];
    longint signed expected [0:3][0:3];
    longint signed input_values [0:31], expected_values [0:31];
    integer input_fd, expected_fd;
    int testcase = 0;
    bit have_input, have_expected;

    accelerator_4x4_top #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst_n(rst_n), .load(load), .start(start),
        .a_matrix(a_matrix), .b_matrix(b_matrix),
        .busy(busy), .done(done), .c_out(c_out)
    );

    always #5 clk = ~clk;

    // Read characters with checked fscanf calls to preserve physical lines.
    // A plain sequence of %d scans would silently cross incomplete lines.
    // Decimal parsing rejects X/Z, underscores, suffixes, and numeric overflow.
    task automatic read_vector_line(
        input integer fd,
        input string filename,
        input int line_number,
        input int required_count,
        input bit int8_values,
        output bit have_line,
        output longint signed values [0:31]
    );
        int rc, count, digits;
        byte unsigned ch;
        bit active, negative, saw_character, at_eof, separator;
        longint signed magnitude, value;
        count = 0;
        digits = 0;
        active = 0;
        negative = 0;
        saw_character = 0;
        magnitude = 0;
        have_line = 0;
        for (int n = 0; n < 32; n++) values[n] = 0;
        forever begin
            rc = $fscanf(fd, "%c", ch);
            at_eof = (rc == -1);
            if (rc != 1 && !(at_eof && $feof(fd)))
                $fatal(1, "%s line %0d: read failure, fscanf returned %0d",
                       filename, line_number, rc);
            if (at_eof && !saw_character) begin
                have_line = 0;
                return;
            end
            if (!at_eof) saw_character = 1;
            separator = at_eof || ch == 8'd32 || ch == 8'd9 ||
                        ch == 8'd13 || ch == 8'd10;
            if (separator) begin
                if (active) begin
                    if (digits == 0)
                        $fatal(1, "%s line %0d: sign without decimal digits",
                               filename, line_number);
                    if (count >= required_count)
                        $fatal(1, "%s line %0d: more than %0d integers",
                               filename, line_number, required_count);
                    value = negative ? -magnitude : magnitude;
                    if (int8_values && (value < -128 || value > 127))
                        $fatal(1, "%s line %0d: input %0d outside INT8 range",
                               filename, line_number, value);
                    if (!int8_values &&
                        (value < -64'sd2147483648 || value > 64'sd2147483647))
                        $fatal(1, "%s line %0d: expected value outside signed ACC_W range",
                               filename, line_number);
                    values[count] = value;
                    count++;
                    active = 0;
                    negative = 0;
                    digits = 0;
                    magnitude = 0;
                end
                if (at_eof || ch == 8'd10) begin
                    if (count != required_count)
                        $fatal(1, "%s line %0d: expected %0d integers, found %0d",
                               filename, line_number, required_count, count);
                    have_line = 1;
                    return;
                end
            end else if (ch >= 8'd48 && ch <= 8'd57) begin
                active = 1;
                digits++;
                magnitude = magnitude * 10 + (ch - 8'd48);
                // Bound each step, before a long decimal token can overflow.
                if (magnitude > 64'sd2147483648)
                    $fatal(1, "%s line %0d: decimal magnitude out of range",
                           filename, line_number);
            end else if (!active && (ch == 8'd43 || ch == 8'd45)) begin
                active = 1;
                negative = (ch == 8'd45);
            end else begin
                $fatal(1, "%s line %0d: invalid decimal character 0x%02h",
                       filename, line_number, ch);
            end
        end
    endtask

    task automatic check_protocol(
        input string label, input logic expected_busy, expected_done
    );
        if (busy !== expected_busy || done !== expected_done)
            $fatal(1, "testcase %0d %s: expected busy=%b done=%b actual busy=%b done=%b time=%0t",
                   testcase, label, expected_busy, expected_done, busy, done, $time);
    endtask

    task automatic check_zero(input string label);
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                if (c_out[i][j] !== {ACC_W{1'b0}})
                    $fatal(1, "testcase %0d %s: row=%0d column=%0d expected=0 actual=%0d time=%0t",
                           testcase, label, i, j, c_out[i][j], $time);
    endtask

    task automatic check_result(input string label);
        logic signed [63:0] actual;
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                actual = {{(64-ACC_W){c_out[i][j][ACC_W-1]}}, c_out[i][j]};
                if (actual !== expected[i][j])
                    $fatal(1, "testcase %0d %s: row=%0d column=%0d expected=%0d actual=%0d time=%0t",
                           testcase, label, i, j, expected[i][j], actual, $time);
            end
    endtask

    task automatic idle_inputs;
        load = 1'b0;
        start = 1'b0;
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                a_matrix[i][j] = '0;
                b_matrix[i][j] = '0;
            end
    endtask

    task automatic load_operands;
        @(negedge clk);
        check_protocol("before load", 0, 0);
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                a_matrix[i][j] = input_values[4*i+j];
                b_matrix[i][j] = input_values[16+4*i+j];
            end
        load = 1'b1;
        @(posedge clk);
        #1;
        check_protocol("load edge stays idle", 0, 0);
        @(negedge clk);
        // Remove external data after capture to exercise buffer retention.
        idle_inputs();
    endtask

    task automatic pulse_start;
        @(negedge clk);
        check_protocol("before start", 0, 0);
        start = 1'b1;
        @(posedge clk);
        #1;
        check_protocol("start accepted / CLEAR interval", 1, 0);
        @(negedge clk);
        start = 1'b0;
    endtask

    task automatic run_testcase;
        load_operands();
        pulse_start();
        // Start acceptance is E0. Busy is high during E0..E10;
        // E11 is the sixth drain edge and must assert DONE after NBA.
        // Only aggregate timing is observable; no internal state is read.
        for (int elapsed = 1; elapsed <= BUSY_CYCLES; elapsed++) begin
            @(posedge clk);
            #1;
            if (elapsed < BUSY_CYCLES)
                check_protocol($sformatf("busy interval %0d", elapsed + 1), 1, 0);
            else begin
                check_protocol("completion at expected edge", 0, 1);
                check_result("DONE scoreboard");
            end
            if (elapsed == 1)
                check_zero("controller clear completed before first feed edge");
        end
        @(negedge clk);
        check_protocol("DONE held for full cycle", 0, 1);
        check_result("DONE hold");
        // First iteration must drop DONE, then all iterations retain C.
        repeat (3) begin
            @(posedge clk);
            #1;
            check_protocol("idle after DONE", 0, 0);
            check_result("idle result stability");
        end
        $display("PASS testcase %0d", testcase);
    endtask

    task automatic reset_after_completion;
        // Called 1 ns after a rising edge: assert at +2, inspect at +3.
        #1 rst_n = 1'b0;
        #1;
        check_protocol("asynchronous reset after completion", 0, 0);
        check_zero("asynchronous reset after completion");
        @(posedge clk);
        #1;
        check_protocol("held reset", 0, 0);
        check_zero("held reset");
        @(negedge clk);
        rst_n = 1'b1;
        repeat (3) begin
            @(posedge clk);
            #1;
            check_protocol("reset released without new start", 0, 0);
            check_zero("reset released without new start");
        end
        $display("PASS: asynchronous reset after completion and idle retention");
    endtask

    initial begin
        idle_inputs();
        // Relative vector paths require running from the project root.
        input_fd = $fopen("vectors/input_vectors.txt", "r");
        if (input_fd == 0) $fatal(1, "Cannot open vectors/input_vectors.txt");
        expected_fd = $fopen("vectors/expected_vectors.txt", "r");
        if (expected_fd == 0) $fatal(1, "Cannot open vectors/expected_vectors.txt");
        #1 rst_n = 1'b0;
        #1;
        check_protocol("initial asynchronous reset", 0, 0);
        check_zero("initial asynchronous reset");
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        check_protocol("initial reset released", 0, 0);
        check_zero("initial reset released");
        $display("PASS: initial reset");

        forever begin
            read_vector_line(input_fd, "input_vectors.txt", testcase + 1,
                             32, 1'b1, have_input, input_values);
            if (!have_input) break;
            read_vector_line(expected_fd, "expected_vectors.txt", testcase + 1,
                             16, 1'b0, have_expected, expected_values);
            if (!have_expected)
                $fatal(1, "Missing expected testcase %0d", testcase + 1);
            testcase++;
            for (int i = 0; i < 4; i++)
                for (int j = 0; j < 4; j++)
                    expected[i][j] = expected_values[4*i+j];
            run_testcase();
            // No global reset between these normal vector operations.
        end
        read_vector_line(expected_fd, "expected_vectors.txt", testcase + 1,
                         16, 1'b0, have_expected, expected_values);
        if (have_expected)
            $fatal(1, "Unexpected extra expected testcase %0d", testcase + 1);
        if (testcase == 0) $fatal(1, "No vector testcases found");
        $fclose(input_fd);
        $fclose(expected_fd);
        reset_after_completion();
        $display("PASS: all accelerator_4x4_top end-to-end tests completed");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "testcase %0d timeout: expected=completion actual=still running time=%0t",
               testcase, $time);
    end
endmodule
