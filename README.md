# CS6230 Viterbi Decoder Project

## Overview

This project implements a hardware Viterbi decoder in Bluespec SystemVerilog (BSV) for the CS6230 Computer-Aided Design for VLSI course. The decoder solves the Hidden Markov Model (HMM) inference problem using the Viterbi algorithm with logarithmic probability computations.

### Key Features

- **Custom IEEE 754 Floating-Point Adder**: Implements single-precision floating-point addition from first principles using bitwise operations, avoiding the prohibited `+` and `*` operators
- **Modular Architecture**: Follows the standard Viterbi decoder decomposition into BMU (Branch Metric Unit), ACSU (Add-Compare-Select Unit), and SMU (Survivor Memory Unit)
- **High Precision Verification**: Uses numpy.float32 for bit-exact precision matching between hardware and software reference models
- **Professional Project Structure**: Organized according to industry best practices with clear separation of concerns

## Project Structure

```
.
├── src/                          # BSV source files
│   ├── ViterbiTypes.bsv         # Type definitions and interfaces
│   ├── ViterbiDecoder.bsv       # Top-level decoder module
│   ├── Bmu.bsv                  # Branch Metric Unit
│   ├── Acsu.bsv                 # Add-Compare-Select Unit
│   ├── Smu.bsv                  # Survivor Memory Unit
│   ├── lib/
│   │   ├── FPAdder.bsv          # Custom IEEE 754 FP adder
│   │   └── FloatingPointAdder.v # Legacy Verilog adder
│   └── test/
│       └── Tb.bsv               # Testbench
├── verification/                 # Verification framework
│   ├── reference_model/
│   │   └── ReferenceModel.py     # Python reference with numpy.float32
│   └── test_cases/              # Test data (small and huge datasets)
├── build/                       # Build artifacts (generated)
├── reports/                     # Synthesis reports (generated)
├── CAD_for_VLSI_Project_spec/   # Original project specifications
├── Makefile                     # Build system
└── README.md                    # This file
```

## Architecture

The Viterbi decoder follows the standard three-unit architecture:

1. **Branch Metric Unit (BMU)**: Computes transition and emission log-probabilities for each state transition
2. **Add-Compare-Select Unit (ACSU)**: Performs the core Viterbi recursion: max over predecessors of (previous path metric + branch metric)
3. **Survivor Memory Unit (SMU)**: Stores predecessor information and performs traceback to reconstruct the optimal path

The custom IEEE 754 floating-point adder uses:
- Bitwise full-adder logic for mantissa addition
- Proper exponent alignment and normalization
- Rounding to nearest even
- Support for gradual underflow and special values

## Building and Testing

### Prerequisites

- Bluespec SystemVerilog compiler (`bsc`)
- Python 3 with numpy
- Make

### Quick Start

```bash
# Build the project
make all

# Run the complete test suite
make test

# Run individual components
make run_sim    # Hardware simulation
make run_ref    # Python reference model

# Clean build artifacts
make clean
```

### Test Datasets

The project includes two test datasets:
- **Small**: Basic functionality test (N=2 states, M=4 observations)
- **Huge**: Performance and stress test (larger matrices)

```bash
# Test with huge dataset
make test_huge
```

## Verification Methodology

The verification framework ensures correctness through:

1. **Bit-Exact Precision**: Hardware uses 32-bit IEEE 754, reference model uses numpy.float32
2. **Automated Comparison**: Makefile-driven test suite compares outputs automatically
3. **Comprehensive Coverage**: Tests both small and large datasets
4. **Regression Testing**: Clean rebuild for each test run

## Synthesis and Performance

For FPGA synthesis in the Shakti environment:

```bash
# Generate Verilog for synthesis
bsc -verilog -g mkViterbiDecoder src/ViterbiDecoder.bsv

# Synthesize with your target toolchain
# (Vivado, Quartus, etc.)
```

### Expected Performance Metrics

- **Baseline**: Initial functionally correct implementation
- **Optimized**: Pipelined FP adder for improved Fmax
- **Area**: Resource usage (LUTs, FFs, DSPs)
- **Power**: Dynamic and static power estimates

## Key Design Decisions

1. **No Native Arithmetic**: Strict adherence to project constraint - all addition implemented with bitwise operations
2. **Modular Interfaces**: Clean separation between BMU, ACSU, and SMU for maintainability
3. **Precision Matching**: numpy.float32 ensures verification accuracy
4. **Professional Structure**: Industry-standard directory layout and build system

## Team Contributions

- **Architecture Design**: BMU-ACSU-SMU decomposition
- **FP Adder Implementation**: Bitwise IEEE 754 single-precision adder
- **Verification Framework**: numpy.float32 reference model and automated testing
- **Build System**: Professional Makefile with comprehensive targets

## Maximum Clock Frequency Achieved

*[To be determined after synthesis]*

## Future Improvements

- Pipeline the FP adder for higher throughput
- Implement resource sharing for area optimization
- Add support for denormalized numbers in FP adder
- Extend test coverage with randomized test cases

---

**Note**: This implementation strictly follows the CS6230 project specifications and academic integrity guidelines. All code is original and developed from first principles.
