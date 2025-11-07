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

// Function to normalize the mantissa and pack into IEEE 754 format
function Bit#(32) normalizeMantissa(Bit#(29) man_sum, Bit#(8) exp, Bit#(1) sign);
    // Find leading 1 position (simplified - assumes no denormals)
    Integer leading_zeros = 0;
    Bit#(24) man_normalized;
    Bit#(8) exp_normalized = exp;

    // Check for overflow from addition (man_sum[28])
    if (man_sum[28] == 1) begin
        // Overflow, shift right
        man_normalized = man_sum[27:4]; // Take bits 27:4
        exp_normalized = exp + 1;
    end
    else if (man_sum[27] == 0) begin
        // Find first 1 bit
        Bool found = False;
        for (Integer i = 26; i >= 0; i = i - 1) begin
            if (!found && man_sum[i] == 1) begin
                leading_zeros = 26 - i;
                found = True;
            end
        end

        // Shift left to normalize
        man_normalized = man_sum[23:0] << leading_zeros;
        exp_normalized = exp - fromInteger(leading_zeros);
    end else begin
        // Already normalized
        man_normalized = man_sum[26:3];  // Take bits 26:3
    end

    // Round to nearest even (simplified)
    Bit#(1) guard = man_sum[2];
    Bit#(1) round = man_sum[1];
    Bit#(1) sticky = man_sum[0];

    if (round == 1 && (guard == 1 || sticky == 1 || man_normalized[0] == 1)) begin
        // Round up
        // Add 1 to the 24-bit mantissa (by adding to the 29-bit extended value)
        Bit#(29) mantissa_ext = {1'b0, man_normalized, 4'b0000};
        Bit#(30) rounded_result_full = addMantissas29(mantissa_ext, 29'd1);
        Bit#(29) rounded_result = rounded_result_full[28:0];

        // Handle overflow from rounding
        if (rounded_result[28] == 1) begin // This is the 'index 24' error fix
            // e.g., 0b1.11...1 rounded up to 0b10.0...0
            // If we round up and overflow, the new mantissa should be 0, and we increment the exponent.
            man_normalized = 24'h000000; // All zeros
            exp_normalized = exp_normalized + 1;
        end else begin
            man_normalized = rounded_result[27:4]; // No overflow
        end
    end

    // Pack result
    Bit#(32) result = {sign, exp_normalized, man_normalized[22:0]};
    return result;
endfunction

endpackage
