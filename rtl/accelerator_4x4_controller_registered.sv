module accelerator_4x4_controller_registered (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    output logic       busy,
    output logic       done,
    output logic       clear_acc,
    output logic       feed_valid,
    output logic [1:0] k_counter
);

    typedef enum logic [2:0] {
        IDLE,
        CLEAR,
        FEED,
        DRAIN,
        DONE
    } state_t;

    state_t state, next_state;
    logic [2:0] drain_counter;

    // Counters advance only on rising edges in their respective states.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            k_counter     <= 2'd0;
            drain_counter <= 3'd0;
        end else begin
            state <= next_state;

            if (state == FEED) begin
                if (k_counter == 2'd3)
                    k_counter <= 2'd0;
                else
                    k_counter <= k_counter + 2'd1;
            end else begin
                k_counter <= 2'd0;
            end

            if (state == DRAIN) begin
                if (drain_counter == 3'd5)
                    drain_counter <= 3'd0;
                else
                    drain_counter <= drain_counter + 3'd1;
            end else begin
                drain_counter <= 3'd0;
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start)
                    next_state = CLEAR;
            end
            CLEAR: next_state = FEED;
            FEED: begin
                if (k_counter == 2'd3)
                    next_state = DRAIN;
            end
            DRAIN: begin
                // Enter DRAIN at zero. Edges with pre-edge counts 0..5
                // are the six drain edges; DONE is registered on edge six.
                if (drain_counter == 3'd5)
                    next_state = DONE;
            end
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // Register the decode of next_state alongside the state register.
    // Counters still use the pre-edge state to preserve FEED/DRAIN timing.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy       <= 1'b0;
            done       <= 1'b0;
            clear_acc  <= 1'b0;
            feed_valid <= 1'b0;
        end
        else begin
            busy       <= 1'b0;
            done       <= 1'b0;
            clear_acc  <= 1'b0;
            feed_valid <= 1'b0;

            case (next_state)
                CLEAR: begin
                    busy      <= 1'b1;
                    clear_acc <= 1'b1;
                end

                FEED: begin
                    busy       <= 1'b1;
                    feed_valid <= 1'b1;
                end

                DRAIN: begin
                    busy <= 1'b1;
                end

                DONE: begin
                    done <= 1'b1;
                end

                default: begin
                end
            endcase
        end
    end

endmodule
