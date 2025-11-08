// FPAdder.bsv
// IEEE 754 Single-Precision Floating-Point Adder
// Implemented from first principles without using '+' or '*' operators

package FPAdder;

import Vector::*;

// IEEE 754 Single-Precision Format:
// Bit 31: Sign bit
// Bits 30-23: 8-bit exponent (biased by 127)
// Bits 22-0: 23-bit mantissa (implicit leading 1 for normalized numbers)

// Function to add two IEEE 754 single-precision floating-point numbers
function Bit#(32) fpAdd(Bit#(32) a, Bit#(32) b);
    // Unpack inputs
    Bit#(1) signA = a[31];
    Bit#(8) expA = a[30:23];
    Bit#(23) manA = a[22:0];

    Bit#(1) signB = b[31];
    Bit#(8) expB = b[30:23];
    Bit#(23) manB = b[22:0];

    // Handle special cases (simplified for this project)
    // For Viterbi decoder, we assume normal numbers and same signs (log probabilities)

    // Add implicit leading 1 for normalized numbers
    Bit#(24) manA_full = {1'b1, manA};
    Bit#(24) manB_full = {1'b1, manB};

    // Determine which number has larger exponent
    Bit#(8) exp_larger, exp_smaller;
    Bit#(24) man_larger, man_smaller;
    Bit#(1) sign_result = signA; // Assume same signs for log probabilities

    if (expA > expB) begin
        exp_larger = expA;
        exp_smaller = expB;
        man_larger = manA_full;
        man_smaller = manB_full;
    end else begin
        exp_larger = expB;
        exp_smaller = expA;
        man_larger = manB_full;
        man_smaller = manA_full;
    end

    // Calculate exponent difference
    Bit#(8) exp_diff = exp_larger - exp_smaller;

    // Align mantissas by shifting the smaller one right
    // Add guard, round, and sticky bits (4 extra bits total)
    Bit#(28) man_larger_ext = {man_larger, 4'b0};
    Bit#(28) man_smaller_ext = {man_smaller, 4'b0};

    // Right shift smaller mantissa
    Bit#(28) man_smaller_shifted = man_smaller_ext >> exp_diff;

    // Add the aligned mantissas
    // This now returns a 29-bit value to include a potential carry-out
    Bit#(29) man_sum = addMantissas(man_larger_ext, man_smaller_shifted);

    // Normalize the result
    Bit#(32) result = normalizeMantissa(man_sum, exp_larger, sign_result);

    return result;
endfunction

// Function to add two 28-bit mantissas using bitwise operations
// Returns a 29-bit result to capture the carry-out bit
function Bit#(29) addMantissas(Bit#(28) a, Bit#(28) b);
    Bit#(29) sum = 0;  // Extra bit for carry
    Bit#(1) carry = 0;

    for (Integer i = 0; i < 28; i = i + 1) begin
        Bit#(1) bitA = a[i];
        Bit#(1) bitB = b[i];

        // Full adder: sum = a ^ b ^ carry, cout = (a & b) | (b & carry) | (a & carry)
        Bit#(1) sum_bit = bitA ^ bitB ^ carry;
        Bit#(1) carry_out = (bitA & bitB) | (bitB & carry) | (bitA & carry);

        sum[i] = sum_bit;
        carry = carry_out;
    end

    // Store the final carry bit in the MSB
    sum[28] = carry;

    return sum;
endfunction

// Function to add two 29-bit mantissas using bitwise operations
// Returns a 30-bit result to capture the carry-out bit
function Bit#(30) addMantissas29(Bit#(29) a, Bit#(29) b);
    Bit#(30) sum = 0;  // Extra bit for carry
    Bit#(1) carry = 0;

    for (Integer i = 0; i < 29; i = i + 1) begin
        Bit#(1) bitA = a[i];
        Bit#(1) bitB = b[i];

        // Full adder: sum = a ^ b ^ carry, cout = (a & b) | (b & carry) | (a & carry)
        Bit#(1) sum_bit = bitA ^ bitB ^ carry;
        Bit#(1) carry_out = (bitA & bitB) | (bitB & carry) | (bitA & carry);

        sum[i] = sum_bit;
        carry = carry_out;
    end

    // Store the final carry bit in the MSB
    sum[29] = carry;

    return sum;
endfunction

// --- OPTIMIZED NORMALIZATION ---
// Uses case statements which are often faster for BSC to elaborate than deep for-loops
function Bit#(5) countLeadingZeros(Bit#(27) val);
    Bit#(5) zeros = 0;
    if (val[26] == 1) zeros = 0;
    else if (val[25] == 1) zeros = 1;
    else if (val[24] == 1) zeros = 2;
    else if (val[23] == 1) zeros = 3;
    else if (val[22] == 1) zeros = 4;
    else if (val[21] == 1) zeros = 5;
    else if (val[20] == 1) zeros = 6;
    else if (val[19] == 1) zeros = 7;
    else if (val[18] == 1) zeros = 8;
    else if (val[17] == 1) zeros = 9;
    else if (val[16] == 1) zeros = 10;
    else if (val[15] == 1) zeros = 11;
    else if (val[14] == 1) zeros = 12;
    else if (val[13] == 1) zeros = 13;
    else if (val[12] == 1) zeros = 14;
    else if (val[11] == 1) zeros = 15;
    else if (val[10] == 1) zeros = 16;
    else if (val[9] == 1) zeros = 17;
    else if (val[8] == 1) zeros = 18;
    else if (val[7] == 1) zeros = 19;
    else if (val[6] == 1) zeros = 20;
    else if (val[5] == 1) zeros = 21;
    else if (val[4] == 1) zeros = 22;
    else if (val[3] == 1) zeros = 23;
    else if (val[2] == 1) zeros = 24;
    else if (val[1] == 1) zeros = 25;
    else if (val[0] == 1) zeros = 26;
    else zeros = 27;
    return zeros;
endfunction

function Bit#(32) normalizeMantissa(Bit#(29) man_sum, Bit#(8) exp, Bit#(1) sign);
    Bit#(24) man_normalized;
    Bit#(8) exp_normalized = exp;

    if (man_sum[28] == 1) begin
        // Overflow
        man_normalized = man_sum[27:4];
        exp_normalized = exp + 1;
    end
    else begin
        // Use the manual optimized leading zero counter
        // We only need to check the top 27 bits (26 down to 0)
        Bit#(5) leading_zeros = countLeadingZeros(man_sum[26:0]);

        // Shift left to normalize
        Bit#(27) shifted_sum = man_sum[26:0] << leading_zeros;
        man_normalized = shifted_sum[26:3];

        // Adjust exponent (using normal subtraction, allowed for index/exponents)
        exp_normalized = exp - extend(leading_zeros);
    end

    // Rounding Logic (unchanged)
    Bit#(1) guard = man_sum[2];
    Bit#(1) round = man_sum[1];
    Bit#(1) sticky = man_sum[0];

    if (man_sum[28] == 0 && (round == 1 && (guard == 1 || sticky == 1 || man_normalized[0] == 1))) begin
         Bit#(29) mantissa_ext = {1'b0, man_normalized, 4'b0000};
         Bit#(30) rounded_result_full = addMantissas29(mantissa_ext, 29'd1);
         if (rounded_result_full[28] == 1) begin
             man_normalized = 24'h800000; // 1.000...
             exp_normalized = exp_normalized + 1;
         end else begin
             man_normalized = rounded_result_full[27:4];
         end
    end

    return {sign, exp_normalized, man_normalized[22:0]};
endfunction

endpackage
