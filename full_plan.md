Here are the resources from my side to help you get started.

I'll provide the two most critical components first:

1.  **Mission 1:** A synthesizable Verilog module for the 32-bit Floating-Point Adder.
2.  **Mission 2:** A complete Python reference model for verification.

-----

## Mission 1: The 32-bit Floating-Point Adder (Verilog)

[cite\_start]As we discussed, you cannot use the `+` operator for synthesis[cite: 261]. [cite\_start]Since your inputs are single-precision floats (log-probabilities)[cite: 186, 191], you need a module to perform floating-point addition.

Here is a **simplified** Verilog module for a 32-bit single-precision (IEEE 754) floating-point adder. It performs the core algorithm for adding two *normal* numbers.

```verilog
// Save this as FloatingPointAdder.v
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
```

### How to use this in your BSV code

To use this Verilog module, you must import it into your BSV file.

1.  Place `FloatingPointAdder.v` in your project directory.

2.  In your `ViterbiDecoder.bsv` file, add the import statement and interface definition at the top:

    ```bluespec
    import "BVI" FloatingPointAdder =
        module mkFloatingPointAdder (FloatingPointAdder_ifc);
            input_clock clk(CLK);
            input_reset rst(RST_N);
            
            method BVI.in_a(in_a);
            method BVI.in_b(in_b);
            method BVI.out_sum() out_sum;
        endmodule

    interface FloatingPointAdder_ifc;
        method Action in_a(Bit#(32) in_a);
        method Action in_b(Bit#(32) in_b);
        method Bit#(32) out_sum();
    endinterface
    ```

3.  Inside your `mkViterbiDecoder` module, instantiate the adder:

    ```bluespec
    // Instantiate the floating point adder
    FloatingPointAdder_ifc fp_adder <- mkFloatingPointAdder;
    ```

4.  When you need to perform an addition (like `p + a`), you must now use the module. This will make your logic sequential (it will take at least a clock cycle). You will need to use `Rules` or an `FSM` to manage the states.

    **Example (Conceptual):**
    Instead of this (which is forbidden):
    `let val = p + a;`

    You will need a rule-based approach:

    ```bluespec
    Reg#(Bit#(32)) reg_p <- mkReg(0);
    Reg#(Bit#(32)) reg_a <- mkReg(0);
    Reg#(Bool) execute_add <- mkReg(False);

    rule do_addition (execute_add);
        fp_adder.in_a(reg_p);
        fp_adder.in_b(reg_a);
        let val = fp_adder.out_sum();
        
        // ... use 'val' to continue your calculation ...
        
        execute_add <= False; // Done
    endrule

    // In your main processing logic:
    // ... when you have p and a ...
    reg_p <= p;
    reg_a <= a;
    execute_add <= True; // Fire the rule
    ```

-----

## Mission 2: The Python Reference Model

[cite\_start]You are required to create a reference model to verify your design's output[cite: 280, 290]. Here is a Python script that reads the sample input files and performs the Viterbi calculation.

