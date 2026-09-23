`timescale 1ns/1ps

// Standalone public-port test. No UVM, DPI, vector files, or hierarchical reads.
module tb_accelerator_4x4_top_v2;
    localparam integer MAX_MATRICES = 64;
    localparam integer WAIT_LIMIT = 64;
    logic clk = 0, rst_n = 1, in_valid = 0;
    logic signed [7:0] a_data = 0, b_data = 0;
    wire in_ready, busy, done;
    wire signed [31:0] c_out [0:3][0:3];

    logic signed [7:0] stimulus_a [0:3][0:3];
    logic signed [7:0] stimulus_b [0:3][0:3];
    logic signed [7:0] captured_a [0:3][0:3];
    logic signed [7:0] captured_b [0:3][0:3];
    logic signed [63:0] expected [0:MAX_MATRICES-1][0:3][0:3];
    integer queued_at [0:MAX_MATRICES-1];
    integer head = 0, tail = 0, partial = 0, active_id = -1;
    typedef enum logic [1:0] {
        REF_EMPTY, REF_LOADING, REF_FULL, REF_COMPUTING
    } ref_bank_state_t;
    ref_bank_state_t ref_bank_state [0:1];
    integer ref_bank_beats [0:1];
    integer ref_bank_for_id [0:MAX_MATRICES-1];
    bit ref_write_sel = 0;
    integer ref_active_bank = -1;
    bit ref_released [0:1];
    integer loading_compute_checks = 0, blocked_bank_checks = 0;
    integer release_checks = 0, reused_bank_beats = 0, held_beat_checks = 0;
    bit hold_pending = 0;
    logic signed [7:0] held_a, held_b;
    // -1 = idle. 0..10 = busy; 11 = DONE. The next edge releases the
    // bank and returns to idle; it cannot start another operation yet.
    integer age = -1;
    integer last_result = -1;
    integer cycles = 0, errors = 0, tests = 0, baseline = 0;
    integer results = 0, epoch_results = 0, element_checks = 0;
    integer overlap_beats = 0, stalled_beats = 0, accepted_beats = 0;
    bit result_held = 0;
    string scenario;

    accelerator_4x4_top_v2 #(.DATA_W(8), .ACC_W(32)) dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_ready(in_ready),
        .a_data(a_data), .b_data(b_data), .busy(busy), .done(done), .c_out(c_out)
    );
    always #5 clk = ~clk;

    task automatic fail(input string message);
        errors = errors + 1;
        $display("FAIL [%s] %s time=%0t", scenario, message, $time);
    endtask

    task automatic stop_failure(input string message);
        fail(message);
        $display("FAIL summary: tests=%0d results=%0d errors=%0d checks=%0d",
                 tests, results, errors, element_checks);
        $fatal(1, "End-to-end verification failed");
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
            fail($sformatf("%s expected=%b actual=%b cycle=%0d", label, wanted, actual, cycles));
    endtask

    // Pure bank-selection rule. -1 means no bank is writable. The fallback
    // is EMPTY only: a partial matrix must stay on the selected write bank.
    // No DUT signal participates in this prediction.
    function automatic integer write_bank_choice(
        input ref_bank_state_t bank0, bank1, input bit write_sel
    );
        ref_bank_state_t current_bank, other_bank;
        current_bank = write_sel ? bank1 : bank0;
        other_bank = write_sel ? bank0 : bank1;
        if (current_bank == REF_LOADING || current_bank == REF_EMPTY)
            write_bank_choice = write_sel ? 1 : 0;
        else if (other_bank == REF_EMPTY)
            write_bank_choice = write_sel ? 0 : 1;
        else write_bank_choice = -1;
    endfunction

    task automatic check_bank_model(input string phase);
        integer selected, full_count, computing_count, loading_count;
        selected = write_bank_choice(ref_bank_state[0], ref_bank_state[1], ref_write_sel);
        check_bit($sformatf("%s in_ready banks=%0d/%0d write=%b partial=%0d",
                  phase, ref_bank_state[0], ref_bank_state[1], ref_write_sel, partial),
                  in_ready, (rst_n && selected >= 0));
        full_count = 0; computing_count = 0; loading_count = 0;
        for (integer b = 0; b < 2; b = b + 1) begin
            case (ref_bank_state[b])
                REF_EMPTY: begin
                    if (ref_bank_beats[b] != 0) fail("reference EMPTY bank has accepted beats");
                end
                REF_LOADING: begin
                    loading_count = loading_count + 1;
                    if (ref_bank_beats[b] < 1 || ref_bank_beats[b] > 15 ||
                        ref_bank_beats[b] != partial || b != int'(ref_write_sel))
                        fail("reference partial count/write selection inconsistent");
                end
                REF_FULL: begin
                    full_count = full_count + 1;
                    if (ref_bank_beats[b] != 16) fail("reference FULL bank is incomplete");
                end
                REF_COMPUTING: begin
                    computing_count = computing_count + 1;
                    if (ref_bank_beats[b] != 16 || ref_active_bank != b)
                        fail("reference COMPUTING bank ownership inconsistent");
                end
                default: fail("unknown reference bank state");
            endcase
        end
        if (full_count != tail-head || computing_count != int'(active_id >= 0) ||
            loading_count != int'(partial > 0) || loading_count > 1)
            fail("reference bank states disagree with transaction scoreboard");
        if (active_id < 0) begin
            if (ref_active_bank != -1) fail("reference active bank without active transaction");
        end else if (ref_active_bank != ref_bank_for_id[active_id])
            fail("reference active transaction/bank mapping inconsistent");
        for (integer id = head; id < tail; id = id + 1)
            if (ref_bank_state[ref_bank_for_id[id]] != REF_FULL)
                fail("queued reference matrix does not own a FULL bank");

        if (computing_count == 1 && loading_count == 1) begin
            loading_compute_checks = loading_compute_checks + 1;
            check_bit({phase, " COMPUTING plus LOADING stays writable"}, in_ready, 1);
        end
        if (full_count + computing_count == 2) begin
            blocked_bank_checks = blocked_bank_checks + 1;
            check_bit({phase, " two occupied banks backpressure"}, in_ready, 0);
        end
    endtask

    // These checks exercise the reference selector only, including states
    // unreachable through this top's faster-than-input automatic scheduler.
    // They are deliberately NOT counted as DUT backpressure coverage.
    task automatic check_write_choice(
        input ref_bank_state_t bank0, bank1, input bit write_sel,
        input integer wanted, input string label
    );
        integer actual;
        actual = write_bank_choice(bank0, bank1, write_sel);
        if (actual != wanted)
            fail($sformatf("reference selector %s expected=%0d actual=%0d", label, wanted, actual));
    endtask

    task automatic check_reference_selector;
        check_write_choice(REF_EMPTY, REF_EMPTY, 0, 0, "reset write preference");
        check_write_choice(REF_EMPTY, REF_EMPTY, 1, 1, "retain empty write preference");
        check_write_choice(REF_LOADING, REF_COMPUTING, 0, 0, "continue bank 0 partial");
        check_write_choice(REF_COMPUTING, REF_LOADING, 1, 1, "continue bank 1 partial");
        check_write_choice(REF_LOADING, REF_FULL, 0, 0, "partial plus queued full");
        check_write_choice(REF_FULL, REF_LOADING, 1, 1, "queued full plus partial");
        check_write_choice(REF_FULL, REF_EMPTY, 0, 1, "switch from full to empty");
        check_write_choice(REF_EMPTY, REF_COMPUTING, 1, 0, "switch from computing to empty");
        for (integer ws = 0; ws < 2; ws = ws + 1) begin
            check_write_choice(REF_FULL, REF_FULL, (ws != 0), -1, "both full");
            check_write_choice(REF_FULL, REF_COMPUTING, (ws != 0), -1, "full/computing");
            check_write_choice(REF_COMPUTING, REF_FULL, (ws != 0), -1, "computing/full");
            check_write_choice(REF_COMPUTING, REF_COMPUTING, (ws != 0), -1, "both computing (selector only)");
        end
        // After releasing the computing bank, only the next edge can use it.
        check_write_choice(REF_FULL, REF_EMPTY, 0, 1, "bank 1 released");
        check_write_choice(REF_EMPTY, REF_FULL, 1, 0, "bank 0 released");
    endtask

    // Widen operands before multiplying. No DUT-dependent arithmetic.
    task automatic reference_matmul(input integer id);
        logic signed [63:0] lhs, rhs, sum;
        for (integer r = 0; r < 4; r = r + 1)
            for (integer c = 0; c < 4; c = c + 1) begin
                sum = 64'sd0;
                for (integer k = 0; k < 4; k = k + 1) begin
                    lhs = {{56{captured_a[r][k][7]}}, captured_a[r][k]};
                    rhs = {{56{captured_b[k][c][7]}}, captured_b[k][c]};
                    sum = sum + lhs * rhs;
                end
                expected[id][r][c] = sum;
            end
    endtask

    task automatic check_result(input integer id, input bit zero, input string phase);
        logic signed [63:0] actual, wanted;
        for (integer r = 0; r < 4; r = r + 1)
            for (integer c = 0; c < 4; c = c + 1) begin
                actual = {{32{c_out[r][c][31]}}, c_out[r][c]};
                wanted = 64'sd0;
                if (!zero) wanted = expected[id][r][c];
                element_checks = element_checks + 1;
                if (actual !== wanted)
                    fail($sformatf("%s matrix=%0d row=%0d column=%0d expected=%0d actual=%0d hex=%h",
                         phase, id, r, c, wanted, actual, actual));
            end
    endtask

    // This task owns each non-reset clock cycle. Scheduling is predicted
    // solely from accepted complete matrices and the reviewed RTL latency;
    // it is NOT advanced from actual busy/done or internal DUT state.
    task automatic cycle(input bit valid,
                         input logic signed [7:0] av, bv,
                         output bit accepted);
        bit was_busy;
        integer write_bank, start_bank, release_bank;
        @(negedge clk);
        in_valid = valid;
        a_data = av;
        b_data = bv;
        @(posedge clk);
        cycles = cycles + 1;
        check_bank_model("pre-edge");
        // Snapshot every event target before changing any reference state.
        // A bank released on this edge cannot accept this edge's input.
        write_bank = write_bank_choice(ref_bank_state[0], ref_bank_state[1], ref_write_sel);
        start_bank = -1;
        release_bank = -1;
        if (age < 0 && head < tail) start_bank = ref_bank_for_id[head];
        if (age == 11) release_bank = ref_active_bank;
        if (hold_pending) begin
            held_beat_checks = held_beat_checks + 1;
            if (in_valid !== 1'b1 || a_data !== held_a || b_data !== held_b)
                fail("unaccepted input beat changed before a valid handshake");
        end
        accepted = (in_valid === 1'b1 && in_ready === 1'b1);
        // Observed acceptance updates input history only. Actual ready,
        // busy, and done never select banks or predict compute events.
        hold_pending = (in_valid === 1'b1 && !accepted);
        if (hold_pending) begin held_a = a_data; held_b = b_data; end
        was_busy = (age >= 0 && age <= 10);
        if (valid && in_ready === 1'b0) stalled_beats = stalled_beats + 1;
        if (accepted && was_busy) overlap_beats = overlap_beats + 1;

        if (start_bank >= 0 && ref_bank_state[start_bank] != REF_FULL)
            stop_failure("predicted start does not own a FULL bank");
        if (release_bank >= 0 && ref_bank_state[release_bank] != REF_COMPUTING)
            stop_failure("predicted release does not own a COMPUTING bank");
        if (accepted) begin
            if (write_bank < 0)
                stop_failure("DUT accepted input while reference has no writable bank");
            if (write_bank == start_bank || write_bank == release_bank)
                stop_failure("input and computation targeted the same pre-edge bank");
            if (ref_bank_beats[write_bank] != partial)
                stop_failure("accepted beat index disagrees with write-bank progress");
            if (ref_released[write_bank]) begin
                reused_bank_beats = reused_bank_beats + 1;
                ref_released[write_bank] = 0;
            end
            ref_write_sel = (write_bank == 1);
            ref_bank_beats[write_bank] = ref_bank_beats[write_bank] + 1;
            if (ref_bank_beats[write_bank] == 16) ref_bank_state[write_bank] = REF_FULL;
            else ref_bank_state[write_bank] = REF_LOADING;
        end
        if (start_bank >= 0) begin
            ref_bank_state[start_bank] = REF_COMPUTING;
            ref_active_bank = start_bank;
        end
        if (release_bank >= 0) begin
            ref_bank_state[release_bank] = REF_EMPTY;
            ref_bank_beats[release_bank] = 0;
            ref_released[release_bank] = 1;
            ref_active_bank = -1;
        end

        // Consume only a matrix completed BEFORE this edge. An empty FIFO
        // cannot start on the same edge as its first completion is appended.
        if (age < 0) begin
            if (head < tail) begin
                active_id = head;
                head = head + 1;
                age = 0;
            end
        end else if (age == 11) begin
            age = -1;
            active_id = -1;
        end else age = age + 1;

        if (accepted) begin
            accepted_beats = accepted_beats + 1;
            captured_a[partial/4][partial%4] = a_data;
            captured_b[partial/4][partial%4] = b_data;
            if (partial == 15) begin
                if (tail >= MAX_MATRICES) stop_failure("reference queue capacity exceeded");
                reference_matmul(tail);
                ref_bank_for_id[tail] = write_bank;
                queued_at[tail] = cycles;
                tail = tail + 1;
                partial = 0;
            end else partial = partial + 1;
        end

        #1; // Wait for accumulator/state NBA updates and combinational decode.
        check_bit("busy", busy, (age >= 0 && age <= 10));
        check_bit("done", done, (age == 11));
        check_bank_model("post-edge");
        if (release_bank >= 0) begin
            release_checks = release_checks + 1;
            check_bit("released bank makes input capacity available after edge", in_ready, 1);
        end
        if (age == 1) begin
            check_result(-1, 1, "CLEAR applied before first feed");
            result_held = 0;
        end
        if (age == 11) begin
            check_result(active_id, 0, "DONE ordered result");
            if (done !== 1'b1) stop_failure("operation did not complete at E11");
            results = results + 1;
            epoch_results = epoch_results + 1;
            last_result = active_id;
            result_held = 1;
        end else if (result_held) begin
            check_result(last_result, 0, "result retained until next CLEAR");
        end
        if (active_id >= 0)
            if (cycles - queued_at[active_id] > WAIT_LIMIT)
                stop_failure("active operation timeout");
        if (head < tail)
            if (cycles - queued_at[head] > WAIT_LIMIT)
                stop_failure("queued operation timeout");
    endtask

    task automatic idle_cycles(input integer count);
        bit ignored;
        for (integer n = 0; n < count; n = n + 1)
            cycle(0, 8'sd91, -8'sd73, ignored);
    endtask

    task automatic send_beat(input logic signed [7:0] av, bv);
        integer waited;
        bit accepted;
        waited = 0;
        accepted = 0;
        // Hold the same payload until the rising-edge handshake accepts it.
        while (!accepted && waited < WAIT_LIMIT) begin
            cycle(1, av, bv, accepted);
            waited = waited + 1;
        end
        if (!accepted) stop_failure("input acceptance timeout");
    endtask

    task automatic send_matrix(input bit insert_pauses);
        for (integer n = 0; n < 16; n = n + 1) begin
            if (insert_pauses && (n == 3 || n == 9 || n == 15)) idle_cycles(3);
            send_beat(stimulus_a[n/4][n%4], stimulus_b[n/4][n%4]);
        end
    endtask

    task automatic drain;
        integer waited;
        waited = 0;
        if (partial != 0) stop_failure("drain called with an incomplete stimulus matrix");
        while ((age >= 0 || head < tail || busy !== 1'b0 || done !== 1'b0)
               && waited < WAIT_LIMIT) begin
            idle_cycles(1);
            waited = waited + 1;
        end
        if (waited >= WAIT_LIMIT) stop_failure("completion drain timeout");
        if (epoch_results != tail)
            fail($sformatf("result count expected=%0d actual=%0d", tail, epoch_results));
        idle_cycles(3); // Detect duplicate/late done pulses and idle corruption.
    endtask

    task automatic reset_dut;
        @(negedge clk);
        rst_n = 0;
        // Valid poison during reset must not be advertised as accepted.
        in_valid = 1; a_data = 8'sd127; b_data = -8'sd128;
        head = 0; tail = 0; partial = 0; active_id = -1; age = -1;
        epoch_results = 0; result_held = 0; last_result = -1;
        ref_write_sel = 0; ref_active_bank = -1; hold_pending = 0;
        for (integer b = 0; b < 2; b = b + 1) begin
            ref_bank_state[b] = REF_EMPTY;
            ref_bank_beats[b] = 0;
            ref_released[b] = 0;
        end
        #1;
        check_bit("asynchronous reset busy", busy, 0);
        check_bit("asynchronous reset done", done, 0);
        check_bit("reset masks in_ready", in_ready, 0);
        check_result(-1, 1, "asynchronous reset output");
        repeat (2) @(posedge clk);
        #1;
        check_bit("held reset busy", busy, 0);
        check_bit("held reset done", done, 0);
        check_bit("held reset in_ready", in_ready, 0);
        check_result(-1, 1, "held reset output");
        @(negedge clk);
        in_valid = 0; a_data = 0; b_data = 0;
        rst_n = 1;
        // No accepted input at the intervening rising edge.
        idle_cycles(2);
        check_result(-1, 1, "reset released output");
    endtask

    task automatic make_pattern(input integer pattern);
        for (integer r = 0; r < 4; r = r + 1)
            for (integer c = 0; c < 4; c = c + 1) begin
                case (pattern)
                    0: begin // Left identity, asymmetric signed B.
                        stimulus_a[r][c] = (r == c) ? 1 : 0;
                        stimulus_b[r][c] = 8'(r*23-c*9-17);
                    end
                    1: begin // Right identity catches indexing/transposition.
                        stimulus_a[r][c] = 8'(r*11+c*17-37);
                        stimulus_b[r][c] = (r == c) ? 1 : 0;
                    end
                    2: begin
                        stimulus_a[r][c] = 0;
                        stimulus_b[r][c] = 8'(r*13-c*7);
                    end
                    3: begin
                        stimulus_a[r][c] = 8'(r*9+c+1);
                        stimulus_b[r][c] = 8'(r+c*7+2);
                    end
                    4: begin
                        stimulus_a[r][c] = 8'((r+c)%2 ? -(r*13+c+1) : r*13+c+1);
                        stimulus_b[r][c] = 8'((r+c)%3 ? r-c*11-5 : r*7+c+3);
                    end
                    5: begin stimulus_a[r][c] = -128; stimulus_b[r][c] = -128; end
                    6: begin stimulus_a[r][c] = -128; stimulus_b[r][c] = 127; end
                    7: begin stimulus_a[r][c] = 127; stimulus_b[r][c] = 127; end
                    8: begin
                        stimulus_a[r][c] = (r+c)%3 ? 127 : -128;
                        stimulus_b[r][c] = (r*2+c)%3 ? -128 : 127;
                    end
                    9: begin stimulus_a[r][c] = 8'(r*9-c*7+1); stimulus_b[r][c] = 0; end
                    default: begin // Repeatable non-symmetric INT8 patterns.
                        stimulus_a[r][c] = 8'(pattern*29+r*41+c*17);
                        stimulus_b[r][c] = 8'(pattern*13-r*19+c*37);
                    end
                endcase
            end
    endtask

    initial begin
        begin_test("reference bank selector checks (not DUT stimulus)");
        check_reference_selector();
        end_test();

        begin_test("reset and idle");
        reset_dut();
        idle_cycles(16);
        end_test();

        for (integer pattern = 0; pattern < 10; pattern = pattern + 1) begin
            begin_test($sformatf("directed arithmetic pattern %0d", pattern));
            make_pattern(pattern);
            send_matrix(0);
            drain();
            end_test();
        end

        begin_test("input pauses preserve row-major grouping");
        make_pattern(12);
        send_matrix(1);
        drain();
        end_test();

        begin_test("continuous stream / overlap / repeated bank reuse / result order");
        // No invalid cycles at matrix boundaries: eight matrices in 128
        // accepted cycles when the implementation sustains its input rate.
        for (integer pattern = 16; pattern < 24; pattern = pattern + 1) begin
            make_pattern(pattern);
            send_matrix(0);
        end
        drain();
        if (overlap_beats == 0) fail("coverage missing: input accepted while computing");
        if (loading_compute_checks == 0) fail("coverage missing: COMPUTING plus LOADING ready check");
        if (release_checks == 0 || reused_bank_beats == 0)
            fail("coverage missing: bank release followed by accepted reuse");
        end_test();

        begin_test("reset discards a partial input matrix");
        make_pattern(24);
        for (integer n = 0; n < 7; n = n + 1)
            send_beat(stimulus_a[n/4][n%4], stimulus_b[n/4][n%4]);
        if (partial != 7) fail("partial-reset setup did not accept seven beats");
        reset_dut();
        idle_cycles(16); // No completion from the abandoned prefix.
        make_pattern(25);
        send_matrix(0);
        drain();
        end_test();

        begin_test("reset aborts FEED and overlapped partial input");
        make_pattern(26);
        send_matrix(0);
        make_pattern(27);
        for (integer n = 0; n < 4; n = n + 1)
            send_beat(stimulus_a[n/4][n%4], stimulus_b[n/4][n%4]);
        if (busy !== 1'b1 || age != 3 || partial != 4)
            fail("active-reset setup did not reach FEED with four pending input beats");
        reset_dut();
        idle_cycles(16); // Old compute must not produce a stale done pulse.
        make_pattern(28);
        send_matrix(0);
        drain();
        end_test();

        begin_test("reset aborts DRAIN and recovery computes correctly");
        make_pattern(29);
        send_matrix(0);
        idle_cycles(8); // E7: drain in progress, before E11 completion.
        if (busy !== 1'b1 || age != 7) fail("drain-reset setup did not reach E7");
        reset_dut();
        idle_cycles(16);
        make_pattern(30);
        send_matrix(1);
        drain();
        end_test();

        // 10 directed + 1 paused + 8 continuous + 3 recovery results.
        if (results != 22) fail($sformatf("total result count expected=22 actual=%0d", results));
        if (errors != 0) stop_failure("one or more checks failed");
        $display("COVERAGE: computing/loading=%0d occupied-bank-backpressure=%0d releases=%0d accepted-reuses=%0d held-beat-retries=%0d",
                 loading_compute_checks, blocked_bank_checks, release_checks, reused_bank_beats, held_beat_checks);
        if (blocked_bank_checks == 0)
            $display("NOT EXERCISED on DUT: full-bank backpressure; automatic compute releases banks before the next 16-beat pair completes.");
        if (held_beat_checks == 0)
            $display("NOT EXERCISED on DUT: stalled-beat retry; hold-until-handshake checker is installed but no input stall occurred.");
        $display("PASS summary: tests=%0d results=%0d errors=0 element_checks=%0d accepted_beats=%0d overlap_beats=%0d stalled_beats=%0d",
                 tests, results, element_checks, accepted_beats, overlap_beats, stalled_beats);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL summary: watchdog tests=%0d results=%0d errors=%0d", tests, results, errors+1);
        $fatal(1, "Global timeout");
    end
endmodule
