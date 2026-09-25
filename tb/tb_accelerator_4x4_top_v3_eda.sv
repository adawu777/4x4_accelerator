`timescale 1ns/1ps

module tb_accelerator_4x4_top_v3;
    logic clk = 0, rst_n = 1, in_valid = 0, out_ready = 0;
    logic signed [7:0] a_data = 0, b_data = 0;
    wire in_ready, out_valid, busy, done;
    wire signed [31:0] c_out [0:3][0:3];
    wire signed [31:0] out_matrix [0:3][0:3];
    accelerator_4x4_top_v3 dut (.*);
    always #5 clk = ~clk;

    // Independent transaction/bank/timing model. Only accepted input events
    // and public output transfers affect the transaction scoreboard. Internal
    // reads below check protection/control; they never drive the model.
    localparam int EMPTY=0, LOADING=1, FULL=2, COMPUTING=3;
    integer va[0:127][0:15], vb[0:127][0:15], vc[0:127][0:15];
    integer vectors;
    integer bank[0:1], bank_id[0:1], pref=0, partial=0, partial_id=-1;
    integer queue_bank[0:4095], qhead=0, qtail=0;
    integer expected_ids[0:4095], sent=0, received=0;
    integer age=-1, active_id=-1, active_bank=-1, output_id=-1;
    bit full=0, held=0;
    logic signed [7:0] held_a, held_b;
    integer cycles=0, results=0, copies=0, resets=0;
    integer completions=0, expected_completions=0, observed_completions=0;
    integer overlap_load=0, overlap_output=0, stalled_input=0;
    integer triple_overlap=0, done_blocked=0;
    integer ownership_checks=0;
    integer pending_stalls=0, replacements=0, push_pop=0;
    integer capture_empty_not_ready=0, consume_only=0, reused=0;
    integer state_resets[0:4];
    bit released[0:1];
    logic signed [31:0] output_snapshot[0:15];
    logic [31:0] random_state=32'hfacade31;

    function automatic integer writable;
        if (bank[pref] == EMPTY || bank[pref] == LOADING) writable=pref;
        else if (bank[1-pref] == EMPTY) writable=1-pref;
        else writable=-1;
    endfunction

    task automatic check_matrix(input integer id);
        // Numerical registered-output comparisons occur ONLY on a handshake.
        for (integer n=0; n<16; n=n+1) begin
            if (out_matrix[n/4][n%4] !== vc[id][n])
                $fatal(1, "cycle=%0d id=%0d element=%0d expected=%0d actual=%0d",
                       cycles, id, n, vc[id][n], out_matrix[n/4][n%4]);
        end
    endtask

    task automatic check_reset_data;
        for (integer n=0; n<16; n++)
            if (c_out[n/4][n%4] !== 32'sd0 || out_matrix[n/4][n%4] !== 32'sd0)
                $fatal(1, "reset live/registered output not zero");
    endtask

    task automatic check_ports;
        // The model selects banks independently; these internal reads are
        // assertion targets only. Check protected contents before and after
        // every edge so a FULL/ACTIVE overwrite cannot hide until execution.
        for (integer b=0; b<2; b++) begin
            if (int'(dut.u_input_buffer.state[b]) !== bank[b])
                $fatal(1, "bank ownership mismatch bank=%0d cycle=%0d", b, cycles);
            if (bank[b] == FULL || bank[b] == COMPUTING) begin
                ownership_checks++;
                for (integer n=0; n<16; n++) begin
                    if (dut.u_input_buffer.a_buf[b][n/4][n%4] !== 8'(va[bank_id[b]][n]) ||
                        dut.u_input_buffer.b_buf[b][n/4][n%4] !== 8'(vb[bank_id[b]][n]))
                        $fatal(1, "protected bank changed bank=%0d element=%0d cycle=%0d", b, n, cycles);
                end
            end
        end
        if (int'(dut.u_input_buffer.fifo_count) !== qtail-qhead ||
            int'(dut.u_input_buffer.write_count) !== partial)
            $fatal(1, "input queue/partial count mismatch cycle=%0d", cycles);
        if (in_ready !== (writable() >= 0)) $fatal(1, "input bank ownership/ready cycle %0d", cycles);
        if (busy !== (age >= 0)) $fatal(1, "busy age=%0d cycle=%0d", age, cycles);
        if (out_valid !== full) $fatal(1, "output valid cycle=%0d", cycles);
        // Stability is checked against a snapshot, not the golden output.
        // This also checks invalid retention and independence from CLEAR.
        for (integer n=0; n<16; n++) begin
            if (out_matrix[n/4][n%4] !== output_snapshot[n])
                $fatal(1, "registered payload changed without capture element=%0d", n);
            if (age == 1 && c_out[n/4][n%4] !== 32'sd0)
                $fatal(1, "legacy live c_out did not clear at E1");
        end
        if (dut.acc_result_valid !== (age == 11))
            $fatal(1, "acc_result_valid timing age=%0d", age);
        if (dut.clear_acc !== (age == 0) ||
            dut.feed_valid !== (age >= 1 && age <= 4))
            $fatal(1, "clear/feed timing age=%0d", age);
        if (age >= 1 && age <= 4 && dut.k_counter !== 2'(age-1))
            $fatal(1, "k timing age=%0d", age);
        if (age == 11) begin
            if (dut.compute_start || dut.clear_acc || dut.feed_valid)
                $fatal(1, "pending accumulator protection violated");
            for (integer n=0; n<16; n=n+1)
                if (c_out[n/4][n%4] !== vc[active_id][n])
                    $fatal(1, "pending/final-drain accumulator id=%0d element=%0d", active_id, n);
        end
    endtask

    task automatic step(input bit valid, input integer id, beat,
                        input bit ready, output bit accepted);
        integer wb, sb;
        bit start_event, release_event, capture_event, consume_event;
        @(negedge clk);
        in_valid=valid;
        a_data=valid ? 8'(va[id][beat]) : 8'sd91;
        b_data=valid ? 8'(vb[id][beat]) : -8'sd73;
        out_ready=ready;
        @(posedge clk);
        cycles=cycles+1;
        check_ports();
        wb=writable();
        accepted=valid && in_ready;
        start_event=(age == -1 && qhead < qtail);
        release_event=(age == 10);
        capture_event=(age == 11 && (!full || ready));
        consume_event=(full && ready);
        sb=start_event ? queue_bank[qhead] : -1;
        if (dut.compute_start !== start_event || dut.compute_done !== release_event ||
            dut.result_capture !== capture_event) $fatal(1, "control event timing cycle=%0d age=%0d", cycles, age);
        if (held && (!valid || a_data !== held_a || b_data !== held_b))
            $fatal(1, "test producer failed hold-until-accepted");
        held=valid && !accepted; held_a=a_data; held_b=b_data;
        if (held) stalled_input++;
        if (accepted && age >= 0 && age < 11) overlap_load++;
        if (full && age >= 0 && age < 11) overlap_output++;
        if (accepted && consume_event && age >= 0 && age < 11) triple_overlap++;
        if (release_event && full && !ready) done_blocked++;
        if (age == 11 && !capture_event) pending_stalls++;
        if (consume_event) begin
            if (received >= sent || output_id != expected_ids[received])
                $fatal(1, "duplicate or reordered result cycle=%0d", cycles);
            check_matrix(expected_ids[received]);
            received++; results++; full=0;
            if (!capture_event) consume_only++;
        end
        if (capture_event) begin
            if (consume_event) replacements++;
            if (!out_valid && !ready) capture_empty_not_ready++;
            output_id=active_id; full=1; copies++;
        end
        if (release_event) begin
            if (expected_completions >= sent || active_id != expected_ids[expected_completions])
                $fatal(1, "completed computation transaction ordering");
            expected_completions++;
            if (bank[active_bank] != COMPUTING) $fatal(1, "release without ownership");
            bank[active_bank]=EMPTY; released[active_bank]=1;
        end
        if (start_event) begin
            if (bank[sb] != FULL) $fatal(1, "start incomplete bank");
            active_bank=sb; active_id=bank_id[sb];
            bank[sb]=COMPUTING; qhead++; age=0;
        end else if (capture_event) begin
            active_id=-1; active_bank=-1; age=-1;
        end else if (age >= 0 && age < 11) age++;

        if (accepted) begin
            if (wb < 0 || wb == sb || (bank[wb] != EMPTY && bank[wb] != LOADING))
                $fatal(1, "write to owned bank");
            if (beat != partial || (partial > 0 && partial_id != id))
                $fatal(1, "test stimulus grouping mismatch");
            if (released[wb]) begin reused++; released[wb]=0; end
            partial_id=id; pref=wb;
            if (partial == 15) begin
                if (qtail >= 4096 || sent >= 4096) $fatal(1, "scoreboard overflow");
                bank[wb]=FULL; bank_id[wb]=id;
                queue_bank[qtail]=wb; qtail++;
                expected_ids[sent]=id; sent++; partial=0; partial_id=-1;
                if (start_event) push_pop++;
            end else begin bank[wb]=LOADING; partial++; end
        end
        #1;
        if (done !== release_event) $fatal(1, "done must pulse exactly once at E11, independent of output readiness");
        if (done) begin observed_completions++; completions++; end
        if (observed_completions != expected_completions)
            $fatal(1, "missing or repeated completion pulse");
        if (capture_event)
            for (integer n=0; n<16; n++) output_snapshot[n]=out_matrix[n/4][n%4];
        check_ports();
    endtask

    task automatic idle(input integer count, input bit ready);
        bit accepted;
        repeat(count) step(0, 0, 0, ready, accepted);
    endtask

    task automatic send_beat(input integer id, beat, input bit ready);
        bit accepted;
        integer waited;
        accepted=0; waited=0;
        while (!accepted && waited < 200) begin
            step(1, id, beat, ready, accepted); waited++;
        end
        if (!accepted) $fatal(1, "input wait timeout");
    endtask

    task automatic send_matrix(input integer id, input bit ready, pauses);
        for (integer n=0; n<16; n++) begin
            if (pauses && n%5 == 3) idle(3, ready);
            send_beat(id, n, ready);
        end
    endtask

    task automatic drain;
        integer waited;
        waited=0;
        while ((received < sent || age >= 0 || full) && waited < 1000) begin
            idle(1, 1); waited++;
        end
        if (received != sent || observed_completions != sent || age >= 0 || full || partial != 0)
            $fatal(1, "drain timeout/lost transaction");
        idle(20, 1); // Detect late/duplicate output or spurious execution.
    endtask

    task automatic reset_dut;
        // Off-edge asynchronous reset, even when a transfer was presented.
        @(negedge clk);
        in_valid=1; out_ready=1; a_data=127; b_data=-128;
        #2; rst_n=0;
        if (age == -1) state_resets[0]++;
        else if (age == 0) state_resets[1]++;
        else if (age <= 4) state_resets[2]++;
        else if (age <= 10) state_resets[3]++;
        else state_resets[4]++;
        age=-1; active_id=-1; active_bank=-1; output_id=-1; full=0;
        qhead=0; qtail=0; sent=0; received=0; partial=0; partial_id=-1;
        expected_completions=0; observed_completions=0;
        pref=0; held=0;
        for (integer n=0; n<16; n++) output_snapshot[n]=0;
        for (integer b=0; b<2; b++) begin
            bank[b]=EMPTY; bank_id[b]=-1; released[b]=0;
        end
        #1;
        if (in_ready || out_valid || busy || done || dut.compute_start ||
            dut.compute_done || dut.acc_result_valid || dut.result_capture || dut.clear_acc || dut.feed_valid)
            $fatal(1, "asynchronous reset did not cancel controls");
        check_reset_data();
        repeat(2) @(posedge clk);
        #1;
        if (in_ready || out_valid || busy || done) $fatal(1, "held reset controls");
        check_reset_data();
        @(negedge clk); in_valid=0; out_ready=0; rst_n=1;
        idle(20, 1); resets++;
    endtask

    // Output 0 retained, output 1 pending, input 2 full, input 3 partial/full.
    task automatic fill_blocked(input integer last_beats);
        send_matrix(0, 0, 0);
        send_matrix(1, 0, 0);
        send_matrix(2, 0, 0);
        for (integer n=0; n<last_beats; n++) send_beat(3, n, 0);
        if (age != 11 || !full) $fatal(1, "blocked setup not reached");
    endtask

    // Fixed input seed, separate from the ready/valid stimulus PRNG.
    function automatic [31:0] vector_next(input [31:0] state);
        reg [31:0] x;
        begin
            x = state ^ (state << 13);
            x = x ^ (x >> 17);
            vector_next = x ^ (x << 5);
        end
    endfunction

    task automatic init_vectors;
        integer id, n, r, col, k;
        integer lhs, rhs, total;
        reg [31:0] vector_state;
        begin
            // Nine original directed cases plus 64 reproducible random pairs.
            vectors = 73;
            vector_state = 32'h00004a43;
            for (n=0; n<16; n=n+1) begin
                // Sequential x identity, zero x zero, identity x signed.
                va[0][n] = n+1;
                vb[0][n] = (n/4 == n%4) ? 1 : 0;
                va[2][n] = 0;
                vb[2][n] = 0;
                va[3][n] = vb[0][n];
                // Original mixed-sign and boundary fixtures, in row-major order.
                case (n)
                    0: begin va[1][n]=-3; vb[1][n]=4; va[4][n]=-128; vb[4][n]=-128; end
                    1: begin va[1][n]=0; vb[1][n]=-2; va[4][n]=-128; vb[4][n]=127; end
                    2: begin va[1][n]=5; vb[1][n]=0; va[4][n]=-128; vb[4][n]=-128; end
                    3: begin va[1][n]=-2; vb[1][n]=7; va[4][n]=-128; vb[4][n]=0; end
                    4: begin va[1][n]=7; vb[1][n]=-5; va[4][n]=127; vb[4][n]=-128; end
                    5: begin va[1][n]=-4; vb[1][n]=3; va[4][n]=127; vb[4][n]=127; end
                    6: begin va[1][n]=1; vb[1][n]=6; va[4][n]=127; vb[4][n]=127; end
                    7: begin va[1][n]=0; vb[1][n]=0; va[4][n]=127; vb[4][n]=-1; end
                    8: begin va[1][n]=-128; vb[1][n]=1; va[4][n]=-128; vb[4][n]=-128; end
                    9: begin va[1][n]=6; vb[1][n]=0; va[4][n]=127; vb[4][n]=127; end
                    10: begin va[1][n]=-7; vb[1][n]=-4; va[4][n]=-128; vb[4][n]=-128; end
                    11: begin va[1][n]=3; vb[1][n]=2; va[4][n]=127; vb[4][n]=1; end
                    12: begin va[1][n]=2; vb[1][n]=0; va[4][n]=0; vb[4][n]=-128; end
                    13: begin va[1][n]=-1; vb[1][n]=8; va[4][n]=-1; vb[4][n]=127; end
                    14: begin va[1][n]=0; vb[1][n]=-3; va[4][n]=1; vb[4][n]=127; end
                    15: begin va[1][n]=127; vb[1][n]=-6; va[4][n]=127; vb[4][n]=127; end
                endcase
                vb[3][n] = vb[1][n];
                // All four signed INT8 extreme combinations.
                va[5][n] = -128; vb[5][n] = -128;
                va[6][n] = -128; vb[6][n] = 127;
                va[7][n] = 127;  vb[7][n] = 127;
                va[8][n] = 127;  vb[8][n] = -128;
            end
            for (id=9; id<vectors; id=id+1) begin
                for (n=0; n<16; n=n+1) begin
                    vector_state = vector_next(vector_state);
                    va[id][n] = int'(vector_state[7:0]) - 128;
                    vector_state = vector_next(vector_state);
                    vb[id][n] = int'(vector_state[7:0]) - 128;
                end
            end

            if (vectors < 73 || vectors > 128) $fatal(1, "bad vector count");
            for (id=0; id<vectors; id=id+1) begin
                for (n=0; n<16; n=n+1) begin
                    if (va[id][n] < -128 || va[id][n] > 127) $fatal(1, "bad A vector");
                    if (vb[id][n] < -128 || vb[id][n] > 127) $fatal(1, "bad B vector");
                end
                // Independent mathematical oracle; no DUT signals or timing.
                // Signed 32-bit integer operands and accumulation are sufficient:
                // four INT8 products have a sum in [-65024, 65536].
                for (r=0; r<4; r=r+1) begin
                    for (col=0; col<4; col=col+1) begin
                        total = 0;
                        for (k=0; k<4; k=k+1) begin
                            lhs = va[id][r*4+k];
                            rhs = vb[id][k*4+col];
                            total = total + lhs * rhs;
                        end
                        vc[id][r*4+col] = total;
                    end
                end
            end
        end
    endtask

    initial begin : tests
        bit accepted;
        integer waited;
        for (integer n=0; n<5; n++) state_resets[n]=0;
        init_vectors();
        reset_dut();

        // Always-ready, all arithmetic vectors, continuous matrix boundaries.
        for (integer id=0; id<vectors; id++) send_matrix(id, 1, 0);
        drain();
        send_matrix(1, 1, 1); drain();

        // Deliberate same-edge load C + compute B + transfer A. A is held
        // while B loads; consume A on a B FEED edge while accepting C beat 3.
        send_matrix(0, 0, 0);
        send_matrix(1, 0, 0);
        send_beat(2, 0, 0);
        send_beat(2, 1, 0);
        send_beat(2, 2, 0);
        send_beat(2, 3, 1);
        for (integer n=4; n<16; n++) send_beat(2, n, 1);
        drain();

        // Real two-bank backpressure; retry an unchanged beat, then unblock.
        fill_blocked(16);
        repeat(40) begin
            step(1, 4, 0, 0, accepted);
            if (accepted) $fatal(1, "both FULL banks accepted a beat");
        end
        send_beat(4, 0, 1);
        for (integer n=1; n<16; n++) send_beat(4, n, 1);
        drain();

        // Capture on the first edge; pop old head + push last beat next edge.
        fill_blocked(15);
        idle(1, 1);
        send_beat(3, 15, 1);
        drain();

        // Randomized ready/valid stalls with a deterministic PRNG. A blocked
        // input retains valid and its exact payload until acceptance.
        for (integer id=9; id<vectors; id++) begin
            for (integer n=0; n<16; n++) begin
                if (n%7 == 2) idle(2, random_state[3]);
                accepted=0; waited=0;
                while (!accepted && waited < 200) begin
                    random_state={random_state[30:0], random_state[31]^random_state[21]^random_state[1]^random_state[0]};
                    step(1, id, n, random_state[4] && random_state[9], accepted);
                    waited++;
                end
                if (!accepted) $fatal(1, "randomized timeout");
            end
        end
        drain();

        // Every compute state reset, followed by a complete fresh transaction.
        for (integer target=0; target<4; target++) begin
            send_matrix(5, 0, 0);
            case(target)
                0: idle(1, 0); // CLEAR after E0
                1: idle(3, 0); // FEED after E2
                2: idle(8, 0); // DRAIN after E7
                3: idle(12, 0); // RESULT_PENDING after E11, empty output
            endcase
            reset_dut(); send_matrix(6, 1, 0); drain();
        end
        for (integer n=0; n<7; n++) send_beat(7, n, 0);
        reset_dut(); send_matrix(8, 1, 0); drain();
        send_matrix(0, 0, 0); idle(20, 0); // unread output, controller idle
        reset_dut(); send_matrix(1, 1, 0); drain();
        fill_blocked(16); // pending + unread output + both FULL banks
        reset_dut(); send_matrix(2, 1, 0); drain();
        fill_blocked(7); // pending + FULL bank + partial other bank
        reset_dut(); send_matrix(3, 1, 0); drain();

        if (!overlap_load || !overlap_output || !stalled_input || !pending_stalls ||
            !replacements || !push_pop || !capture_empty_not_ready || !consume_only || !reused ||
            !triple_overlap || !done_blocked || !ownership_checks)
            $fatal(1, "required functional coverage missing");
        for (integer n=0; n<5; n++)
            if (!state_resets[n]) $fatal(1, "reset state coverage missing %0d", n);
        $display("COVERAGE load_compute=%0d output_compute=%0d input_stalls=%0d pending_stalls=%0d replacements=%0d push_pop=%0d capture_empty_not_ready=%0d consume_only=%0d reused=%0d resets=%0d",
                 overlap_load, overlap_output, stalled_input, pending_stalls,
                 replacements, push_pop, capture_empty_not_ready, consume_only, reused, resets);
        $display("COVERAGE triple_overlap=%0d done_while_output_blocked=%0d ownership_checks=%0d", triple_overlap, done_blocked, ownership_checks);
        $display("PASS v3: results=%0d copies=%0d completions=%0d cycles=%0d golden_vectors=%0d", results, copies, completions, cycles, vectors);
        $finish;
    end
    initial begin
        #1000000; $fatal(1, "v3 global timeout");
    end
endmodule