```python
# Save this as ReferenceModel.py
import struct
import math

# Helper to convert a 32-bit hex string to an IEEE 754 float
def hex_to_float(hex_str):
    try:
        int_val = int(hex_str, 16)
        return struct.unpack('f', struct.pack('I', int_val))[0]
    except Exception as e:
        print(f"Error converting hex: {hex_str} - {e}")
        return 0.0

# Helper to write output values in the required format
def write_output_val(f, val, is_float=False):
    if is_float:
        # Convert float back to 32-bit hex integer representation
        hex_val = struct.unpack('I', struct.pack('f', val))[0]
        f.write(f"{hex_val:08X}\n")
    else:
        # Write integer value
        f.write(f"{val}\n")

def run_viterbi(n, m, a_matrix, b_matrix, obs_sequence):
    """
    Runs the Viterbi algorithm using log-probabilities.
    Formula: V_t(j) = max_i(V_{t-1}(i) + a_ij) + b_j(o_t)
    """
    T = len(obs_sequence)
    if T == 0:
        return [], -math.inf

    # Viterbi probability table: V[t][j]
    V = [[-math.inf for _ in range(n)] for _ in range(T)]
    # Backtrace path pointer table: B[t][j]
    B = [[0 for _ in range(n)] for _ in range(T)]

    # --- 1. Initialization Step (t=0) ---
    obs_idx = obs_sequence[0] - 1 # Observations are 1-indexed
    for j in range(n): # For each state j
        # P(j | start) + P(o_1 | j)
        # a_matrix[0] is for start -> j transitions
        # b_matrix[j][obs_idx] is for state j emitting obs_1
        a_0j = a_matrix[0][j]
        b_j_o1 = b_matrix[j][obs_idx]
        V[0][j] = a_0j + b_j_o1
        B[0][j] = 0 # Start state

    # --- 2. Iterative Step (t > 0) ---
    for t in range(1, T):
        obs_idx = obs_sequence[t] - 1
        for j in range(n): # For current state j
            max_prob = -math.inf
            max_state = 0
            for i in range(n): # From previous state i
                # V_{t-1}(i) + a_ij
                # a_matrix[i+1] is for state i -> j transitions
                prob = V[t-1][i] + a_matrix[i+1][j]
                if prob > max_prob:
                    max_prob = prob
                    max_state = i
            
            # V_t(j) = max_prob + b_j(o_t)
            V[t][j] = max_prob + b_matrix[j][obs_idx]
            B[t][j] = max_state

    # --- 3. Termination ---
    final_prob = -math.inf
    final_state = 0
    for j in range(n):
        if V[T-1][j] > final_prob:
            final_prob = V[T-1][j]
            final_state = j

    # --- 4. Backtrace ---
    path = [0] * T
    path[T-1] = final_state + 1 # States are 1-indexed in output
    
    for t in range(T - 2, -1, -1):
        path[t] = B[t+1][path[t+1]-1] + 1 # Get previous state from B table

    return path, final_prob


def main():
    # --- Load N.dat ---
    with open("N_xxxx.dat", 'r') as f:
        N = int(f.readline().strip()) # N=2
        M = int(f.readline().strip()) # M=4
    print(f"Loaded N={N}, M={M}")

    # --- Load A.dat ---
    # (N+1) x N matrix
    A = [[0.0 for _ in range(N)] for _ in range(N + 1)]
    with open("A_xxxx.dat", 'r') as f:
        lines = f.readlines()
        idx = 0
        for i in range(N + 1):
            for j in range(N):
                A[i][j] = hex_to_float(lines[idx].strip())
                idx += 1
    
    # --- Load B.dat ---
    # N x M matrix
    B = [[0.0 for _ in range(M)] for _ in range(N)]
    with open("B_xxxx.dat", 'r') as f:
        lines = f.readlines()
        idx = 0
        for i in range(N):
            for j in range(M):
                B[i][j] = hex_to_float(lines[idx].strip())
                idx += 1

    # --- Process Input.dat and Write Output.dat ---
    with open("Input.dat", 'r') as f_in, open("Ref_Output.dat", 'w') as f_out:
        current_sequence = []
        while True:
            line = f_in.readline()
            if not line:
                break # End of file
            
            line = line.strip()
            
            if line == "FFFFFFFF":
                # End of a sequence, process it
                print(f"Processing sequence: {current_sequence}")
                path, prob = run_viterbi(N, M, A, B, current_sequence)
                
                # Write path to output
                for state in path:
                    write_output_val(f_out, state)
                # Write final probability
                write_output_val(f_out, prob, is_float=True)
                # Write sequence marker
                write_output_val(f_out, "FFFFFFFF")
                
                current_sequence = [] # Reset for next sequence
                
                # Check for final marker
                next_line = f_in.readline()
                if not next_line:
                    break
                next_line = next_line.strip()
                if next_line == "0":
                    write_output_val(f_out, 0) # Write final '0' and stop
                    break
                else:
                    # Not the end, put the line back (figuratively)
                    # In a real scenario, you'd have to handle this more robustly
                    # For this simple file format, we assume '0' follows 'FFFFFFFF' *only* at the end.
                    # So, we process the line we just read.
                    if next_line != "FFFFFFFF":
                         current_sequence.append(int(next_line))
            
            elif line != "0": # Ignore the final '0' if read in the main loop
                current_sequence.append(int(line))

    print("Reference model finished. 'Ref_Output.dat' created.")


if __name__ == "__main__":
    main()
```

This gives you a solid start on the two most complex parts of the project. Your immediate next step should be to integrate the `FloatingPointAdder.v` module into your BSV design and refactor your logic to use it.

Once you have done that, would you like me to provide the BSV testbench code for file I/O (Mission 3) and the automation scripts (Mission 4)?