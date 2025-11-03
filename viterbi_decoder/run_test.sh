#!/bin/bash
# run_test.sh
# Automation script for the Viterbi Decoder project.

echo "--- Viterbi Decoder Test Flow ---"

# Step 1: Clean previous run
echo "🧹 [1/4] Cleaning previous run..."
make clean > build.log
if [ $? -ne 0 ]; then
    echo "❌ Clean failed. Check build.log for details."
    exit 1
fi
echo "Clean successful."

# Step 2: Build the simulation
# We check for a build failure
echo "🛠️  [2/4] Building simulation..."
make > build.log
if [ $? -ne 0 ]; then
    echo "❌ BUILD FAILED. Check build.log for details."
    exit 1
fi
echo "Build successful."

# Step 3: Run the check
# The 'check' target in the Makefile runs sim, ref, and diff
echo "🚀 [3/4] Running simulation and reference model..."
make check > check.log

# Step 4: Report final status
echo "🏁 [4/4] Checking final result..."
if grep -q "TEST PASSED" check.log; then
    echo "✅ ✅ ✅ All tests PASSED. 'Output.dat' matches 'Ref_Output.dat'."
    rm -f build.log check.log
    exit 0
else
    echo "❌ ❌ ❌ TEST FAILED. Outputs do not match."
    echo "Details:"
    cat check.log
    rm -f build.log # keep check.log for debugging
    exit 1
fi
