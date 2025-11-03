// FloatingPointAdder.v
// A simplified 32-bit single-precision (IEEE 754) floating-point adder.
// NOTE: This is a simplified implementation for normal numbers.
// It does not handle NaNs, Infs, or denormalized numbers,
// but should be sufficient for the project's core recursion.

module FloatingPointAdder (
    input  wire [31:0] in_a,
    input  wire [31:0] in_b,
    output reg  [31:0] out_sum
);

    // 1. Unpack inputs
    wire sign_a = in_a[31];
    wire [7:0] exp_a = in_a[30:23];
    wire [22:0] man_a = in_a[22:0];

    wire sign_b = in_b[31];
    wire [7:0] exp_b = in_b[30:23];
    wire [22:0] man_b = in_b[22:0];

    // Add the implicit '1' for normal numbers
    wire [23:0] man_a_full = {1'b1, man_a};
    wire [23:0] man_b_full = {1'b1, man_b};

    // 2. Exponent Comparison & Alignment
    reg [7:0] exp_diff;
    reg [23:0] man_a_aligned, man_b_aligned;
    reg [7:0] final_exp;
    wire sign_sum;

    // We need extra bits for alignment shift and guard bits
    reg [27:0] man_a_shifted, man_b_shifted;
    reg [27:0] man_sum;
    reg [27:0] man_larger, man_smaller;

    always @* begin
        if (exp_a > exp_b) begin
            exp_diff = exp_a - exp_b;
            final_exp = exp_a;
            man_larger = {man_a_full, 4'b0}; // Add 4 guard bits
            man_smaller = {man_b_full, 4'b0};
            man_smaller = man_smaller >> exp_diff; // Right-shift smaller mantissa
        end else begin
            exp_diff = exp_b - exp_a;
            final_exp = exp_b;
            man_larger = {man_b_full, 4'b0};
            man_smaller = {man_a_full, 4'b0};
            man_smaller = man_smaller >> exp_diff;
        end

        // 3. Mantissa Addition
        // This project assumes log-probabilities, which are negative.
        // We are adding two log-probs: log(P1) + log(P2) = log(P1*P2).
        // The Viterbi formula is max(V_i + a_ij) + b_j.
        // Since all probabilities are <= 1, their logs are <= 0.
        // We can treat them as two positive numbers (magnitudes) and
        // keep the negative sign (sign bit = 1).
        // A full adder/subtractor would be needed if signs could be different.
        // For this project, we are always adding log-probs, so we add the magnitudes.

        // Simple addition for this project's use case
        man_sum = man_larger + man_smaller;
        sign_sum = sign_a; // Assuming inputs are always same sign (negative logs)

        // 4. Normalization
        if (man_sum[27]) begin
            // Result overflowed (e.g., 1.x + 1.x = 1x.x)
            // Shift right and increment exponent
            man_sum = man_sum >> 1;
            final_exp = final_exp + 1;
        end
        // NOTE: A full normalizer would also check for leading zeros
        // and shift left, decrementing the exponent.

        // 5. Pack the result
        // Simple rounding (truncate)
        out_sum = {sign_sum, final_exp, man_sum[26:4]};
    end

endmodule
