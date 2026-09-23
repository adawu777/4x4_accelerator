
module matrix_input_pingpong_buffer #(
    parameter int DATA_W = 8
)(
    input  logic clk,
    input  logic rst_n,

    // ---------------------------------
    // Streaming input
    // ---------------------------------
    input  logic in_valid,
    output logic in_ready,

    input  logic signed [DATA_W-1:0] a_data,
    input  logic signed [DATA_W-1:0] b_data,

    // ---------------------------------
    // Compute controller interface
    // ---------------------------------
    output logic matrix_ready,

    input  logic compute_start,
    input  logic compute_done,

    output logic compute_sel,

    // ---------------------------------
    // Matrix output
    // ---------------------------------
    output wire signed [DATA_W-1:0]
        a_matrix [0:3][0:3],

    output wire signed [DATA_W-1:0]
        b_matrix [0:3][0:3]
);

    // =================================
    // 1. Buffer states
    // =================================

    typedef enum logic [1:0] {
        EMPTY,
        LOADING,
        FULL,
        COMPUTING
    } buffer_state_t;

    buffer_state_t state [0:1];

    // =================================
    // 2. Matrix storage
    // =================================

    logic signed [DATA_W-1:0]
        a_buf [0:1][0:3][0:3];

    logic signed [DATA_W-1:0]
        b_buf [0:1][0:3][0:3];

    // =================================
    // 3. Input control
    // =================================

    logic write_sel;
    logic write_buf_sel;
    logic write_buf_valid;

    logic [3:0] write_count;

    wire transfer = in_valid && in_ready;

    wire load_last =
        transfer && (write_count == 4'd15);

    // =================================
    // 4. Compute control
    // =================================

    logic compute_active;

    logic active_sel;

    wire start_fire =
        compute_start &&
        matrix_ready &&
        !compute_active;

    wire done_fire =
        compute_done && compute_active;

    // =================================
    // 5. Completed-matrix FIFO
    // =================================

    logic fifo_mem [0:1];

    logic fifo_wr_ptr;
    logic fifo_rd_ptr;

    logic [1:0] fifo_count;

    wire fifo_push = load_last;

    wire fifo_pop  = start_fire;

    assign matrix_ready =
        !compute_active &&
        (fifo_count != 0);

    // =================================
    // 6. Input buffer selection
    // =================================

    always_comb begin

        write_buf_valid = 1'b0;
        write_buf_sel   = write_sel;

        // Continue loading current buffer
        if (state[write_sel] == LOADING) begin

            write_buf_valid = 1'b1;

        end

        // Current buffer is empty
        else if (state[write_sel] == EMPTY) begin

            write_buf_valid = 1'b1;

        end

        // Try the other buffer
        else if (state[~write_sel] == EMPTY) begin

            write_buf_valid = 1'b1;
            write_buf_sel   = ~write_sel;

        end

    end

    assign in_ready = write_buf_valid;

    // =================================
    // 7. Matrix output selection
    // =================================

    assign compute_sel =
        compute_active ?
        active_sel :
        ((fifo_count != 0) ?
         fifo_mem[fifo_rd_ptr] : 1'b0);

    genvar i, j;

    generate

        for (i = 0; i < 4; i++) begin : ROW

            for (j = 0; j < 4; j++) begin : COL

                assign a_matrix[i][j] =
                    a_buf[compute_sel][i][j];

                assign b_matrix[i][j] =
                    b_buf[compute_sel][i][j];

            end

        end

    endgenerate

    // =================================
    // 8. Sequential control
    // =================================

    always_ff @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            write_sel      <= 1'b0;
            write_count    <= 4'd0;

            compute_active <= 1'b0;
            active_sel     <= 1'b0;

            fifo_wr_ptr    <= 1'b0;
            fifo_rd_ptr    <= 1'b0;
            fifo_count     <= 2'd0;

            state[0] <= EMPTY;
            state[1] <= EMPTY;

            fifo_mem[0] <= 1'b0;
            fifo_mem[1] <= 1'b0;

        end
        else begin

            // -------------------------
            // A. Streaming input write
            // -------------------------

            if (transfer) begin

                a_buf[write_buf_sel]
                     [write_count[3:2]]
                     [write_count[1:0]]
                     <= a_data;

                b_buf[write_buf_sel]
                     [write_count[3:2]]
                     [write_count[1:0]]
                     <= b_data;

                write_sel <= write_buf_sel;

                if (write_count == 4'd15) begin

                    state[write_buf_sel] <= FULL;

                    write_count <= 4'd0;

                end
                else begin

                    state[write_buf_sel] <= LOADING;

                    write_count <= write_count + 1'b1;

                end

            end

            // -------------------------
            // B. FIFO push
            // -------------------------

            if (fifo_push) begin

                fifo_mem[fifo_wr_ptr]
                    <= write_buf_sel;

                fifo_wr_ptr <= ~fifo_wr_ptr;

            end

            // -------------------------
            // C. Compute start
            // -------------------------

            if (start_fire) begin

                active_sel <=
                    fifo_mem[fifo_rd_ptr];

                compute_active <= 1'b1;

                state[fifo_mem[fifo_rd_ptr]]
                    <= COMPUTING;

                fifo_rd_ptr <= ~fifo_rd_ptr;

            end

            // -------------------------
            // D. Compute done
            // -------------------------

            if (done_fire) begin

                state[active_sel] <= EMPTY;

                compute_active <= 1'b0;

            end

            // -------------------------
            // E. FIFO count
            // -------------------------

            case ({fifo_push, fifo_pop})

                2'b10:
                    fifo_count <= fifo_count + 1'b1;

                2'b01:
                    fifo_count <= fifo_count - 1'b1;

                default:
                    fifo_count <= fifo_count;

            endcase

        end

    end

endmodule