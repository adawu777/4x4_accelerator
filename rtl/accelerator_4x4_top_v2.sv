// Streaming 4x4 matrix accelerator. Every 16 accepted paired input beats
// form A and B in row-major order. Complete pairs execute automatically.
module accelerator_4x4_top_v2 #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     in_valid,
    output wire                      in_ready,
    input  logic signed [DATA_W-1:0]  a_data,
    input  logic signed [DATA_W-1:0]  b_data,
    output wire                      busy,
    output wire                      done,
    output wire signed [ACC_W-1:0]   c_out [0:3][0:3]
);

    wire buffer_in_ready;
    wire buffer_in_valid;
    wire matrix_ready;
    wire compute_start;
    wire compute_done;
    wire clear_acc;
    wire feed_valid;
    wire [1:0] k_counter;
    wire signed [DATA_W-1:0] a_selected [0:3][0:3];
    wire signed [DATA_W-1:0] b_selected [0:3][0:3];
    wire signed [DATA_W-1:0] a_feed [0:3];
    wire signed [DATA_W-1:0] b_feed [0:3];
    wire a_valid_in [0:3];
    wire b_valid_in [0:3];

    // The standalone buffer reports ready even in reset. Mask both sides
    // at this interface so reset cannot advertise an accepted input beat.
    assign in_ready = rst_n && buffer_in_ready;
    assign buffer_in_valid = rst_n && in_valid;

    // In the existing Moore FSM, !busy && !done identifies IDLE among
    // reachable states. Excluding DONE prevents a FIFO pop on an edge
    // where the controller would ignore start and only return to IDLE.
    assign compute_start = rst_n && matrix_ready && !busy && !done;
    assign compute_done = rst_n && done;

    matrix_input_pingpong_buffer #(
        .DATA_W(DATA_W)
    ) u_input_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(buffer_in_valid),
        .in_ready(buffer_in_ready),
        .a_data(a_data),
        .b_data(b_data),
        .matrix_ready(matrix_ready),
        .compute_start(compute_start),
        .compute_done(compute_done),
        .compute_sel(), // Bank ownership and selection remain in the buffer.
        .a_matrix(a_selected),
        .b_matrix(b_selected)
    );

    accelerator_4x4_controller u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(compute_start),
        .busy(busy),
        .done(done),
        .clear_acc(clear_acc),
        .feed_valid(feed_valid),
        .k_counter(k_counter)
    );

    // No matrix_operand_buffer: the active ping-pong bank already provides
    // stable storage. All four lanes use the same k during each FEED cycle.
    // Zero invalid inputs so uninitialized bank storage is not propagated
    // into the skew/data registers while the datapath is idle.
    generate
        for (genvar lane = 0; lane < 4; lane++) begin : gen_feed
            assign a_feed[lane] = feed_valid ? a_selected[lane][k_counter] : '0;
            assign b_feed[lane] = feed_valid ? b_selected[k_counter][lane] : '0;
            assign a_valid_in[lane] = feed_valid;
            assign b_valid_in[lane] = feed_valid;
        end
    endgenerate

    accelerator_4x4_core #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_core (
        .clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_acc),
        .a_in(a_feed),
        .a_valid_in(a_valid_in),
        .b_in(b_feed),
        .b_valid_in(b_valid_in),
        .c_out(c_out)
    );

    // Relative to start acceptance E0: CLEAR is applied at E1, input slices
    // k=0..3 are consumed at E2..E5, and the last PE updates at E11 (DONE).
    // The buffer samples compute_done at E12, retaining its bank through
    // the full DONE cycle. Another queued pair can start at E13.
    // c_out is the live accumulator array: sample on done, after NBA settles.
endmodule
