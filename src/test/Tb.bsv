// Tb.bsv - Testbench for Viterbi Decoder
package Tb;

import ViterbiDecoder::*;
import StmtFSM::*;
import FIFO::*;
import RegFile::*;
import Vector::*;

// Testbench module
(* synthesize *)
module mkTb(Empty);
    // Instantiate the DUT
    ViterbiDecoder_ifc dut <- mkViterbiDecoder;

    // RegFiles for loading matrices using mkRegFileLoad
    RegFile#(Bit#(32), Bit#(32)) nFile <- mkRegFileLoad("../../CAD_for_VLSI_Project_spec/test-cases/small/N_small.dat", 0, 1);
    RegFile#(Bit#(32), Bit#(32)) aFile <- mkRegFileLoad("../../CAD_for_VLSI_Project_spec/test-cases/small/A_small.dat", 0, 5); // (N+1)*N - 1 = 5
    RegFile#(Bit#(32), Bit#(32)) bFile <- mkRegFileLoad("../../CAD_for_VLSI_Project_spec/test-cases/small/B_small.dat", 0, 7); // N*M - 1 = 7
    RegFile#(Bit#(32), Bit#(32)) obsFile <- mkRegFileLoad("../../CAD_for_VLSI_Project_spec/test-cases/small/input_small.dat", 0, 100); // Sufficient size

    // FSM for testbench control
    StmtFSM testFSM <- mkFSM(seq
        // Load N and M
        action
            Bit#(32) n_val = nFile.sub(0);
            Bit#(32) m_val = nFile.sub(1);
            dut.start(n_val, m_val);
            $display("Testbench: Loaded N=%h, M=%h", n_val, m_val);
        endaction

        // Load A matrix (transition probabilities)
        $display("Testbench: Loading A Matrix...");
        for (Integer i = 0; i < 6; i = i + 1) begin
            action
                Bit#(32) val = aFile.sub(fromInteger(i));
                dut.loadTransitionProb(fromInteger(i), val);
            endaction
        end
        $display("Testbench: A Matrix Loaded.");

        // Load B matrix (emission probabilities)
        $display("Testbench: Loading B Matrix...");
        for (Integer i = 0; i < 8; i = i + 1) begin
            action
                Bit#(32) val = bFile.sub(fromInteger(i));
                dut.loadEmissionProb(fromInteger(i), val);
            endaction
        end
        $display("Testbench: B Matrix Loaded.");

        // Process observations
        $display("Testbench: Processing observations...");
        action
            Integer obs_idx = 0;
            while (True) begin
                Bit#(32) obs = obsFile.sub(fromInteger(obs_idx));
                obs_idx = obs_idx + 1;

                if (obs == 32'hFFFFFFFF) begin
                    // End of sequence
                    dut.processObservation(obs);
                    break;
                end else if (obs == 32'h00000000) begin
                    // Final marker
                    dut.processObservation(obs);
                    break;
                end else begin
                    // Regular observation
                    dut.processObservation(obs);
                end
            end
        endaction

        // Get and display results
        action
            let result <- dut.getResult();
            match {.path, .prob} = result;

            $display("Testbench: Viterbi path found");
            $display("Testbench: Final probability: %h", prob);

            // Write output to file
            Integer path_idx = 0;
            while (path_idx < 10) begin // Show first 10 states
                if (path[path_idx] != 0) begin
                    $display("State[%d]: %d", path_idx, path[path_idx]);
                end
                path_idx = path_idx + 1;
            end
        endaction

        // Finish
        action
            $display("Testbench: Simulation complete");
            $finish;
        endaction
    endseq);

    // Start the test
    rule startTest;
        testFSM.start();
    endrule

endmodule
endpackage
