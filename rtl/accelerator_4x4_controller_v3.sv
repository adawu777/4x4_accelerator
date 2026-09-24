// Compute ownership is independent of input-bank and output-slot ownership.
module accelerator_4x4_controller_v3 (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       matrix_ready,
    input  logic       result_ready,
    output wire        compute_start,
    output wire        compute_done,
    output wire        acc_result_valid,
    output wire        result_capture,
    output wire        busy,
    output wire        clear_acc,
    output wire        feed_valid,
    output logic [1:0] k_counter
);
    typedef enum logic [2:0] {
        IDLE, CLEAR, FEED, DRAIN, RESULT_PENDING
    } state_t;
    state_t state;
    logic [2:0] drain_counter;

    assign compute_start = rst_n && (state == IDLE) && matrix_ready;
    // Sampled on E11: release operands independently of output backpressure.
    assign compute_done = rst_n && (state == DRAIN) && (drain_counter == 3'd5);
    // Earliest E12: the E11 final MAC must settle before reading accumulators.
    assign acc_result_valid = rst_n && (state == RESULT_PENDING);
    assign result_capture = acc_result_valid && result_ready;
    assign busy = rst_n && (state != IDLE);
    assign clear_acc = rst_n && (state == CLEAR);
    assign feed_valid = rst_n && (state == FEED);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            k_counter <= 2'd0;
            drain_counter <= 3'd0;
        end else begin
            case (state)
                IDLE: if (compute_start) state <= CLEAR;
                CLEAR: begin
                    state <= FEED;
                    k_counter <= 2'd0;
                end
                FEED: begin
                    if (k_counter == 2'd3) begin
                        state <= DRAIN;
                        k_counter <= 2'd0;
                        drain_counter <= 3'd0;
                    end else k_counter <= k_counter + 2'd1;
                end
                DRAIN: begin
                    if (drain_counter == 3'd5) begin
                        state <= RESULT_PENDING;
                        drain_counter <= 3'd0;
                    end else drain_counter <= drain_counter + 3'd1;
                end
                RESULT_PENDING: if (result_capture) state <= IDLE;
                default: begin
                    state <= IDLE;
                    k_counter <= 2'd0;
                    drain_counter <= 3'd0;
                end
            endcase
        end
    end
endmodule
