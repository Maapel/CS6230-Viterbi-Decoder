// Acsu.bsv
// Add-Compare-Select Unit for Viterbi Decoder
// Performs the core Viterbi recursion: max over i of (V_{t-1}[i] + branch_metric[i][j])

package Acsu;

import ViterbiTypes::*;
import FPAdder::*;
import Vector::*;
import FIFO::*;

// Add-Compare-Select Unit Module
module mkAcsu(AcsuIfc);
    // State for accumulating candidates
    Reg#(Vector#(32, LogProb)) candidateMetrics <- mkReg(replicate(32'h7FFFFFFF)); // Initialize to large positive (least likely)
    Reg#(Vector#(32, StateIndex)) candidatePreds <- mkReg(replicate(0));
    Reg#(Bit#(6)) candidateCount <- mkReg(0); // Up to 32 candidates (N <= 32)

    // Result FIFO
    FIFO#(Tuple2#(LogProb, StateIndex)) resultFifo <- mkFIFO;

    method Action putCandidate(LogProb pathMetric, LogProb branchMetric, StateIndex predIndex);
        // Add path metric + branch metric
        LogProb candidate = fpAdd(pathMetric, branchMetric);

        // Store candidate
        Vector#(32, LogProb) newMetrics = candidateMetrics;
        Vector#(32, StateIndex) newPreds = candidatePreds;

        Bit#(6) idx = candidateCount;
        newMetrics[idx] = candidate;
        newPreds[idx] = predIndex;

        candidateMetrics <= newMetrics;
        candidatePreds <= newPreds;
        candidateCount <= candidateCount + 1;
    endmethod

    method ActionValue#(Tuple2#(LogProb, StateIndex)) getResult();
        // Find the maximum among all candidates
        LogProb maxVal = 32'h80000000; // Most negative (most likely for log probs)
        StateIndex maxPred = 0;

        for (Integer i = 0; i < 32; i = i + 1) begin
            if (fromInteger(i) < candidateCount) begin
                LogProb candidate = candidateMetrics[fromInteger(i)];
                if (compareLogProbs(candidate, maxVal)) begin
                    maxVal = candidate;
                    maxPred = candidatePreds[fromInteger(i)];
                end
            end
        end

        // Reset for next use
        candidateMetrics <= replicate(32'h7FFFFFFF);
        candidatePreds <= replicate(0);
        candidateCount <= 0;

        // Return result
        return tuple2(maxVal, maxPred);
    endmethod

    // Helper function to compare log probabilities (larger value is better)
    function Bool compareLogProbs(LogProb a, LogProb b);
        // For IEEE 754, compare as signed integers (log probs are negative)
        return (a > b);
    endfunction

endmodule

endpackage
