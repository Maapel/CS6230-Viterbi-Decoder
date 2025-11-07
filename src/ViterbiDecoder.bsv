// ViterbiDecoder.bsv
// Top-level Viterbi Decoder module implementing the proper BMU-ACSU-SMU architecture
// This version is refactored with a correct Finite State Machine to replace
// non-synthesizable software loops.

package ViterbiDecoder;

import ViterbiTypes::*;
import Bmu::*;
import Acsu::*;
import Smu::*;
import Vector::*;
import RegFile::*;
import FIFO::*;
import FShow::*; // For $fshow

// Define the states for our main Finite State Machine
typedef enum {
    Idle,
    Init_ComputeBMU,        // State for initialization loop, calling bmu.compute
    Init_GetBMU_Store,      // State for initialization loop, calling bmu.get and storing
    Iter_ComputeBMU,        // State for main loop, calling bmu.compute for (i, j)
    Iter_GetBMU_PutACSU,    // State for main loop, getting BMU result and feeding ACSU
    Iter_GetACSU_Store,     // State for main loop, getting ACSU result for state j
    Traceback_FindBest_Loop,// State for traceback, finding best final state
    Traceback_StartSMU,     // NEW: Tells SMU to start tracing
    Traceback_GetPath_Enq   // State for traceback, getting path from SMU and enqueuing result
} FSMState deriving (Bits, Eq, FShow);

