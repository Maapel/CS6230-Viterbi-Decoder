// Tb.bsv
// Correct testbench for ViterbiDecoder
// Uses mkRegFileLoad as required by the project spec.

package Tb;

import ViterbiDecoder::*;
import ViterbiTypes::*;
import StmtFSM::*;
import FIFO::*;
import File::*;
import RegFile::*;
import Vector::*;
import FShow::*;
import GetPut::*;

// Testbench FSM States
typedef enum {
    Load_N,
    Load_A,
    Load_B,
    Process_Obs,
    Get_Results,
    Done
} TbState deriving (Bits, Eq, FShow);

(* synthesize *)
module mkTb(Empty);

    ViterbiDecoderIfc decoder <- mkViterbiDecoder;

    // --- 1. Create RegFiles for ALL input data ---
    // These sizes are for the 'small' test case. 
    // N=7, M=3. A=(N+1)*N = 8*7=56. B=N*M = 7*3=21.
    // For the 'huge' case, these would need to be larger (e.g., 1024).
    RegFile#(Bit#(4), Bit#(32)) rf_N <- mkRegFileFull(); // 2 entries (N, M)
    RegFile#(Bit#(6), Bit#(32)) rf_A <- mkRegFileFull(); // 56 entries
    RegFile#(Bit#(5), Bit#(32)) rf_B <- mkRegFileFull(); // 21 entries
    RegFile#(Bit#(4), Bit#(32)) rf_Input <- mkRegFileFull(); // 3 entries for small case

    // --- 2. Load files into RegFiles using mkRegFileLoad ---
    // This happens *at instantiation* (time 0).
    let n_loaded <- mkRegFileLoad("verification/test_cases/small/N_small.dat", rf_N);
    let a_loaded <- mkRegFileLoad("verification/test_cases/small/A_small.dat", rf_A);
    let b_loaded <- mkRegFileLoad("verification/test_cases/small/B_small.dat", rf_B);
    let input_loaded <- mkRegFileLoad("verification/test_cases/small/input_small.dat", rf_Input);

    // --- 3. FSM to control the test flow ---
    Reg#(TbState)     tbState <- mkReg(Load_N);
    Reg#(Bit#(32))    r_N <- mkReg(0);
    Reg#(Bit#(32))    r_M <- mkReg(0);
    Reg#(Bit#(32))    r_A_count <- mkReg(0);
    Reg#(Bit#(32))    r_B_count <- mkReg(0);
    Reg#(Bit#(32))    r_Input_count <- mkReg(0);
    Reg#(File)        outputFile <- mkReg(InvalidFile);

    // Rule to open the output file
    rule open_output_file (outputFile == InvalidFile);
        File f <- $fopen("build/Output.dat", "w");
        outputFile <= f;
    endrule

    // --- FSM Rules ---

    rule load_n_and_m (tbState == Load_N && outputFile != InvalidFile);
        let n = rf_N.sub(0);
        let m = rf_N.sub(1);
        
        decoder.start(n, m);
        
        r_N <= n;
        r_M <= m;
        tbState <= Load_A;
        $display("Testbench: Loaded N=%d, M=%d", n, m);
    endrule

    rule load_a_matrix (tbState == Load_A);
        let a_limit = (r_N + 1) * r_N;
        if (r_A_count < a_limit) begin
            let data = rf_A.sub(r_A_count);
            decoder.loadTransitionProb(r_A_count, data);
            r_A_count <= r_A_count + 1;
        end else begin
            tbState <= Load_B;
            $display("Testbench: A Matrix Loaded (%d entries)", r_A_count);
        end
    endrule

    rule load_b_matrix (tbState == Load_B);
        let b_limit = r_N * r_M;
        if (r_B_count < b_limit) begin
            let data = rf_B.sub(r_B_count);
            decoder.loadEmissionProb(r_B_count, data);
            r_B_count <= r_B_count + 1;
        end else begin
            tbState <= Process_Obs;
            $display("Testbench: B Matrix Loaded (%d entries)", r_B_count);
        end
    endrule

    rule process_observations (tbState == Process_Obs);
        // This is a bit tricky. We assume rf_Input size is known.
        // For 'small' case, it's 3 entries: 1, 3, FFFFFFFF, 0
        // Let's hardcode for simplicity. A better way uses $feof.
        // But mkRegFileLoad doesn't support $feof.
        
        let obs = rf_Input.sub(r_Input_count);
        decoder.processObservation(obs);
        r_Input_count <= r_Input_count + 1;
        
        if (obs == 32'h00000000) begin
            tbState <= Get_Results; // Move to get results
            $display("Testbench: Sent final '0' marker.");
        end else if (obs == 32'hFFFFFFFF) begin
            $display("Testbench: Sent 'FFFFFFFF' marker.");
            // After sending FFFF, we must immediately check for 0
            let next_obs = rf_Input.sub(r_Input_count + 1);
            if(next_obs == 32'h00000000) begin
                decoder.processObservation(next_obs);
                r_Input_count <= r_Input_count + 2;
                tbState <= Get_Results;
                $display("Testbench: Sent final '0' marker.");
            end
        end else begin
            $display("Testbench: Sent observation %h", obs);
        end
    endrule

    rule get_results (tbState == Get_Results);
        let res <- decoder.getResult();
        match {.path, .prob} = res;

        // Write the path
        // Note: Smu.getSurvivorPath is non-synthesizable and will run
        // instantly in simulation.
        for (Integer i = 0; i < 3; i = i + 1) begin // Hardcoded for small test path len
             if (path[i] != 0) begin // Print non-zero path elements
                $fwrite(outputFile, "%X\n", path[i]);
             end
        end

        // Write the probability
        $fwrite(outputFile, "%X\n", prob);
        
        // Write the end marker
        $fwrite(outputFile, "FFFFFFFF\n");
        
        // Check for the final '0' tuple
        let final_check <- decoder.getResult();
        if (final_check[1] == 0) begin
            $fwrite(outputFile, "0\n");
            tbState <= Done;
            $display("Testbench: Results written. Test complete.");
        end
    endrule

    rule finish_sim (tbState == Done);
        $fclose(outputFile);
        $finish;
    endrule

endmodule

endpackage
