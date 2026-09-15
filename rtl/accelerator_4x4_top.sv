module accelerator_4x4_top #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     load,
    input  logic                     start,
    input  logic signed [DATA_W-1:0] a_matrix [0:3][0:3],
    input  logic signed [DATA_W-1:0] b_matrix [0:3][0:3],
    output logic                     busy,
    output logic                     done,
    output wire signed [ACC_W-1:0]   c_out [0:3][0:3]
);

    wire clear_acc;
    wire feed_valid;
    wire [1:0] k_counter;
    wire signed [DATA_W-1:0] a_feed [0:3];
    wire signed [DATA_W-1:0] b_feed [0:3];
    wire a_valid_in [0:3];
    wire b_valid_in [0:3];

    accelerator_4x4_controller u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .clear_acc(clear_acc),
        .feed_valid(feed_valid),
        .k_counter(k_counter)
    );

    matrix_operand_buffer #(
        .DATA_W(DATA_W)
    ) u_operand_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .load(load),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .k_counter(k_counter),
        .a_feed(a_feed),
        .b_feed(b_feed)
    );

    // All lanes carry one common k slice during each FEED cycle.
    generate
        for (genvar lane = 0; lane < 4; lane++) begin : gen_valid
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

endmodule
