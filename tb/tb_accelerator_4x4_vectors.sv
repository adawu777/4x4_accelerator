`timescale 1ns/1ps

module tb_accelerator_4x4_vectors;
    localparam int DATA_W = 8;
    localparam int ACC_W = 32;
    localparam int DRAIN_CYCLES = 8;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic clear_acc = 1'b0;
    logic signed [DATA_W-1:0] a_in [0:3], b_in [0:3];
    logic a_valid_in [0:3], b_valid_in [0:3];
    wire signed [ACC_W-1:0] c_out [0:3][0:3];
    logic signed [DATA_W-1:0] A [0:3][0:3], B [0:3][0:3];
    longint signed expected [0:3][0:3];
    longint signed input_values [0:31], expected_values [0:31];
    integer input_fd, expected_fd;
    int testcase = 0;
    bit have_input, have_expected;

    accelerator_4x4_core #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc),
        .a_in(a_in), .a_valid_in(a_valid_in),
        .b_in(b_in), .b_valid_in(b_valid_in), .c_out(c_out)
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

    task automatic idle_inputs;
        for (int lane = 0; lane < 4; lane++) begin
            a_in[lane] = '0;
            b_in[lane] = '0;
            a_valid_in[lane] = 1'b0;
            b_valid_in[lane] = 1'b0;
        end
    endtask

    task automatic run_testcase;
        longint signed actual;
        @(negedge clk);
        idle_inputs();
        clear_acc = 1'b1;
        @(posedge clk);
        #1;
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                if (c_out[i][j] !== {ACC_W{1'b0}})
                    $fatal(1, "testcase %0d clear: row=%0d column=%0d expected=0 actual=%0d",
                           testcase, i, j, c_out[i][j]);
        @(negedge clk);
        clear_acc = 1'b0;

        for (int k = 0; k < 4; k++) begin
            @(negedge clk);
            for (int lane = 0; lane < 4; lane++) begin
                a_in[lane] = A[lane][k];
                b_in[lane] = B[k][lane];
                a_valid_in[lane] = 1'b1;
                b_valid_in[lane] = 1'b1;
            end
            @(posedge clk);
            #1;
        end
        // Last PE completes six rising edges after k=3; allow eight.
        repeat (DRAIN_CYCLES) begin
            @(negedge clk);
            idle_inputs();
            @(posedge clk);
            #1;
        end
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                actual = {{(64-ACC_W){c_out[i][j][ACC_W-1]}}, c_out[i][j]};
                if (actual !== expected[i][j])
                    $fatal(1, "testcase %0d: row=%0d column=%0d expected=%0d actual=%0d",
                           testcase, i, j, expected[i][j], actual);
            end
        $display("PASS testcase %0d", testcase);
    endtask

    initial begin
        idle_inputs();
        // Run the simulator from the project root to resolve these paths.
        input_fd = $fopen("vectors/input_vectors.txt", "r");
        if (input_fd == 0)
            $fatal(1, "Cannot open vectors/input_vectors.txt");
        expected_fd = $fopen("vectors/expected_vectors.txt", "r");
        if (expected_fd == 0)
            $fatal(1, "Cannot open vectors/expected_vectors.txt");

        #1 rst_n = 1'b0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

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
                for (int j = 0; j < 4; j++) begin
                    A[i][j] = input_values[4*i+j];
                    B[i][j] = input_values[16+4*i+j];
                    expected[i][j] = expected_values[4*i+j];
                end
            run_testcase();
        end

        read_vector_line(expected_fd, "expected_vectors.txt", testcase + 1,
                         16, 1'b0, have_expected, expected_values);
        if (have_expected)
            $fatal(1, "Unexpected extra expected testcase %0d", testcase + 1);
        if (testcase == 0)
            $fatal(1, "No vector testcases found");
        $fclose(input_fd);
        $fclose(expected_fd);
        $display("PASS: %0d vector-driven matrix multiplication tests completed", testcase);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Vector-driven testbench timeout at testcase %0d", testcase);
    end
endmodule
