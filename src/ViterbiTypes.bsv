// ViterbiTypes.bsv
// Global type definitions for the Viterbi Decoder project

package ViterbiTypes;

import Vector::*;

// Basic types
typedef Bit#(32) LogProb;        // IEEE 754 single-precision floating-point for log-probabilities
typedef Bit#(32) StateIndex;     // State indices (assuming N <= 32 for this implementation)
typedef Bit#(32) Observation;    // Observation values

// Interface for the Branch Metric Unit (BMU)
interface BmuIfc;
    // Configuration
    method Action configure(Bit#(32) nStates, Bit#(32) mObservations);

    // Data loading
    method Action loadTransitionProb(Bit#(32) addr, LogProb data);
    method Action loadEmissionProb(Bit#(32) addr, LogProb data);

    // Input: observation and state indices
    method Action setObservation(Observation obs);
    method Action computeBranchMetric(StateIndex fromState, StateIndex toState);

    // Output: computed branch metric (log P(from->to) + log P(obs|to))
    method ActionValue#(LogProb) getBranchMetric();
endinterface

// Interface for the Add-Compare-Select Unit (ACSU)
interface AcsuIfc;
    // Feed one candidate path metric + branch metric
    method Action putCandidate(LogProb pathMetric, LogProb branchMetric, StateIndex predIndex);

    // Signal end of candidates and get result
    method ActionValue#(Tuple2#(LogProb, StateIndex)) getResult();
endinterface

// Interface for the Survivor Memory Unit (SMU)
interface SmuIfc;
    // Configuration
    method Action configure(Bit#(32) nStates);

    // Store predecessor for a state at current time step
    method Action storePredecessor(StateIndex state, StateIndex predecessor);

    // Advance to next time step
    method Action advanceTime();

    // Get the complete path for traceback
    method ActionValue#(Vector#(1024, StateIndex)) getSurvivorPath(StateIndex finalState, Bit#(32) pathLength);
endinterface

// Interface for the top-level Viterbi Decoder
interface ViterbiDecoderIfc;
    // Configuration
    method Action start(Bit#(32) nStates, Bit#(32) mObservations);

    // Data loading
    method Action loadTransitionProb(Bit#(32) addr, LogProb data);
    method Action loadEmissionProb(Bit#(32) addr, LogProb data);

    // Processing
    method Action processObservation(Observation obs);

    // Results
    method ActionValue#(Tuple2#(Vector#(1024, StateIndex), LogProb)) getResult();
endinterface

endpackage
