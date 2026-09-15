`timescale 1ns/1ps

module tb_matrix_operand_buffer;
    localparam int DATA_W = 8;
    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic load = 1'b0;
    logic [1:0] k_counter = 2'd0;
    logic signed [DATA_W-1:0] a_matrix [0:3][0:3];
    logic signed [DATA_W-1:0] b_matrix [0:3][0:3];
    logic signed [DATA_W-1:0] expected_a [0:3][0:3];
    logic signed [DATA_W-1:0] expected_b [0:3][0:3];
    wire signed [DATA_W-1:0] a_feed [0:3], b_feed [0:3];
    int rising_edges = 0;

    matrix_operand_buffer #(.DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n), .load(load),
        .a_matrix(a_matrix), .b_matrix(b_matrix),
        .k_counter(k_counter), .a_feed(a_feed), .b_feed(b_feed)
    );

    always #5 clk = ~clk;
    always @(posedge clk) rising_edges++;

    task automatic zero_expected;
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                expected_a[i][j] = '0;
                expected_b[i][j] = '0;
            end
    endtask

    task automatic check_feed(input string test_name);
        for (int lane = 0; lane < 4; lane++) begin
            if (a_feed[lane] !== expected_a[lane][k_counter])
                $fatal(1, "%s: A lane=%0d k=%0d expected=%0d actual=%0d time=%0t",
                       test_name, lane, k_counter, expected_a[lane][k_counter],
                       a_feed[lane], $time);
            if (b_feed[lane] !== expected_b[k_counter][lane])
                $fatal(1, "%s: B lane=%0d k=%0d expected=%0d actual=%0d time=%0t",
                       test_name, lane, k_counter, expected_b[k_counter][lane],
                       b_feed[lane], $time);
        end
    endtask

    // Call with at least 2 ns remaining before the next rising edge.
    // Four address changes and comparisons complete in just 2 ns.
    task automatic sweep_k(input string test_name);
        int edges_before;
        edges_before = rising_edges;
        for (int k = 0; k < 4; k++) begin
            k_counter = 2'(k);
            #0.5;
            check_feed(test_name);
        end
        if (rising_edges != edges_before)
            $fatal(1, "%s: lane=N/A expected=0 rising edges during sweep actual=%0d time=%0t",
                   test_name, rising_edges - edges_before, $time);
        $display("PASS %s: all A/B lanes at k=0,1,2,3 without a rising edge", test_name);
    endtask

    task automatic load_matrix(input string test_name);
        // External matrices are prepared before this task.
        @(negedge clk);
        load = 1'b1;
        #1;
        check_feed({test_name, " retains old values before load edge"});
        @(posedge clk);
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                expected_a[i][j] = a_matrix[i][j];
                expected_b[i][j] = b_matrix[i][j];
            end
        #1; // Observe storage after nonblocking updates.
        check_feed({test_name, " captured at rising edge"});
        @(negedge clk);
        load = 1'b0;
        sweep_k(test_name);
    endtask

    initial begin
        zero_expected();
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                a_matrix[i][j] = DATA_W'(i == 3 ? -(31+j) : 10*i+j+1);
                b_matrix[i][j] = DATA_W'(i == 3 ? -(71+j) : 41+10*i+j);
            end

        // Assert reset at t=1 ns; the entire zero sweep precedes t=5 ns.
        #1 rst_n = 1'b0;
        sweep_k("initial asynchronous reset");
        @(negedge clk);
        rst_n = 1'b1;
        load_matrix("known matrices: column A and row B selection");

        // Change every external element while keeping load low.
        @(negedge clk);
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                a_matrix[i][j] = DATA_W'(-100 + 4*i+j);
                b_matrix[i][j] = DATA_W'(100 - 4*i-j);
            end
        sweep_k("hold despite changed external matrices");
        repeat (3) begin
            @(posedge clk);
            #1;
            sweep_k("load=0 storage hold across clock edges");
        end

        // Second matrices include positive, negative, zero and INT8 extremes.
        @(negedge clk);
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                a_matrix[i][j] = DATA_W'((i+j)%2 == 0 ? 80+4*i+j : -80-4*i-j);
                b_matrix[i][j] = DATA_W'((i+j)%2 == 0 ? -40-4*i-j : 40+4*i+j);
            end
        a_matrix[0][0] = 8'sh80; // -128
        a_matrix[3][3] = 8'sd127;
        b_matrix[0][0] = 8'sd0;
        b_matrix[3][3] = 8'sh80;
        load_matrix("reload replaces all stored elements");

        // Reset occupied storage between edges and check every location
        // before the next rising edge, proving asynchronous clearing.
        @(posedge clk);
        #1 rst_n = 1'b0;
        zero_expected();
        sweep_k("asynchronous reset of nonzero stored matrices");
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
        sweep_k("reset values retained with load=0");

        $display("PASS: all matrix_operand_buffer tests completed");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "timeout: lane=N/A expected=tests completed actual=still running time=%0t",
               $time);
    end
endmodule
