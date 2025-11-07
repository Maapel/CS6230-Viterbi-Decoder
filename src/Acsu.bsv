// Acsu.bsv
// Add-Compare-Select Unit for Viterbi Decoder
// Performs the core Viterbi recursion: max over i of (V_{t-1}[i] + branch_metric[i][j])
// This version uses an FSM to find the maximum instead of a non-synthesizable for loop.

package Acsu;

import ViterbiTypes::*;
import FPAdder::*;
import Vector::*;
import FIFO::*;

// FSM states for finding maximum
typedef enum {
    Idle,           // Waiting for getResult() call
    FindingMax,     // Iterating through candidates to find max
    Done            // Result ready
} AcsuState deriving (Bits, Eq);

// Add-Compare-Select Unit Module
module mkAcsu(AcsuIfc);
    // State for accumulating candidates
    Reg#(Vector#(32, LogProb)) candidateMetrics <- mkReg(replicate(32'h7FFFFFFF)); // Initialize to large positive (least likely)
    Reg#(Vector#(32, StateIndex)) candidatePreds <- mkReg(replicate(0));
    Reg#(Bit#(6)) candidateCount <- mkReg(0); // Up to 32 candidates (N <= 32)

    // FSM state
    Reg#(AcsuState) acsuState <- mkReg(Idle);
    Reg#(Bit#(6)) maxSearchIdx <- mkReg(0); // Counter for finding maximum

    // Current maximum tracking
    Reg#(LogProb) currentMax <- mkReg(32'h80000000); // Most negative (most likely for log probs)
    Reg#(StateIndex) currentMaxPred <- mkReg(0);

    // Result FIFO
    FIFO#(Tuple2#(LogProb, StateIndex)) resultFifo <- mkFIFO;

    // Helper function to compare log probabilities (larger value is better)
    function Bool compareLogProbs(LogProb a, LogProb b);
        // For IEEE 754, compare as signed integers (log probs are negative)
        return (a > b);
    endfunction

    // FSM rule to find the maximum candidate
    rule findMaximum (acsuState == FindingMax);
        let idx = maxSearchIdx;

        if (idx < candidateCount) begin
            // Check this candidate
            LogProb candidate = candidateMetrics[idx];
            if (compareLogProbs(candidate, currentMax)) begin
                currentMax <= candidate;
                currentMaxPred <= candidatePreds[idx];
            end

            // Move to next candidate
            maxSearchIdx <= idx + 1;
        end else begin
            // Finished searching, enqueue result and reset
            resultFifo.enq(tuple2(currentMax, currentMaxPred));

            // Reset for next use
            candidateMetrics <= replicate(32'h7FFFFFFF);
            candidatePreds <= replicate(0);
            candidateCount <= 0;
            acsuState <= Idle;
        end
    endrule

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
        // Start the FSM to find maximum
        acsuState <= FindingMax;
        maxSearchIdx <= 0;
        currentMax <= 32'h80000000; // Most negative (most likely for log probs)
        currentMaxPred <= 0;

        // The actual result will be enqueued by the FSM rules
        resultFifo.deq();
        return resultFifo.first();
    endmethod

endmodule

endpackage
