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

// FSM States
typedef enum {
    Idle,
    Init_LoadMatrices,
    Init_Process,
    Process_LoadMatrices,
    Process_Compute,
    Process_GetResult,
    Traceback,
    Output_Result
} ViterbiState deriving (Bits, Eq);

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

    // FSM state
    Reg#(ViterbiState) fsmState <- mkReg(Idle);

    // Loop counters for FSM
    Reg#(Bit#(6)) jCounter <- mkReg(0);  // For state loops (0-31)
    Reg#(Bit#(6)) iCounter <- mkReg(0);  // For predecessor loops (0-31)

    // Processing state
    Reg#(Bool) initialized <- mkReg(False);
    FIFO#(Tuple2#(Vector#(1024, StateIndex), LogProb)) resultFifo <- mkFIFO;

    // Input FIFO for observations
    FIFO#(Observation) obsFifo <- mkFIFO;

    // Rule: Process observations through FSM
    rule processObs (fsmState == Idle && obsFifo.notEmpty());
        let obs = obsFifo.first();
        obsFifo.deq();

        if (obs == 32'hFFFFFFFF) begin
            // End of sequence - start traceback
            fsmState <= Traceback;
        end else if (obs == 32'h00000000) begin
            // Final marker - output result
            fsmState <= Output_Result;
        end else begin
            // Process observation
            bmu.setObservation(obs);
            if (!initialized) begin
                fsmState <= Init_LoadMatrices;
                initialized <= True;
            end else begin
                fsmState <= Process_LoadMatrices;
            end
        end
    endrule

    // Rule: Initialize path metrics for t=0
    rule initPathMetrics (fsmState == Init_LoadMatrices);
        Bit#(32) j = extend(jCounter);

        if (j < nStates) begin
            // Compute branch metric for start -> state j
            bmu.computeBranchMetric(32'hFFFFFFFF, j); // Special marker for start state
            let branchMetric <- bmu.getBranchMetric();

            // Store result
            Bit#(32) addr = 0 * nStates + j; // time 0, state j
            pathMetrics.upd(addr, branchMetric);

            // Store predecessor (start state)
            smu.storePredecessor(j, 32'hFFFFFFFF); // Special marker for start
        end

        // Move to next state or finish
        if (jCounter == 31) begin
            jCounter <= 0;
            currentTime <= 1;
            smu.advanceTime();
            fsmState <= Idle;
        end else begin
            jCounter <= jCounter + 1;
        end
    endrule

    // Rule: Load matrices for iterative processing
    rule processLoadMatrices (fsmState == Process_LoadMatrices);
        fsmState <= Process_Compute;
        iCounter <= 0;
        jCounter <= 0;
    endrule

    // Rule: Compute one (i,j) combination per cycle
    rule processCompute (fsmState == Process_Compute);
        Bit#(32) j = extend(jCounter);
        Bit#(32) i = extend(iCounter);

        if (j < nStates && i < nStates) begin
            // Get previous path metric V[t-1][i]
            Bit#(32) prevAddr = (currentTime - 1) * nStates + i;
            LogProb prevPathMetric = pathMetrics.sub(prevAddr);

            // Compute branch metric A[i][j] + B[j][obs]
            bmu.computeBranchMetric(i, j);
            let branchMetric <- bmu.getBranchMetric();

            // Feed to ACSU
            acsu.putCandidate(prevPathMetric, branchMetric, i);
        end

        // Update counters
        if (iCounter == extend(nStates) - 1) begin
            // Finished all predecessors for this state
            iCounter <= 0;

            if (jCounter == extend(nStates) - 1) begin
                // Finished all states
                jCounter <= 0;
                fsmState <= Process_GetResult;
            end else begin
                jCounter <= jCounter + 1;
            end
        end else begin
            iCounter <= iCounter + 1;
        end
    endrule

    // Rule: Get ACSU results and store path metrics
    rule processGetResult (fsmState == Process_GetResult);
        Bit#(32) j = extend(jCounter);

        if (j < nStates) begin
            // Get ACSU result
            let result <- acsu.getResult();
            match {.newPathMetric, .predecessor} = result;

            // Store new path metric
            Bit#(32) addr = currentTime * nStates + j;
            pathMetrics.upd(addr, newPathMetric);

            // Store predecessor in SMU
            smu.storePredecessor(j, predecessor);
        end

        // Move to next state or finish
        if (jCounter == extend(nStates) - 1) begin
            jCounter <= 0;
            currentTime <= currentTime + 1;
            smu.advanceTime();
            fsmState <= Idle;
        end else begin
            jCounter <= jCounter + 1;
        end
    endrule

    // Rule: Perform traceback
    rule doTraceback (fsmState == Traceback);
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

        fsmState <= Idle;
    endrule

    // Rule: Output final result
    rule doOutputResult (fsmState == Output_Result);
        // Reset for next sequence
        initialized <= False;
        currentTime <= 0;
        fsmState <= Idle;
    endrule

    // Methods (must be at end of module)
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
        obsFifo.enq(obs);
    endmethod

    method ActionValue#(Tuple2#(Vector#(1024, StateIndex), LogProb)) getResult();
        resultFifo.deq();
        return resultFifo.first();
    endmethod

endmodule

endpackage
