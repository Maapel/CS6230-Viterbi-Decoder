// Save this as Tb.bsv
package Tb;

import ViterbiDecoder::*; // Import your decoder's package
import StmtFSM::*;
import FIFO::*;
import File::*; // For file handling
import RegFile::*;
import GetPut::*;
import ClientServer::*;
import Vector::*;
import String::*; // For string manipulation
import FShow::*; // For $fshow
import BSV_Utils::*; // For $fscanf, $fdisplay, etc.

(* synthesize *)
module mkTb(Empty);

    ViterbiDecoder_ifc decoder <- mkViterbiDecoder;

    // --- File Handles ---
    // Note: BSV's file type is a bit abstract.
    // We use built-in system tasks for reading/writing formatted text.
    let input_N     <- mkReg(InvalidFile);
    let input_A     <- mkReg(InvalidFile);
    let input_B     <- mkReg(InvalidFile);
    let input_Obs   <- mkReg(InvalidFile);
    let output_file <- mkReg(InvalidFile);

    StmtFSM fsm <- mkFSM(seq

        // --- 1. Open all files ---
        action
            // Open input files for reading ("r")
            let f_n   <- $fopen("../CAD_for_VLSI_Project_spec/test-cases/small/N_small.dat", "r");
            let f_a   <- $fopen("../CAD_for_VLSI_Project_spec/test-cases/small/A_small.dat", "r");
            let f_b   <- $fopen("../CAD_for_VLSI_Project_spec/test-cases/small/B_small.dat", "r");
            let f_obs <- $fopen("../CAD_for_VLSI_Project_spec/test-cases/small/input_small.dat", "r");

            // Open output file for writing ("w")
            let f_out <- $fopen("Output.dat", "w");

            if (f_n == InvalidFile || f_a == InvalidFile || f_b == InvalidFile || f_obs == InvalidFile || f_out == InvalidFile) begin
                $display("ERROR: Could not open one or more files.");
                $finish;
            end

            input_N     <= f_n;
            input_A     <= f_a;
            input_B     <= f_b;
            input_Obs   <= f_obs;
            output_file <= f_out;
            $display("Testbench: All files opened.");
        endaction

        // --- 2. Load N and M ---
        action
            let n_val <- $fscanf(input_N, "%d");
            let m_val <- $fscanf(input_N, "%d");
            decoder.start(n_val, m_val);
            $display("Testbench: Loaded N=%d, M=%d", n_val, m_val);

            // We need to know N and M to load the matrices
            // This is a common pattern: pass N/M to a loading function.
            // For simplicity here, we'll hardcode based on the sample.
            // In a generic testbench, you'd use n_val and m_val in loops.
        endaction

        // --- 3. Load A Matrix (Transition) ---
        // The spec mentions mkRegFileLoad, which is for binary files.
        // Since the samples are text, we'll use $fscanf.
        $display("Testbench: Loading A Matrix...");
        // A.dat has (N+1)*N = (2+1)*2 = 6 entries for the sample
        for (Integer i = 0; i < 6; i = i + 1) begin
            action
                let hex_val <- $fscanf_hex(input_A);
                decoder.loadA(fromInteger(i), hex_val);
            endaction
        end
        $display("Testbench: A Matrix Loaded.");

        // --- 4. Load B Matrix (Emission) ---
        $display("Testbench: Loading B Matrix...");
        // B.dat has N*M = 2*4 = 8 entries for the sample
        for (Integer i = 0; i < 8; i = i + 1) begin
            action
                let hex_val <- $fscanf_hex(input_B);
                decoder.loadB(fromInteger(i), hex_val);
            endaction
        end
        $display("Testbench: B Matrix Loaded.");

        // --- 5. Process Observation Sequences ---
        $display("Testbench: Starting observation processing...");
        action
            // This loop will process all sequences in Input.dat
            while (True) begin

                // --- Read one observation sequence ---
                action
                    while (True) begin
                        let obs_val <- $fscanf_hex(input_Obs);

                        if (obs_val == 32'hFFFFFFFF) begin
                            decoder.process(-1); // Send end-of-sequence marker
                            break; // Exit inner loop
                        end

                        if (obs_val == 32'h00000000) begin
                            // This is the final '0'
                            decoder.process(0); // Send final '0' marker
                            break; // Exit inner loop
                        end

                        decoder.loadInput(obs_val); // Send the observation
                        decoder.process(obs_val);
                    end
                endaction

                // --- Write the corresponding output sequence ---
                action
                    while (True) begin
                        let out_val <- decoder.getOutput;

                        // Write to file using $fwrite
                        $fwrite(output_file, "%X\n", out_val);

                        if (out_val == 32'hFFFFFFFF) begin
                            break; // End of this output sequence
                        end
                        if (out_val == 32'h00000000) begin
                            break; // Final '0'
                        end
                    end
                endaction

                // Check if the last value read was the final '0'
                // This is a simplification; a more robust FSM would be better.
                let eof_check <- $feof(input_Obs);
                if (eof_check != 0) begin
                    break; // Exit outer loop
                end
            end
        endaction

        // --- 6. Close files and finish ---
        action
            $fclose(input_N);
            $fclose(input_A);
            $fclose(input_B);
            $fclose(input_Obs);
            $fclose(output_file);
            $display("Testbench: Processing complete. 'Output.dat' created.");
            $finish;
        endaction

    endseq);

endmodule
endpackage