// Viterbi Decoder Module
module mkViterbiDecoder(ViterbiDecoderIfc);
    // Sub-modules
    BmuIfc bmu <- mkBmu;
    AcsuIfc acsu <- mkAcsu;
    SmuIfc smu <- mkSmu;

    // Path metrics memory: V[t][state]
    // We need two RegFiles to read V[t-1] and write V[t] without conflict.
    // This is a standard technique called ping-ponging or double-buffering.
    RegFile#(Bit#(32), LogProb) pathMetricsA <- mkRegFile(0, 1024);
    RegFile#(Bit#(32), LogProb) pathMetricsB <- mkRegFile(0, 1024);
    Reg#(Bool)                    pmBank <- mkReg(False); // False=A is current, True=B is current

    // FSM and Configuration
    Reg#(FSMState)    fsmState <- mkReg(Idle);
    Reg#(Bit#(32))    nStates <- mkReg(0);
    Reg#(Bit#(32))    mObservations <- mkReg(0);
    Reg#(Bit#(32))    currentTime <- mkReg(0); // Represents the time 't' we are computing
    Reg#(Bool)        initialized <- mkReg(False);

    // Loop Counters
    Reg#(Bit#(32))    r_j_counter <- mkReg(0); // Counter for 'j' state
    Reg#(Bit#(32))    r_i_counter <- mkReg(0); // Counter for 'i' state
    
    // Registers for processing
    Reg#(Observation) r_currentObs <- mkReg(0);
    Reg#(LogProb)     r_bestMetric <- mkReg(32'h80000000); // For traceback (maxNeg)
    Reg#(StateIndex)  r_bestState <- mkReg(0);

    // Output FIFO
    FIFO#(Tuple2#(Vector#(1024, StateIndex), LogProb)) resultFifo <- mkFIFO;

    // Helper function to get the correct path metric RegFile
    function RegFile#(Bit#(32), LogProb) pmReadBank();
        return (pmBank == False) ? pathMetricsA : pathMetricsB;
    endfunction
    function RegFile#(Bit#(32), LogProb) pmWriteBank();
        return (pmBank == False) ? pathMetricsB : pathMetricsA;
    endfunction

    // --- FSM Rules ---

    // === Initialization (t=0) ===

    rule do_init_compute (fsmState == Init_ComputeBMU);
        let j = r_j_counter;
        if (j < nStates) begin
            // Compute branch metric for start -> state j
            let startStateMarker = 32'hFFFFFFFF; // Special marker for start
            bmu.computeBranchMetric(startStateMarker, j); 
            fsmState <= Init_GetBMU_Store; // Move to wait state
        end else begin
            // Finished loop
            initialized <= True;
            currentTime <= 1; // We have processed t=0, next is t=1
            smu.advanceTime(); // Tell SMU time has advanced
            pmBank <= !pmBank; // Flip banks. Results for t=0 are in WriteBank.
            r_j_counter <= 0; // Reset counter
            fsmState <= Idle; // Go back to idle
        end
    endrule

    rule do_init_get_and_store (fsmState == Init_GetBMU_Store);
        let j = r_j_counter;
        let startStateMarker = 32'hFFFFFFFF; 

        let branchMetric <- bmu.getBranchMetric();

        // Store in V[0][j] (the write bank)
        Bit#(32) addr = j; // Only need state index for t=0
        pmWriteBank().upd(addr, branchMetric);

        smu.storePredecessor(j, startStateMarker);
        
        r_j_counter <= j + 1; // Increment j counter
        fsmState <= Init_ComputeBMU; // Go back to compute for next j
    endrule

    // === Iteration (t>0) ===

    rule do_iter_compute (fsmState == Iter_ComputeBMU);
        let i = r_i_counter;
        let j = r_j_counter;

        if (j < nStates) begin
            if (i < nStates) begin
                // Compute Branch Metric for (i -> j)
                bmu.computeBranchMetric(i, j);
                fsmState <= Iter_GetBMU_PutACSU;
            end else begin
                // End of 'i' loop for this 'j'
                fsmState <= Iter_GetACSU_Store;
            end
        end else begin
            // End of 'j' loop (finished all states for this time step)
            currentTime <= currentTime + 1; // Advance time
            smu.advanceTime();
            pmBank <= !pmBank; // Flip banks for next time step
            r_j_counter <= 0; // Reset counters
            r_i_counter <= 0;
            fsmState <= Idle; // Go back to idle
        end
    endrule

    rule do_iter_get_bmu_put_acsu (fsmState == Iter_GetBMU_PutACSU);
        let i = r_i_counter;
        let j = r_j_counter;

        // Get V[t-1][i] from the ReadBank
        Bit#(32) prevAddr = i;
        LogProb prevPathMetric = pmReadBank().sub(prevAddr);

        let branchMetric <- bmu.getBranchMetric();

        // Feed to ACSU
        acsu.putCandidate(prevPathMetric, branchMetric, i);
        
        r_i_counter <= i + 1; // Increment i
        fsmState <= Iter_ComputeBMU; // Go back to compute for next i
    endrule

    rule do_iter_get_acsu_store (fsmState == Iter_GetACSU_Store);
        let j = r_j_counter;
        
        let result <- acsu.getResult();
        match {.newPathMetric, .predecessor} = result;

        // Store new path metric V[t][j] in the WriteBank
        Bit#(32) addr = j;
        pmWriteBank().upd(addr, newPathMetric);

        smu.storePredecessor(j, predecessor);
        
        r_i_counter <= 0; // Reset i counter
        r_j_counter <= j + 1; // Increment j counter
        fsmState <= Iter_ComputeBMU; // Go back to compute for next j
    endrule

    // === Traceback ===

    rule do_traceback_findbest (fsmState == Traceback_FindBest_Loop);
        let j = r_j_counter;
        if (j < nStates) begin
            // Read from the last written bank (the ReadBank)
            Bit#(32) addr = j; 
            LogProb finalMetric = pmReadBank().sub(addr);
            
            // "Best" is the largest (least negative) log-probability
            if (finalMetric > r_bestMetric) begin
                r_bestMetric <= finalMetric;
                r_bestState <= j;
            end
            
            r_j_counter <= j + 1;
        end else begin
            // Finished loop, we have r_bestState and r_bestMetric
            fsmState <= Traceback_StartSMU; // NEW: Go to SMU start state
        end
    endrule

    // NEW RULE: This rule tells the SMU to start its FSM
    rule do_traceback_start_smu (fsmState == Traceback_StartSMU);
        smu.startTraceback(r_bestState, currentTime - 1);
        fsmState <= Traceback_GetPath_Enq; // Now we can wait for the result
    endrule

    rule do_traceback_get_path_and_enq (fsmState == Traceback_GetPath_Enq);
        // This rule now calls the non-blocking getPathResult
        let path <- smu.getPathResult();

        // Enqueue the real result
        resultFifo.enq(tuple2(path, r_bestMetric));


        // Enqueue the end-of-sequence marker
        resultFifo.enq(tuple2(replicate(0), 32'hFFFFFFFF));

        r_j_counter <= 0; // Reset counter
        fsmState <= Idle; // Back to idle
    endrule

    // --- Interface Methods ---

    method Action start(Bit#(32) n, Bit#(32) m);
        nStates <= n;
        mObservations <= m;
        currentTime <= 0;
        initialized <= False;
        fsmState <= Idle;

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

    // This is the main input from the testbench, driving the FSM
    method Action processObservation(Observation obs);
        if (fsmState == Idle) begin // Only accept input when idle
            if (obs == 32'hFFFFFFFF) begin
                // End of sequence - perform traceback
                fsmState <= Traceback_FindBest_Loop;
                r_j_counter <= 0; // Use j_counter for traceback loop
                r_bestMetric <= 32'h80000000; // Init to max negative (most likely)
            end else if (obs == 32'h00000000) begin
                // Final marker - output final result
                resultFifo.enq(tuple2(replicate(0), 32'h00000000)); // Special "final" tuple
                initialized <= False;
                currentTime <= 0;
                pmBank <= False;
            end else begin
                // Process observation
                r_currentObs <= obs; // Store the observation
                bmu.setObservation(obs); // Tell BMU the new obs
                r_j_counter <= 0; // Reset j for the loops
                r_i_counter <= 0; // Reset i for the loops
                if (!initialized) begin
                    fsmState <= Init_ComputeBMU;
                end else begin
                    fsmState <= Iter_ComputeBMU;
                end
            end
        end
    endmethod

    method ActionValue#(Tuple2#(Vector#(1024, StateIndex), LogProb)) getResult();
        resultFifo.deq();
        return resultFifo.first();
    endmethod

endmodule

endpackage
