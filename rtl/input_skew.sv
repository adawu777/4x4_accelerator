module input_skew #(
    parameter int DATA_W = 8
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic signed [DATA_W-1:0] a_in [0:3],
    input  logic                     a_valid_in [0:3],
    input  logic signed [DATA_W-1:0] b_in [0:3],
    input  logic                     b_valid_in [0:3],
    output wire signed [DATA_W-1:0]  a_out [0:3],
    output wire                      a_valid_out [0:3],
    output wire signed [DATA_W-1:0]  b_out [0:3],
    output wire                      b_valid_out [0:3]
);

    // Lane 0 is combinational, including during reset.
    assign a_out[0]       = a_in[0];
    assign a_valid_out[0] = a_valid_in[0];
    assign b_out[0]       = b_in[0];
    assign b_valid_out[0] = b_valid_in[0];

    generate
        for (genvar lane = 1; lane < 4; lane++) begin : gen_delay
            // Lane N has exactly N registers for both data and valid.
            logic signed [DATA_W-1:0] a_delay [0:lane-1];
            logic signed [DATA_W-1:0] b_delay [0:lane-1];
            logic a_valid_delay [0:lane-1];
            logic b_valid_delay [0:lane-1];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int stage = 0; stage < lane; stage++) begin
                        a_delay[stage]       <= '0;
                        b_delay[stage]       <= '0;
                        a_valid_delay[stage] <= 1'b0;
                        b_valid_delay[stage] <= 1'b0;
                    end
                end else begin
                    // Shift every cycle so invalid bubbles retain their timing.
                    a_delay[0]       <= a_in[lane];
                    b_delay[0]       <= b_in[lane];
                    a_valid_delay[0] <= a_valid_in[lane];
                    b_valid_delay[0] <= b_valid_in[lane];
                    for (int stage = 1; stage < lane; stage++) begin
                        a_delay[stage]       <= a_delay[stage-1];
                        b_delay[stage]       <= b_delay[stage-1];
                        a_valid_delay[stage] <= a_valid_delay[stage-1];
                        b_valid_delay[stage] <= b_valid_delay[stage-1];
                    end
                end
            end

            assign a_out[lane]       = a_delay[lane-1];
            assign b_out[lane]       = b_delay[lane-1];
            assign a_valid_out[lane] = a_valid_delay[lane-1];
            assign b_valid_out[lane] = b_valid_delay[lane-1];
        end
    endgenerate

endmodule
