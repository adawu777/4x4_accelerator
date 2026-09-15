module matrix_operand_buffer #(
    parameter int DATA_W = 8
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     load,
    input  logic signed [DATA_W-1:0] a_matrix [0:3][0:3],
    input  logic signed [DATA_W-1:0] b_matrix [0:3][0:3],
    input  logic [1:0]               k_counter,
    output logic signed [DATA_W-1:0] a_feed [0:3],
    output logic signed [DATA_W-1:0] b_feed [0:3]
);

    logic signed [DATA_W-1:0] a_mem [0:3][0:3];
    logic signed [DATA_W-1:0] b_mem [0:3][0:3];

    // Capture both matrices together; otherwise retain the stored operands.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    a_mem[i][j] <= '0;
                    b_mem[i][j] <= '0;
                end
            end
        end else if (load) begin
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    a_mem[i][j] <= a_matrix[i][j];
                    b_mem[i][j] <= b_matrix[i][j];
                end
            end
        end
    end

    // Select A's column k and B's row k without adding a pipeline stage.
    always_comb begin
        for (int lane = 0; lane < 4; lane++) begin
            a_feed[lane] = a_mem[lane][k_counter];
            b_feed[lane] = b_mem[k_counter][lane];
        end
    end

endmodule
