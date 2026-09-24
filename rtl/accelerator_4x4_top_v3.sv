// One ordered streaming input, two operand banks, one registered output slot.
module accelerator_4x4_top_v3 #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    in_valid,
    output wire                     in_ready,
    input  logic signed [DATA_W-1:0] a_data,
    input  logic signed [DATA_W-1:0] b_data,
    input  logic                    out_ready,
    output wire                     out_valid,
    output wire                     busy,
    output logic                    done,
    output wire signed [ACC_W-1:0]  c_out [0:3][0:3],
    output logic signed [ACC_W-1:0] out_matrix [0:3][0:3]
);
    wire buffer_ready, matrix_ready, compute_start, compute_done;
    wire clear_acc, feed_valid, result_ready, result_capture;
    wire acc_result_valid, output_fire, output_can_accept;
    wire [1:0] k_counter;
    logic output_full;
    wire signed [DATA_W-1:0] a_selected [0:3][0:3];
    wire signed [DATA_W-1:0] b_selected [0:3][0:3];
    wire signed [DATA_W-1:0] a_feed [0:3], b_feed [0:3];
    wire lane_valid [0:3];

    assign in_ready = rst_n && buffer_ready;
    assign out_valid = rst_n && output_full;
    assign output_fire = out_valid && out_ready;
    assign output_can_accept = !output_full || output_fire;
    assign result_ready = output_can_accept;

    matrix_input_pingpong_buffer #(.DATA_W(DATA_W)) u_input_buffer (
        .clk(clk), .rst_n(rst_n), .in_valid(rst_n && in_valid),
        .in_ready(buffer_ready), .a_data(a_data), .b_data(b_data),
        .matrix_ready(matrix_ready), .compute_start(compute_start),
        .compute_done(compute_done), .compute_sel(),
        .a_matrix(a_selected), .b_matrix(b_selected)
    );

    accelerator_4x4_controller_v3 u_controller (
        .clk(clk), .rst_n(rst_n), .matrix_ready(matrix_ready),
        .result_ready(result_ready), .compute_start(compute_start),
        .compute_done(compute_done), .result_capture(result_capture),
        .acc_result_valid(acc_result_valid),
        .busy(busy), .clear_acc(clear_acc), .feed_valid(feed_valid),
        .k_counter(k_counter)
    );

    generate
        for (genvar lane = 0; lane < 4; lane++) begin : gen_feed
            assign a_feed[lane] = feed_valid ? a_selected[lane][k_counter] : '0;
            assign b_feed[lane] = feed_valid ? b_selected[k_counter][lane] : '0;
            assign lane_valid[lane] = feed_valid;
        end
    endgenerate

    accelerator_4x4_core #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_core (
        .clk(clk), .rst_n(rst_n), .clear_acc(clear_acc),
        .a_in(a_feed), .a_valid_in(lane_valid),
        .b_in(b_feed), .b_valid_in(lane_valid), .c_out(c_out)
    );

    // Preserve v2 completion timing: E11 has the final MAC and one done pulse.
    // Neither output occupancy nor readiness can delay/repeat this indication.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) done <= 1'b0;
        else done <= compute_done;
    end

    // This is the only result storage outside the existing PE accumulators.
    // The consumer samples pre-edge out_matrix; replacement is visible after
    // the edge. Capture priority retains valid across consume-and-replace.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_full <= 1'b0;
            for (int r = 0; r < 4; r++)
                for (int c = 0; c < 4; c++) out_matrix[r][c] <= '0;
        end else begin
            if (result_capture) begin
                output_full <= 1'b1;
                for (int r = 0; r < 4; r++)
                    for (int c = 0; c < 4; c++)
                        out_matrix[r][c] <= c_out[r][c];
            end else if (output_fire) output_full <= 1'b0;
        end
    end
endmodule
