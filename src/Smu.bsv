// Smu.bsv
// Survivor Memory Unit for Viterbi Decoder
// Stores predecessor states and performs traceback to reconstruct the optimal path

package Smu;

import ViterbiTypes::*;
import Vector::*;
import RegFile::*;

// Survivor Memory Unit Module
module mkSmu(SmuIfc);
    // Memory to store predecessors: predecessor[t][state] = previous state at time t for this state
    // Using a 2D structure: time * N + state
    RegFile#(Bit#(32), StateIndex) predecessorMem <- mkRegFile(0, 32*1024); // Support up to 1024 time steps, 32 states

    // Configuration
    Reg#(Bit#(32)) nStates <- mkReg(0);
    Reg#(Bit#(32)) currentTime <- mkReg(0);

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

    method ActionValue#(Vector#(1024, StateIndex)) getSurvivorPath(StateIndex finalState, Bit#(32) pathLength);
        Vector#(1024, StateIndex) path = replicate(0);

        // Start from the final state
        StateIndex currentState = finalState;
        path[pathLength-1] = currentState + 1; // Convert to 1-indexed

        // Trace back through predecessors
        for (Integer t = pathLength-2; t >= 0; t = t - 1) begin
            Bit#(32) timeStep = fromInteger(t + 1); // Next time step
            Bit#(32) addr = timeStep * nStates + currentState;
            currentState = predecessorMem.sub(addr);
            path[t] = currentState + 1; // Convert to 1-indexed
        end

        return path;
    endmethod

endmodule

endpackage
