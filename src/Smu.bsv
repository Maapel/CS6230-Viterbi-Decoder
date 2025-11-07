// Smu.bsv
// Survivor Memory Unit for Viterbi Decoder
// Stores predecessor states and performs traceback to reconstruct the optimal path
// This version uses an FSM for traceback instead of a non-synthesizable for loop.

package Smu;

import ViterbiTypes::*;
import Vector::*;
import RegFile::*;
import FIFO::*;

// FSM states for traceback
typedef enum {
    Idle,           // Waiting for startTraceback() call
    TracingBack     // Performing traceback one step per cycle
} SmuState deriving (Bits, Eq);

// Survivor Memory Unit Module
module mkSmu(SmuIfc);
    // Memory to store predecessors: predecessor[t][state] = previous state at time t for this state
    // Using a 2D structure: time * N + state
    RegFile#(Bit#(32), StateIndex) predecessorMem <- mkRegFile(0, 32*1024); // Support up to 1024 time steps, 32 states

    // Configuration
    Reg#(Bit#(32)) nStates <- mkReg(0);
    Reg#(Bit#(32)) currentTime <- mkReg(0);

    // FSM state for traceback
    Reg#(SmuState) smuState <- mkReg(Idle);
    Reg#(Bit#(32)) tracebackCounter <- mkReg(0); // Counter for traceback steps
    Reg#(StateIndex) currentTracebackState <- mkReg(0); // Current state during traceback
    Reg#(Vector#(1024, StateIndex)) tracebackPath <- mkReg(replicate(0)); // Path being built
    Reg#(Bit#(32)) currentPathLength <- mkReg(0); // Store pathLength for the rule

    // Result FIFO
    FIFO#(Vector#(1024, StateIndex)) resultFifo <- mkFIFO;

    // FSM rule to perform traceback one step per cycle
    rule performTraceback (smuState == TracingBack);
        let counter = tracebackCounter;
        let currentState = currentTracebackState;
        let path = tracebackPath;
        let pathLength = currentPathLength;

        if (counter < pathLength - 1) begin
            // Perform one traceback step
            Bit#(32) timeStep = pathLength - 1 - counter; // Start from last time step
            Bit#(32) addr = timeStep * nStates + currentState;
            StateIndex nextState = predecessorMem.sub(addr);

            // Update path and state
            path[timeStep - 1] = nextState + 1; // Convert to 1-indexed
            tracebackPath <= path;
            currentTracebackState <= nextState;

            // Increment counter
            tracebackCounter <= counter + 1;
        end else begin
            // Traceback complete, enqueue result
            resultFifo.enq(tracebackPath);
            smuState <= Idle;
        end
    endrule

    method Action configure(Bit#(32) n);
        nStates <= n;
        currentTime <= 0;
    endmethod

    method Action storePredecessor(StateIndex state, StateIndex predecessor);
        // Store predecessor for current time step and state
        Bit#(32) addr = currentTime * nStates + state;
        predecessorMem.upd(addr, predecessor);
    endmethod

    method Action advanceTime();
        currentTime <= currentTime + 1;
    endmethod

    // Non-blocking traceback interface
    method Action startTraceback(StateIndex finalState, Bit#(32) pathLength);
        // Start the FSM for traceback
        smuState <= TracingBack;
        tracebackCounter <= 0;
        currentTracebackState <= finalState;
        currentPathLength <= pathLength;

        // Initialize the path with the final state
        Vector#(1024, StateIndex) initPath = replicate(0);
        Bit#(32) lastIdx = pathLength - 1;
        initPath[lastIdx] = finalState + 1; // Convert to 1-indexed
        tracebackPath <= initPath;
    endmethod

    method ActionValue#(Vector#(1024, StateIndex)) getPathResult();
        // The actual result is enqueued by the FSM rule
        resultFifo.deq();
        return resultFifo.first();
    endmethod

endmodule

endpackage
