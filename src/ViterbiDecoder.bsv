// ViterbiDecoder.bsv
// Top-level Viterbi Decoder module implementing the proper BMU-ACSU-SMU architecture

package ViterbiDecoder;

import ViterbiTypes::*;
import Bmu::*;
import Acsu::*;
import Smu::*;
import Vector::*;
import RegFile::*;
import FIFO::*;

// Viterbi Decoder Module
module mkViterbiDecoder(ViterbiDecoderIfc);
    // Sub-modules
    BmuIfc bmu <- mkBmu;
    AcsuIfc acsu <- mkAcsu;
    SmuIfc smu <- mkSmu;

    // Path metrics memory: V[t][state]
    RegFile#(Bit#(32), LogProb) pathMetrics <- mkRegFile(0, 32*1024);

    // Configuration
    Reg#(Bit#(32)) nStates <- mkReg(0);
    Reg#(Bit#(32)) mObservations <- mkReg(0);
    Reg#(Bit#(32)) currentTime <- mkReg(0);

    // Processing state
    Reg#(Bool) initialized <- mkReg(False);
    FIFO#(Tuple2#(Vector#(1024, StateIndex), LogProb)) resultFifo <- mkFIFO;

    method Action start(Bit#(32) n, Bit#(32) m);
        nStates <= n;
        mObservations <= m;
        currentTime <= 0;
        initialized <= False;

        // Configure sub-modules
        bmu.configure(n, m);
        smu.configure(n);
    endmethod

    method Action loadTransitionProb(Bit#(32) addr, LogProb data);
        bmu.loadTransitionProb(addr, data);
    endmethod

    method Action loadEmissionProb(Bit#(32) addr, LogProb data);
        bmu.loadEmissionProb(addr, data);
    endmethod

    method Action processObservation(Observation obs);
        if (obs == 32'hFFFFFFFF) begin
            // End of sequence - perform traceback
            performTraceback();
        end else if (obs == 32'h00000000) begin
            // Final marker - output final result
            outputFinalResult();
        end else begin
            // Process observation
            processSingleObservation(obs);
        end
    endmethod

    method ActionValue#(Tuple2#(Vector#(1024, StateIndex), LogProb)) getResult();
        resultFifo.deq();
        return resultFifo.first();
    endmethod

    // Helper method to process a single observation
    method Action processSingleObservation(Observation obs);
        // Set observation in BMU
        bmu.setObservation(obs);

        if (!initialized) begin
            // Initialization step (t=0)
            performInitialization(obs);
            initialized <= True;
        end else begin
            // Iterative step (t > 0)
            performIteration();
        end

        // Advance time
        currentTime <= currentTime + 1;
        smu.advanceTime();
    endmethod

    // Initialization for t=0
    method Action performInitialization(Observation obs);
        for (Integer j = 0; j < 32; j = j + 1) begin
            if (fromInteger(j) < nStates) begin
                // Compute branch metric for start -> state j
                bmu.computeBranchMetric(32'hFFFFFFFF, fromInteger(j)); // Special marker for start state
                let branchMetric <- bmu.getBranchMetric();

                // For initialization, path metric is just the branch metric
                // Store result
                Bit#(32) addr = 0 * nStates + fromInteger(j); // time 0, state j
                pathMetrics.upd(addr, branchMetric);

                // Store predecessor (start state)
                smu.storePredecessor(fromInteger(j), 32'hFFFFFFFF); // Special marker for start
            end
        end
    endmethod

    // Iterative step for t > 0
    method Action performIteration();
        for (Integer j = 0; j < 32; j = j + 1) begin
            if (fromInteger(j) < nStates) begin
                // Clear ACSU for this state
                // Feed all candidates to ACSU
                for (Integer i = 0; i < 32; i = i + 1) begin
                    if (fromInteger(i) < nStates) begin
                        // Get previous path metric V[t-1][i]
                        Bit#(32) prevAddr = (currentTime - 1) * nStates + fromInteger(i);
                        LogProb prevPathMetric = pathMetrics.sub(prevAddr);

                        // Compute branch metric A[i][j] + B[j][obs]
                        bmu.computeBranchMetric(fromInteger(i), fromInteger(j));
                        let branchMetric <- bmu.getBranchMetric();

                        // Feed to ACSU
                        acsu.putCandidate(prevPathMetric, branchMetric, fromInteger(i));
                    end
                end

                // Get ACSU result
                let result <- acsu.getResult();
                match {.newPathMetric, .predecessor} = result;

                // Store new path metric
                Bit#(32) addr = currentTime * nStates + fromInteger(j);
                pathMetrics.upd(addr, newPathMetric);

                // Store predecessor in SMU
                smu.storePredecessor(fromInteger(j), predecessor);
            end
        end
    endmethod

    // Perform traceback at end of sequence
    method Action performTraceback();
        // Find state with best final path metric
        LogProb bestMetric = 32'h7FFFFFFF; // Large positive (least likely)
        StateIndex bestState = 0;

        for (Integer j = 0; j < 32; j = j + 1) begin
            if (fromInteger(j) < nStates) begin
                Bit#(32) addr = (currentTime - 1) * nStates + fromInteger(j);
                LogProb finalMetric = pathMetrics.sub(addr);
                if (finalMetric < bestMetric) begin // Smaller (more negative) is better for log probs
                    bestMetric = finalMetric;
                    bestState = fromInteger(j);
                end
            end
        end

        // Get survivor path
        let path <- smu.getSurvivorPath(bestState, currentTime);

        // Store result
        resultFifo.enq(tuple2(path, bestMetric));
    endmethod

    // Output final result
    method Action outputFinalResult();
        // This would output the final marker, but for now just prepare for next sequence
        initialized <= False;
        currentTime <= 0;
    endmethod

endmodule

endpackage
