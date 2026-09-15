`timescale 1ns/1ps

module tb_accelerator_4x4_matmul;
    localparam int DATA_W = 8;
    localparam int ACC_W = 32;
    // Six cycles are required after the last feed edge; allow two extra.
    localparam int DRAIN_CYCLES = 8;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic clear_acc = 1'b0;
    logic signed [DATA_W-1:0] a_in [0:3], b_in [0:3];
    logic a_valid_in [0:3], b_valid_in [0:3];
    wire signed [ACC_W-1:0] c_out [0:3][0:3];
    logic signed [DATA_W-1:0] A [0:3][0:3];
    logic signed [DATA_W-1:0] B [0:3][0:3];
    logic signed [63:0] expected [0:3][0:3];

    accelerator_4x4_core #(
        .DATA_W(DATA_W), .ACC_W(ACC_W)
    ) dut (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc),
        .a_in(a_in), .a_valid_in(a_valid_in),
        .b_in(b_in), .b_valid_in(b_valid_in), .c_out(c_out)
    );

    always #5 clk = ~clk;

    task automatic idle_inputs;
        for (int lane = 0; lane < 4; lane++) begin
            a_in[lane] = '0;
            b_in[lane] = '0;
            a_valid_in[lane] = 1'b0;
            b_valid_in[lane] = 1'b0;
        end
    endtask

    task automatic check_zero(input string test_name);
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                if (c_out[i][j] !== {ACC_W{1'b0}})
                    $fatal(1, "%s: row=%0d column=%0d expected=0 DUT=%0d",
                           test_name, i, j, c_out[i][j]);
        $display("PASS %s: all 16 accumulators are zero", test_name);
    endtask

    task automatic clear_one_cycle(input string test_name);
        // Call only after reset or after the previous wavefront has drained.
        // clear_acc does not flush the skew or PE forwarding registers.
        @(negedge clk);
        idle_inputs();
        clear_acc = 1'b1;
        @(posedge clk);
        #1;
        check_zero(test_name);
        @(negedge clk);
        clear_acc = 1'b0;
    endtask

    task automatic compute_reference;
        logic signed [63:0] a_wide, b_wide;
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 4; j++) begin
                expected[i][j] = 64'sd0;
                for (int k = 0; k < 4; k++) begin
                    // Explicit sign extension before multiplication prevents
                    // an 8-bit intermediate from truncating the product.
                    a_wide = {{(64-DATA_W){A[i][k][DATA_W-1]}}, A[i][k]};
                    b_wide = {{(64-DATA_W){B[k][j][DATA_W-1]}}, B[k][j]};
                    expected[i][j] += a_wide * b_wide;
                end
            end
        end
    endtask

    task automatic check_result(input string test_name);
        logic signed [63:0] actual;
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                actual = {{(64-ACC_W){c_out[i][j][ACC_W-1]}}, c_out[i][j]};
                if (actual !== expected[i][j])
                    $fatal(1, "%s: row=%0d column=%0d expected=%0d DUT=%0d",
                           test_name, i, j, expected[i][j], actual);
            end
    endtask

    task automatic run_matmul(input string test_name);
        compute_reference();
        clear_one_cycle({test_name, " clear before feed"});

        // All four A rows and B columns are driven together, without TB skew.
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

        // If k=0 is edge E0, PE(i,j) consumes k at E(k+i+j).
        // PE(3,3) completes k=3 at E9: six rising edges after E3.
        repeat (DRAIN_CYCLES) begin
            @(negedge clk);
            idle_inputs();
            @(posedge clk);
            #1;
        end
        check_result(test_name);
        // Additional idle edges verify the completed matrix remains stable.
        repeat (2) begin
            @(negedge clk);
            idle_inputs();
            @(posedge clk);
            #1;
            check_result({test_name, " idle hold"});
        end
        $display("%s resulting C:", test_name);
        for (int i = 0; i < 4; i++)
            $display("  %0d  %0d  %0d  %0d",
                     c_out[i][0], c_out[i][1], c_out[i][2], c_out[i][3]);
        $display("PASS %s: all 16 signed matrix elements match", test_name);
    endtask

    initial begin
        idle_inputs();
        #1 rst_n = 1'b0;
        #1;
        check_zero("asynchronous reset");
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                A[i][j] = DATA_W'(4*i + j + 1);
                B[i][j] = (i == j) ? 8'sd1 : 8'sd0;
            end
        run_matmul("Test 1: A times identity");

        // Nontrivial signed operands, including zero and 8-bit extremes.
        A[0][0] = -8'sd3; A[0][1] =  8'sd0; A[0][2] =  8'sd5; A[0][3] = -8'sd2;
        A[1][0] =  8'sd7; A[1][1] = -8'sd4; A[1][2] =  8'sd1; A[1][3] =  8'sd0;
        A[2][0] =  8'sh80; A[2][1] = 8'sd6; A[2][2] = -8'sd7; A[2][3] =  8'sd3;
        A[3][0] =  8'sd2; A[3][1] = -8'sd1; A[3][2] =  8'sd0; A[3][3] =  8'sd127;

        B[0][0] =  8'sd4; B[0][1] = -8'sd2; B[0][2] =  8'sd0; B[0][3] =  8'sd7;
        B[1][0] = -8'sd5; B[1][1] =  8'sd3; B[1][2] =  8'sd6; B[1][3] =  8'sd0;
        B[2][0] =  8'sd1; B[2][1] =  8'sd0; B[2][2] = -8'sd4; B[2][3] =  8'sd2;
        B[3][0] =  8'sd0; B[3][1] =  8'sd8; B[3][2] = -8'sd3; B[3][3] = -8'sd6;
        // No reset here: this run checks clear_acc between real operations.
        run_matmul("Test 2: signed matrices");
        clear_one_cycle("final clear");

        $display("PASS: all accelerator_4x4_core matrix multiplication tests completed");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "FAIL: matrix multiplication testbench timeout");
    end
endmodule
