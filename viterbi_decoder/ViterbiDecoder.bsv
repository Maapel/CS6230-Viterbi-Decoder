// Viterbi Decoder in Bluespec System Verilog

package ViterbiDecoder;

import Vector::*;
import FIFO::*;
import RegFile::*;
import List::*;

// FIX: Added a compliant integer adder to avoid using the '+' operator,
// as required by the project specification.
function Bit#(32) int_add(Bit#(32) a, Bit#(32) b);
    Bit#(33) sum = 0;
    Bit#(1) carry_in = 0;
    for (Integer i = 0; i < 32; i = i + 1) begin
        Bit#(1) a_i = a[i];
        Bit#(1) b_i = b[i];
        
        // Sum bit = a_i ^ b_i ^ carry_in
        Bit#(1) sum_i = a_i ^ b_i ^ carry_in;
        
        // Carry_out = (a_i & b_i) | (a_i & carry_in) | (b_i & carry_in)
        Bit#(1) carry_out = (a_i & b_i) | (a_i & carry_in) | (b_i & carry_in);
        
        sum[i] = sum_i;
        carry_in = carry_out;
    end
    return sum[31:0];
endfunction

// Helper function for floating-point addition (placeholder)
function Bit#(32) fp_add(Bit#(32) a, Bit#(32) b);
    // NOTE: This is a placeholder as you noted.
    // In synthesis, this will be replaced with the Verilog FP adder module.
    let result_exp = (a[30:23] >= b[30:23]) ? a[30:23] : b[30:23];
    Bit#(32) result = {a[31], result_exp, a[22:0]};
    return result;
endfunction

