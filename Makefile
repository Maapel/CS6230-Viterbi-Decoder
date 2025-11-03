# CS6230 Viterbi Decoder Project Makefile
# Professional build system with proper directory structure

# --- Configuration ---
# Bluespec Compiler
BSC = bsc

# Bluespec flags for simulation
BSC_SIM_FLAGS = -sim -bdir build -simdir build -p src:src/lib:src/test +

# Simulation executable
SIM_EXE = build/a.out

# Source files
BSV_SOURCES = src/ViterbiTypes.bsv src/Bmu.bsv src/Acsu.bsv src/Smu.bsv src/ViterbiDecoder.bsv src/test/Tb.bsv
VERILOG_SOURCES = src/lib/FloatingPointAdder.v

# --- Main Targets ---
.PHONY: all clean test help

all: $(SIM_EXE)

# Build simulation executable
$(SIM_EXE): build $(BSV_SOURCES) $(VERILOG_SOURCES)
	@echo "=== Building BSV Sources ==="
	$(BSC) $(BSC_SIM_FLAGS) -g mkViterbiDecoder src/ViterbiDecoder.bsv
	$(BSC) $(BSC_SIM_FLAGS) -g mkTb src/test/Tb.bsv
	@echo "=== Compiling Verilog Sources ==="
	$(BSC) $(BSC_SIM_FLAGS) src/lib/FloatingPointAdder.v
	@echo "=== Linking Simulation ==="
	$(BSC) -sim -e mkTb -o $(SIM_EXE) -bdir build

build:
	mkdir -p build

# Run simulation
run_sim: $(SIM_EXE)
	@echo "=== Running Hardware Simulation ==="
	$(SIM_EXE) > sim.log
	@echo "Simulation complete. Output written to sim.log"

# Run reference model
run_ref:
	@echo "=== Running Python Reference Model ==="
	cd verification/reference_model && python3 ReferenceModel.py
	@echo "Reference model complete. Output: verification/reference_model/Ref_Output.dat"

# Run complete test suite
test: clean all run_sim run_ref
	@echo "=== Comparing Results ==="
	@if diff -w build/Output.dat verification/reference_model/Ref_Output.dat > diff.log; then \
		echo "✅ ✅ ✅ TEST PASSED ✅ ✅ ✅"; \
		echo "Hardware output matches reference model."; \
	else \
		echo "❌ ❌ ❌ TEST FAILED ❌ ❌ ❌"; \
		echo "Differences found. See diff.log for details."; \
		exit 1; \
	fi

# Test with small dataset
test_small: test

# Test with huge dataset (if available)
test_huge: clean all
	@echo "=== Testing with Huge Dataset ==="
	# Update paths in reference model for huge test case
	sed -i 's/small/huge/g' verification/reference_model/ReferenceModel.py
	make run_sim run_ref
	@if diff -w build/Output.dat verification/reference_model/Ref_Output.dat > diff.log; then \
		echo "✅ ✅ ✅ HUGE TEST PASSED ✅ ✅ ✅"; \
	else \
		echo "❌ ❌ ❌ HUGE TEST FAILED ❌ ❌ ❌"; \
	fi
	# Restore small test case
	sed -i 's/huge/small/g' verification/reference_model/ReferenceModel.py

# Clean build artifacts
clean:
	@echo "=== Cleaning Build Artifacts ==="
	rm -rf build sim.log diff.log
	rm -f verification/reference_model/Ref_Output.dat
	rm -f build/Output.dat

# Clean everything including reports
clean_all: clean
	rm -rf reports/

# Show help
help:
	@echo "CS6230 Viterbi Decoder Project Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  all        - Build the simulation executable"
	@echo "  run_sim    - Run the hardware simulation"
	@echo "  run_ref    - Run the Python reference model"
	@echo "  test       - Run complete test suite (small dataset)"
	@echo "  test_huge  - Run test with huge dataset"
	@echo "  clean      - Clean build artifacts"
	@echo "  clean_all  - Clean everything"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Project structure:"
	@echo "  src/              - BSV source files"
	@echo "  verification/     - Reference models and test cases"
	@echo "  build/            - Build artifacts"
	@echo "  reports/          - Synthesis reports"

# Development targets
check_syntax:
	@echo "=== Checking BSV Syntax ==="
	$(BSC) -p src:src/lib +RTS -K100M -RTS -check -g mkViterbiDecoder src/ViterbiDecoder.bsv

# Create reports directory for synthesis results
reports:
	mkdir -p reports

# Default target
.DEFAULT_GOAL := help
