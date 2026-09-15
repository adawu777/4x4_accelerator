module accelerator_4x4_core #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     clear_acc,
    input  logic signed [DATA_W-1:0] a_in [0:3],
    input  logic                     a_valid_in [0:3],
    input  logic signed [DATA_W-1:0] b_in [0:3],
    input  logic                     b_valid_in [0:3],
    output wire signed [ACC_W-1:0]   c_out [0:3][0:3]
);

    wire signed [DATA_W-1:0] a_skewed [0:3];
    wire signed [DATA_W-1:0] b_skewed [0:3];
    wire a_valid_skewed [0:3];
    wire b_valid_skewed [0:3];

    input_skew #(
        .DATA_W(DATA_W)
    ) u_input_skew (
        .clk(clk),
        .rst_n(rst_n),
        .a_in(a_in),
        .a_valid_in(a_valid_in),
        .b_in(b_in),
        .b_valid_in(b_valid_in),
        .a_out(a_skewed),
        .a_valid_out(a_valid_skewed),
        .b_out(b_skewed),
        .b_valid_out(b_valid_skewed)
    );

    accelerator_4x4 #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_accelerator_4x4 (
        .clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_acc),
        .a_in(a_skewed),
        .a_valid_in(a_valid_skewed),
        .b_in(b_skewed),
        .b_valid_in(b_valid_skewed),
        .c_out(c_out)
    );

endmodule
