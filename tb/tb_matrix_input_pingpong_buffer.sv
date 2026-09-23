`timescale 1ns/1ps

// Public-port-only transaction scoreboard. No external vectors or DUT hierarchy.
module tb_matrix_input_pingpong_buffer;
    localparam integer DATA_W = 8;
    localparam integer MAX_WAIT = 40;
    logic clk = 0, rst_n = 1;
    logic in_valid = 0, compute_start = 0, compute_done = 0;
    logic signed [DATA_W-1:0] a_data = 0, b_data = 0;
    wire in_ready, matrix_ready, compute_sel;
    wire signed [DATA_W-1:0] a_matrix [0:3][0:3];
    wire signed [DATA_W-1:0] b_matrix [0:3][0:3];
    logic signed [7:0] expected_a [0:15][0:3][0:3];
    logic signed [7:0] expected_b [0:15][0:3][0:3];
    integer accepted [0:15];
    logic bank [0:15];
    integer pending [0:31];
    integer head = 0, tail = 0, active_id = -1;
    integer errors = 0, tests = 0, baseline = 0, comparisons = 0;
    string scenario;

    matrix_input_pingpong_buffer #(.DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_ready(in_ready),
        .a_data(a_data), .b_data(b_data), .matrix_ready(matrix_ready),
        .compute_start(compute_start), .compute_done(compute_done),
        .compute_sel(compute_sel), .a_matrix(a_matrix), .b_matrix(b_matrix)
    );
    always #5 clk = ~clk;

    task automatic fail(input string message);
        errors = errors + 1;
        $display("FAIL [%s] %s time=%0t", scenario, message, $time);
    endtask

    task automatic fatal_timeout(input string message);
        fail(message);
        $display("FAIL summary: tests=%0d errors=%0d comparisons=%0d", tests, errors, comparisons);
        $fatal(1, "Bounded wait expired");
    endtask

    task automatic begin_test(input string label);
        scenario = label;
        baseline = errors;
        tests = tests + 1;
    endtask

    task automatic end_test;
        if (errors == baseline) $display("PASS [%s]", scenario);
        else $display("FAIL [%s]: %0d errors", scenario, errors-baseline);
    endtask

    task automatic check_bit(input string label, input logic actual, wanted);
        if (actual !== wanted)
            fail($sformatf("%s expected=%b actual=%b", label, wanted, actual));
    endtask

    task automatic check_matrix(input integer id);
        check_bit("compute_sel", compute_sel, bank[id]);
        if (accepted[id] != 16) begin
            fail($sformatf("scoreboard matrix %0d incomplete (%0d beats)", id, accepted[id]));
        end else begin
            for (integer r = 0; r < 4; r = r + 1)
                for (integer c = 0; c < 4; c = c + 1) begin
                    comparisons = comparisons + 2;
                    if (a_matrix[r][c] !== expected_a[id][r][c])
                        fail($sformatf("matrix=%0d A row=%0d column=%0d expected=%0d actual=%0d",
                             id, r, c, expected_a[id][r][c], a_matrix[r][c]));
                    if (b_matrix[r][c] !== expected_b[id][r][c])
                        fail($sformatf("matrix=%0d B row=%0d column=%0d expected=%0d actual=%0d",
                             id, r, c, expected_b[id][r][c], b_matrix[r][c]));
                end
        end
    endtask

    task automatic check_visible;
        check_bit("matrix_ready", matrix_ready, (active_id < 0 && head < tail));
        if (in_ready !== 1'b0 && in_ready !== 1'b1) fail("in_ready contains X/Z");
        // Never inspect uninitialized or partially loaded matrix storage.
        if (active_id >= 0) check_matrix(active_id);
        else if (head < tail) check_matrix(pending[head]);
    endtask

    // All stimulus changes on falling edges. Observe handshakes BEFORE NBA,
    // then check selected matrix and control outputs AFTER NBA at +1 ns.
    // id=-1 denotes poison traffic: it must never be accepted.
    task automatic cycle(input bit valid, input integer id,
                         input bit start_cmd, input bit done_cmd);
        integer n;
        bit take_input, take_start, take_done;
        @(negedge clk);
        in_valid = valid;
        compute_start = start_cmd;
        compute_done = done_cmd;
        n = (id >= 0) ? accepted[id] : 0;
        a_data = 8'(id * 29 + n * 11 - 128);
        b_data = 8'(127 - id * 17 - n * 7);
        if (id < 0) begin a_data = 8'sd85; b_data = -8'sd86; end
        @(posedge clk);
        check_visible();
        take_input = (in_valid === 1'b1 && in_ready === 1'b1);
        take_start = (compute_start === 1'b1 && matrix_ready === 1'b1 && active_id < 0);
        take_done = (compute_done === 1'b1 && active_id >= 0);
        // Pop the old head before appending a matrix completed on this edge.
        if (take_start) begin
            if (head >= tail) fail("unexpected start with empty reference queue");
            else begin active_id = pending[head]; head = head + 1; end
        end
        if (take_done) active_id = -1;
        if (take_input) begin
            if (id < 0) fail("backpressured poison beat was accepted");
            else if (n >= 16) fail("more than 16 accepted beats for one matrix");
            else begin
                expected_a[id][n/4][n%4] = a_data;
                expected_b[id][n/4][n%4] = b_data;
                accepted[id] = n + 1;
                if (n == 15) begin
                    if (tail >= 32) $fatal(1, "Reference queue capacity exceeded");
                    pending[tail] = id;
                    tail = tail + 1;
                end
            end
        end
        #1;
        check_visible();
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst_n = 0;
        in_valid = 0; compute_start = 0; compute_done = 0;
        a_data = 0; b_data = 0;
        head = 0; tail = 0; active_id = -1;
        for (integer id = 0; id < 16; id = id + 1) begin
            accepted[id] = 0;
            bank[id] = 0;
        end
        #1; // Before the next rising edge: verify asynchronous reset.
        check_bit("reset matrix_ready", matrix_ready, 0);
        check_bit("reset in_ready", in_ready, 1);
        repeat (2) @(posedge clk);
        #1;
        check_bit("held reset matrix_ready", matrix_ready, 0);
        check_bit("held reset in_ready", in_ready, 1);
        @(negedge clk);
        rst_n = 1;
        cycle(0, -1, 0, 0);
        check_bit("released reset in_ready", in_ready, 1);
    endtask

    task automatic send_until(input integer id, input integer target);
        integer attempts;
        attempts = 0;
        while (accepted[id] < target && attempts < MAX_WAIT) begin
            cycle(1, id, 0, 0);
            attempts = attempts + 1;
        end
        if (accepted[id] != target) fatal_timeout($sformatf("input matrix %0d target=%0d accepted=%0d", id, target, accepted[id]));
    endtask

    task automatic start_matrix(input integer id);
        integer waited;
        waited = 0;
        while (matrix_ready !== 1'b1 && waited < MAX_WAIT) begin
            cycle(0, -1, 0, 0);
            waited = waited + 1;
        end
        if (matrix_ready !== 1'b1) fatal_timeout("waiting for matrix_ready");
        cycle(0, -1, 1, 0);
        if (active_id != id) fail($sformatf("FIFO order expected matrix=%0d actual=%0d", id, active_id));
        check_matrix(id);
    endtask

    task automatic finish_matrix;
        if (active_id < 0) fail("finish requested without active computation");
        cycle(0, -1, 0, 1);
    endtask

    initial begin
        begin_test("1 reset");
        reset_dut();
        end_test();

        begin_test("2 single matrix load");
        bank[0] = 0;
        send_until(0, 16);
        check_bit("complete matrix ready", matrix_ready, 1);
        start_matrix(0);
        finish_matrix();
        cycle(0, -1, 0, 0);
        end_test();

        begin_test("3 input pause");
        reset_dut();
        bank[1] = 0;
        send_until(1, 6);
        repeat (4) cycle(0, -1, 0, 0);
        if (accepted[1] != 6) fail("accepted count advanced while in_valid=0");
        check_bit("partial matrix not ready", matrix_ready, 0);
        send_until(1, 16);
        start_matrix(1);
        finish_matrix();
        end_test();

        begin_test("4 ping-pong overlap");
        reset_dut();
        bank[2] = 0; bank[3] = 1;
        send_until(2, 16);
        start_matrix(2);
        // check_visible verifies all 32 active elements on every input edge.
        send_until(3, 16);
        check_bit("active computation masks matrix_ready", matrix_ready, 0);
        check_matrix(2);
        end_test();

        begin_test("5 backpressure preserves both matrices");
        check_bit("both banks occupied", in_ready, 0);
        repeat (4) begin
            cycle(1, -1, 0, 0);
            check_bit("backpressure maintained", in_ready, 0);
        end
        finish_matrix();
        start_matrix(3); // Verifies waiting bank was not overwritten by poison.
        finish_matrix();
        end_test();

        begin_test("6 FIFO completion ordering");
        reset_dut();
        bank[4] = 0; bank[5] = 1;
        send_until(4, 16);
        send_until(5, 16);
        check_bit("two queued banks backpressure", in_ready, 0);
        cycle(1, -1, 0, 0);
        start_matrix(4);
        // Concurrent done/start must only release; start cannot hand off.
        cycle(0, -1, 1, 1);
        if (active_id != -1) fail("same-edge done/start unexpectedly handed off");
        check_bit("next matrix waits after done", matrix_ready, 1);
        start_matrix(5);
        finish_matrix();
        check_bit("queue drained", matrix_ready, 0);
        end_test();

        begin_test("7 simultaneous FIFO push/pop");
        reset_dut();
        bank[6] = 0; bank[7] = 1;
        send_until(6, 16);
        send_until(7, 15);
        check_bit("final beat ready", in_ready, 1);
        check_bit("first matrix ready", matrix_ready, 1);
        cycle(1, 7, 1, 0);
        if (accepted[7] != 16 || active_id != 6)
            fail("simultaneous final beat and compute_start did not both occur");
        check_matrix(6);
        finish_matrix();
        start_matrix(7);
        finish_matrix();
        check_bit("both matrices consumed", matrix_ready, 0);
        end_test();

        begin_test("8 bank reuse while other bank computes");
        reset_dut();
        bank[8] = 0; bank[9] = 1; bank[10] = 0;
        send_until(8, 16);
        start_matrix(8);
        send_until(9, 16);
        finish_matrix();
        check_bit("released bank ready for input", in_ready, 1);
        start_matrix(9);
        send_until(10, 16);
        finish_matrix();
        start_matrix(10);
        finish_matrix();
        end_test();

        begin_test("9 reset during partial load");
        reset_dut();
        bank[11] = 0;
        send_until(11, 7);
        reset_dut();
        repeat (3) cycle(0, -1, 0, 0);
        check_bit("discarded partial matrix not ready", matrix_ready, 0);
        bank[12] = 0;
        send_until(12, 15);
        check_bit("new load needs all 16 beats", matrix_ready, 0);
        send_until(12, 16);
        start_matrix(12);
        finish_matrix();
        cycle(0, -1, 0, 0);
        check_bit("no stale queued matrix", matrix_ready, 0);
        end_test();

        if (errors != 0) begin
            $display("FAIL summary: tests=%0d errors=%0d comparisons=%0d", tests, errors, comparisons);
            $fatal(1, "Ping-pong buffer self-check failed");
        end
        $display("PASS summary: tests=%0d errors=0 comparisons=%0d", tests, comparisons);
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL summary: global timeout tests=%0d errors=%0d", tests, errors+1);
        $fatal(1, "Global watchdog expired");
    end
endmodule