// Interface for the Viterbi Decoder
interface ViterbiDecoder_ifc;
    method Action start(Bit#(32) n, Bit#(32) m);
    method Action loadA(Bit#(32) addr, Bit#(32) data);
    method Action loadB(Bit#(32) addr, Bit#(32) data);
    method Action loadInput(Bit#(32) data);
    method Action process(Bit#(32) obs);
    method ActionValue#(Bit#(32)) getOutput;
endinterface

// Viterbi Decoder Module
module mkViterbiDecoder(ViterbiDecoder_ifc);

    Reg#(Bit#(32)) n_states <- mkReg(0);
    Reg#(Bit#(32)) m_observations <- mkReg(0);

    RegFile#(Bit#(32), Bit#(32)) a_matrix <- mkRegFile(0, 1024);
    RegFile#(Bit#(32), Bit#(32)) b_matrix <- mkRegFile(0, 1024);

    FIFO#(Bit#(32)) input_fifo <- mkFIFO;
    FIFO#(Bit#(32)) output_fifo <- mkFIFO;



    RegFile#(Bit#(32), Bit#(32)) prob <- mkRegFile(0, 1024);
    // FIX: Declared temp_prob at module scope for the iterative step
    RegFile#(Bit#(32), Bit#(32)) temp_prob <- mkRegFile(0, 1024);
    RegFile#(Bit#(32), Bit#(32)) backtrace <- mkRegFile(0, 1024);
    Reg#(Bit#(32)) t <- mkReg(0);

    method Action start(Bit#(32) n, Bit#(32) m);
        n_states <= n;
        m_observations <= m;
        t <= 0;
    endmethod

    method Action loadA(Bit#(32) addr, Bit#(32) data);
        a_matrix.upd(addr, data);
    endmethod

    method Action loadB(Bit#(32) addr, Bit#(32) data);
        b_matrix.upd(addr, data);
    endmethod

    method Action loadInput(Bit#(32) data);
        input_fifo.enq(data);
    endmethod

    method ActionValue#(Bit#(32)) getOutput;
        output_fifo.deq;
        return output_fifo.first;
    endmethod

    method Action process(Bit#(32) obs);
        // FIX: Removed let-bindings for n_val, m_val, t_val

        if (obs == 32'hFFFFFFFF) begin
            // Termination step
            Bit#(32) max_val = 32'h80000000;
            Integer max_state = -1;
            // FIX: Use unpack(n_states) inline
            Integer n_val_term = unpack(n_states);
            for (Integer i = 0; i < n_val_term; i = i + 1) begin
                let p = prob.sub(fromInteger(i));
                if (p > max_val) begin
                    max_val = p;
                    max_state = i;
                end
            end

            // Traceback
            Vector#(1024, Bit#(32)) path = replicate(0);
            // FIX: Use unpack(t) inline
            Integer t_val_path = unpack(t);
            path[(t_val_path - 1) % 1024] = fromInteger(max_state);
            // FIX: Use unpack(t) inline
            Integer t_val_term = unpack(t);
            Integer n_val_term = unpack(n_states);
            for (Integer i = t_val_term - 2; i >= 0; i = i - 1) begin
                // FIX: Use unpack(n_states) inline
                Integer path_val = unpack(path[(i+1)%1024]);
                let bt_addr = fromInteger((i+1) * n_val_term + path_val);
                path[i%1024] = backtrace.sub(bt_addr);
            end

            // Enqueue output
            // FIX: Use unpack(t) inline
            Integer t_val_out = unpack(t);
            for (Integer i = 0; i < t_val_out; i = i + 1) begin
                output_fifo.enq(int_add(path[i%1024], fromInteger(1))); // FIX: Use fromInteger(1)
            end
            output_fifo.enq(32'hFFFFFFFF);
            t <= 0;
        end
        else if (obs == 32'h00000000) begin
            output_fifo.enq(0);
        end
        else begin
            Integer t_val_proc = unpack(t);
            if (t_val_proc == 0) begin // FIX: Use unpack(t) inline
                // Initialization step
                // FIX: Use unpack(n_states) inline
                Integer n_val_init = unpack(n_states);
                Integer m_val_init = unpack(m_observations);
                Integer obs_val_init = unpack(obs);
                for (Integer j = 0; j < n_val_init; j = j + 1) begin
                    let a = a_matrix.sub(fromInteger(j));
                    // FIX: Use unpack(m_observations) inline
                    let b_addr = fromInteger(j * m_val_init + obs_val_init - 1);
                    let b = b_matrix.sub(b_addr);
                    prob.upd(fromInteger(j), fp_add(a, b));
                    backtrace.upd(fromInteger(j), 0);
                end
            end else begin
                // Iterative step: Read from 'prob', write to 'temp_prob'
                // FIX: Use unpack(n_states) inline
                Integer n_val_iter = unpack(n_states);
                Integer m_val_iter = unpack(m_observations);
                Integer obs_val_iter = unpack(obs);
                Integer t_val_iter = unpack(t);
                for (Integer j = 0; j < n_val_iter; j = j + 1) begin
                    Bit#(32) max_val = 32'h80000000;
                    Integer max_state = -1;
                    // FIX: Use unpack(n_states) inline
                    for (Integer i = 0; i < n_val_iter; i = i + 1) begin
                        let p = prob.sub(fromInteger(i));
                        // FIX: Use unpack(n_states) inline
                        let a_addr = fromInteger(i * n_val_iter + j);
                        let a = a_matrix.sub(a_addr);
                        let val = fp_add(p, a);
                        if (val > max_val) begin
                            max_val = val;
                            max_state = i;
                        end
                    end
                    // FIX: Use unpack(m_observations) inline
                    let b_addr = fromInteger(j * m_val_iter + obs_val_iter - 1);
                    let b = b_matrix.sub(b_addr);
                    temp_prob.upd(fromInteger(j), fp_add(max_val, b));
                    // FIX: Use unpack(t) and unpack(n_states) inline
                    let bt_addr = fromInteger(t_val_iter * n_val_iter + j);
                    backtrace.upd(bt_addr, fromInteger(max_state));
                end

                // Copy temp_prob back to prob
                // FIX: Use unpack(n_states) inline
                Integer n_val_copy = unpack(n_states);
                for (Integer i = 0; i < n_val_copy; i = i + 1) begin
                    prob.upd(fromInteger(i), temp_prob.sub(fromInteger(i)));
                end
            end
            // FIX: Use compliant int_add and fromInteger(1)
            t <= int_add(t, fromInteger(1));
        end
    endmethod

endmodule

endpackage
