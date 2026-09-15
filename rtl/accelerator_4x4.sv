module accelerator_4x4 #(
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

    // Four rows, with five horizontal boundaries per row.
    wire signed [DATA_W-1:0] a_pipe [0:3][0:4];
    wire                    a_valid_pipe [0:3][0:4];

    // Five vertical boundaries, each spanning four columns.
    wire signed [DATA_W-1:0] b_pipe [0:4][0:3];
    wire                    b_valid_pipe [0:4][0:3];

    generate
        for (genvar i = 0; i < 4; i++) begin : gen_rows
            assign a_pipe[i][0]       = a_in[i];
            assign a_valid_pipe[i][0] = a_valid_in[i];

            for (genvar j = 0; j < 4; j++) begin : gen_cols
                if (i == 0) begin : gen_top_inputs
                    assign b_pipe[0][j]       = b_in[j];
                    assign b_valid_pipe[0][j] = b_valid_in[j];
                end

                accelerator_4x4_pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear_acc(clear_acc),
                    .a_in(a_pipe[i][j]),
                    .b_in(b_pipe[i][j]),
                    .a_valid_in(a_valid_pipe[i][j]),
                    .b_valid_in(b_valid_pipe[i][j]),
                    .a_out(a_pipe[i][j+1]),
                    .b_out(b_pipe[i+1][j]),
                    .a_valid_out(a_valid_pipe[i][j+1]),
                    .b_valid_out(b_valid_pipe[i+1][j]),
                    .acc(c_out[i][j])
                );
            end
        end
    endgenerate

endmodule
