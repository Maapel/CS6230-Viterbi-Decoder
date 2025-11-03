# Makefile for CS6230 Viterbi Decoder Project

# --- Configuration ---
# Bluespec Compiler
BSC = bsc

# Bluespec flags for 2021.12.1 version:
# -sim: Simulation mode
# -bdir: Directory for object files
# -simdir: Directory for simulation executable
# -p +: Path to find .v files
# -g: Top module to synthesize
BSC_COMPILE_FLAGS = -sim -bdir Build -simdir Sim -p +

# Simulation executable name
SIM_EXE = Sim/a.out

# --- File Definitions ---
BSV_FILES = ViterbiDecoder.bsv Tb.bsv
VERILOG_FILES = FloatingPointAdder.v

# --- Main Targets ---
all: $(SIM_EXE)

# Rule to build the simulation executable
$(SIM_EXE): Build $(BSV_FILES) $(VERILOG_FILES)
	@echo "Compiling BSV files..."
	$(BSC) $(BSC_COMPILE_FLAGS) -g mkViterbiDecoder ViterbiDecoder.bsv
	$(BSC) $(BSC_COMPILE_FLAGS) -g mkTb Tb.bsv
	@echo "Compiling Verilog file..."
	$(BSC) $(BSC_COMPILE_FLAGS) FloatingPointAdder.v
	@echo "Linking simulation..."
	$(BSC) -sim -e mkTb -o $(SIM_EXE) -bdir Build

Build:
	mkdir -p Build Sim

# Rule to run the simulation
run_sim: $(SIM_EXE)
	@echo "Running hardware simulation..."
	$(SIM_EXE) > sim.log
	@echo "Simulation complete. 'Output.dat' generated."

# Rule to run the reference model
run_ref:
	@echo "Running Python reference model..."
	python3 ReferenceModel.py
	@echo "Reference model complete. 'Ref_Output.dat' generated."

# Rule to check the results
check: run_sim run_ref
	@echo "Comparing hardware output with reference output..."
	@diff -w Output.dat Ref_Output.dat > diff.log
	@if [ $$? -eq 0 ]; then \
		echo "✅ ✅ ✅ TEST PASSED ✅ ✅ ✅"; \
	else \
		echo "❌ ❌ ❌ TEST FAILED ❌ ❌ ❌"; \
		echo "See diff.log for differences."; \
	fi

# Rule to clean up generated files
clean:
	@echo "Cleaning up..."
	rm -rf Verilog Build Sim sim.log *.bo *.bi
	rm -f Output.dat Ref_Output.dat diff.log
	rm -f a.out

.PHONY: all run_sim run_ref check clean
