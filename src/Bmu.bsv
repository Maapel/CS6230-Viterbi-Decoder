// Bmu.bsv
// Branch Metric Unit for Viterbi Decoder
// Computes log P(s_j|s_i) + log P(o_t|s_j) for each state transition

package Bmu;

import ViterbiTypes::*;
import FPAdder::*;
import RegFile::*;
import FIFO::*;

// Branch Metric Unit Module
module mkBmu(BmuIfc);
    // Memory for transition probabilities A[i][j] = log P(s_j|s_i)
    // Stored as (N+1) x N matrix, where row 0 is start state transitions
    RegFile#(Bit#(32), LogProb) aMatrix <- mkRegFile(0, 1024);

    // Memory for emission probabilities B[j][k] = log P(o_k|s_j)
    // Stored as N x M matrix
    RegFile#(Bit#(32), LogProb) bMatrix <- mkRegFile(0, 1024);

    // Current observation
    Reg#(Observation) currentObs <- mkReg(0);

    // Configuration
    Reg#(Bit#(32)) nStates <- mkReg(0);
    Reg#(Bit#(32)) mObservations <- mkReg(0);

    // FIFO for computed branch metrics
    FIFO#(LogProb) resultFifo <- mkFIFO;

    method Action configure(Bit#(32) n, Bit#(32) m);
        nStates <= n;
        mObservations <= m;
    endmethod

    method Action loadTransitionProb(Bit#(32) addr, LogProb data);
        aMatrix.upd(addr, data);
    endmethod

    method Action loadEmissionProb(Bit#(32) addr, LogProb data);
        bMatrix.upd(addr, data);
    endmethod

    method Action setObservation(Observation obs);
        currentObs <= obs;
    endmethod

    method Action computeBranchMetric(StateIndex fromState, StateIndex toState);
        // Compute address for transition probability A[fromState+1][toState]
        // A matrix: (N+1) x N, row 0 = start->states, rows 1-N = state->state transitions
        Bit#(32) aAddr = (fromState + 1) * nStates + toState;

        // Compute address for emission probability B[toState][currentObs-1]
        // B matrix: N x M, observations are 1-indexed
        Bit#(32) bAddr = toState * mObservations + (currentObs - 1);

        // Get the probabilities
        LogProb transProb = aMatrix.sub(aAddr);
        LogProb emitProb = bMatrix.sub(bAddr);

        // Compute branch metric: transProb + emitProb
        LogProb branchMetric = fpAdd(transProb, emitProb);

        // Store result
        resultFifo.enq(branchMetric);
    endmethod

    method ActionValue#(LogProb) getBranchMetric();
        resultFifo.deq();
        return resultFifo.first();
    endmethod

endmodule

endpackage
