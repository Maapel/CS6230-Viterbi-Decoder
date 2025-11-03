# ReferenceModel.py
import struct
import numpy as np

# Helper to convert a 32-bit hex string to an IEEE 754 float
def hex_to_float(hex_str):
    try:
        int_val = int(hex_str, 16)
        # Use numpy.float32 for bit-exact precision matching with hardware
        return np.float32(struct.unpack('f', struct.pack('I', int_val))[0])
    except Exception as e:
        print(f"Error converting hex: {hex_str} - {e}")
        return np.float32(0.0)

# Helper to write output values in the required format
def write_output_val(f, val, is_float=False):
    if is_float:
        # Convert numpy.float32 back to 32-bit hex integer representation
        # Ensure we maintain float32 precision throughout
        float32_val = np.float32(val)
        hex_val = struct.unpack('I', struct.pack('f', float32_val))[0]
        f.write(f"{hex_val:08X}\n")
    else:
        # Write integer value
        f.write(f"{val}\n")

def run_viterbi(n, m, a_matrix, b_matrix, obs_sequence):
    """
    Runs the Viterbi algorithm using log-probabilities with numpy.float32 precision.
    Formula: V_t(j) = max_i(V_{t-1}(i) + a_ij) + b_j(o_t)
    """
    T = len(obs_sequence)
    if T == 0:
        return [], np.float32(-np.inf)

    # Viterbi probability table: V[t][j] - use numpy.float32 for precision
    V = [[np.float32(-np.inf) for _ in range(n)] for _ in range(T)]
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
            max_prob = np.float32(-np.inf)
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
    final_prob = np.float32(-np.inf)
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
    with open("../../CAD_for_VLSI_Project_spec/test-cases/small/N_small.dat", 'r') as f:
        N = int(f.readline().strip()) # N=2
        M = int(f.readline().strip()) # M=4
    print(f"Loaded N={N}, M={M}")

    # --- Load A.dat ---
    # (N+1) x N matrix
    A = [[np.float32(0.0) for _ in range(N)] for _ in range(N + 1)]
    with open("../../CAD_for_VLSI_Project_spec/test-cases/small/A_small.dat", 'r') as f:
        lines = f.readlines()
        idx = 0
        for i in range(N + 1):
            for j in range(N):
                hex_str = lines[idx].strip()
                A[i][j] = hex_to_float(hex_str)
                idx += 1

    # --- Load B.dat ---
    # N x M matrix
    B = [[np.float32(0.0) for _ in range(M)] for _ in range(N)]
    with open("../../CAD_for_VLSI_Project_spec/test-cases/small/B_small.dat", 'r') as f:
        lines = f.readlines()
        idx = 0
        for i in range(N):
            for j in range(M):
                B[i][j] = hex_to_float(lines[idx].strip())
                idx += 1

    # --- Process Input.dat and Write Output.dat ---
    with open("../../CAD_for_VLSI_Project_spec/test-cases/small/input_small.dat", 'r') as f_in, open("Ref_Output.dat", 'w') as f_out:
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
                    current_sequence.append(int(next_line))

            elif line != "0": # Ignore the final '0' if read in the main loop
                current_sequence.append(int(line))

    print("Reference model finished. 'Ref_Output.dat' created.")


if __name__ == "__main__":
    main()
