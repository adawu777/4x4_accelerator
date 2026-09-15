`timescale 1ns/1ps

module tb_accelerator_4x4_pe;
    localparam int DATA_W = 8;
    localparam int ACC_W = 32;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic clear_acc = 1'b0;
    logic signed [DATA_W-1:0] a_in = '0, b_in = '0;
    logic a_valid_in = 1'b0, b_valid_in = 1'b0;
    logic signed [DATA_W-1:0] a_out, b_out;
    logic a_valid_out, b_valid_out;
    logic signed [ACC_W-1:0] acc;

    accelerator_4x4_pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc),
        .a_in(a_in), .b_in(b_in),
        .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(a_out), .b_out(b_out),
        .a_valid_out(a_valid_out), .b_valid_out(b_valid_out),
        .acc(acc)
    );

    always #5 clk = ~clk;  // 10 ns period

    task automatic check_reset;
        if (acc !== '0 || a_out !== '0 || b_out !== '0 ||
            a_valid_out !== 1'b0 || b_valid_out !== 1'b0)
            $fatal(1, "FAIL reset: acc=%0d A=%0d B=%0d valids=%b%b",
                   acc, a_out, b_out, a_valid_out, b_valid_out);
        $display("PASS reset: all outputs are zero at %0t", $time);
    endtask

    task automatic run_cycle(
        input string label,
        input logic signed [DATA_W-1:0] next_a,
        input logic signed [DATA_W-1:0] next_b,
        input logic next_a_valid,
        input logic next_b_valid,
        input logic next_clear,
        input logic signed [ACC_W-1:0] expected_acc
    );
        logic signed [DATA_W-1:0] old_a, old_b;
        logic old_a_valid, old_b_valid;
        begin
            // Drive away from the active edge to avoid races with the DUT.
            @(negedge clk);
            old_a = a_out;
            old_b = b_out;
            old_a_valid = a_valid_out;
            old_b_valid = b_valid_out;
            a_in = next_a;
            b_in = next_b;
            a_valid_in = next_a_valid;
            b_valid_in = next_b_valid;
            clear_acc = next_clear;

            // Registered outputs must retain the preceding cycle's values.
            #1;
            if (a_out !== old_a || b_out !== old_b ||
                a_valid_out !== old_a_valid || b_valid_out !== old_b_valid)
                $fatal(1, "FAIL %s: forwarding changed before the clock edge", label);

            @(posedge clk);
            #1;  // Allow nonblocking register updates to complete.
            if (acc !== expected_acc)
                $fatal(1, "FAIL %s: acc expected %0d, got %0d",
                       label, expected_acc, acc);
            if (a_out !== next_a || b_out !== next_b ||
                a_valid_out !== next_a_valid || b_valid_out !== next_b_valid)
                $fatal(1, "FAIL %s: forwarding expected A=%0d B=%0d valids=%b%b, got A=%0d B=%0d valids=%b%b",
                       label, next_a, next_b, next_a_valid, next_b_valid,
                       a_out, b_out, a_valid_out, b_valid_out);
            $display("PASS %s: acc=%0d; registered data/valid forwarding correct",
                     label, acc);
        end
    endtask

    initial begin
        // Assert between clock edges and check before the first rising edge.
        #1 rst_n = 1'b0;
        #1;
        check_reset();
        @(negedge clk);
        rst_n = 1'b1;

        run_cycle("MAC 2 * 3",       8'sd2,  8'sd3,  1, 1, 0, 32'sd6);
        run_cycle("MAC 4 * 5",       8'sd4,  8'sd5,  1, 1, 0, 32'sd26);
        run_cycle("invalid bubble",  8'sd99, 8'sd99, 0, 0, 0, 32'sd26);
        run_cycle("negative MAC",   -8'sd2,  8'sd3,  1, 1, 0, 32'sd20);
        // A valid nonzero product proves clear has priority over MAC.
        run_cycle("clear with forwarding", 8'sd7, -8'sd4, 1, 1, 1, 32'sd0);
        run_cycle("A-only valid",    8'sd9,  8'sd2,  1, 0, 0, 32'sd0);
        run_cycle("B-only valid",    8'sd3,  8'sd8,  0, 1, 0, 32'sd0);
        run_cycle("MAC after clear", 8'sd2,  8'sd3,  1, 1, 0, 32'sd6);

        // Recheck asynchronous reset from nonzero data, valids, and acc.
        #1 rst_n = 1'b0;
        #1;
        check_reset();

        $display("PASS: all accelerator_4x4_pe directed tests completed");
        $finish;
    end

    initial begin
        #1000;
        $fatal(1, "FAIL: testbench timeout");
    end
endmodule
