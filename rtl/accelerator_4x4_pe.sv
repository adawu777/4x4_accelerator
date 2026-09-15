module accelerator_4x4_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     clear_acc,
    input  logic signed [DATA_W-1:0] a_in,
    input  logic signed [DATA_W-1:0] b_in,
    input  logic                     a_valid_in,
    input  logic                     b_valid_in,
    output logic signed [DATA_W-1:0] a_out,
    output logic signed [DATA_W-1:0] b_out,
    output logic                     a_valid_out,
    output logic                     b_valid_out,
    output logic signed [ACC_W-1:0]  acc
);

    localparam int PRODUCT_W = 2 * DATA_W;
    logic signed [PRODUCT_W-1:0] product;
    logic signed [ACC_W-1:0]     product_extended;

    assign product = a_in * b_in;
    // ACC_W must be at least PRODUCT_W to retain the full signed product.
    assign product_extended = $signed({
        {(ACC_W-PRODUCT_W){product[PRODUCT_W-1]}}, product
    });

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out       <= '0;
            b_out       <= '0;
            a_valid_out <= 1'b0;
            b_valid_out <= 1'b0;
        end else begin
            a_out       <= a_in;
            b_out       <= b_in;
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= '0;
        end else if (clear_acc) begin
            acc <= '0;
        end else if (a_valid_in && b_valid_in) begin
            acc <= acc + product_extended;
        end
    end

endmodule
