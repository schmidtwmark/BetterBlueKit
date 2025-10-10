#!/bin/bash

set -e

# 1. Run tests with code coverage enabled
echo "Running tests with code coverage..."
swift test --enable-code-coverage

# 2. Find the test binary and coverage data
BINARY_PATH=$(find .build -type f -name BetterBlueKitPackageTests -print -quit)
PROFDATA_PATH=$(find .build -type f -name default.profdata -print -quit)

if [[ -z "$BINARY_PATH" || -z "$PROFDATA_PATH" ]]; then
  echo "❌ Could not find test binary or coverage data."
  exit 1
fi

# 3. Print a human-readable coverage summary
echo
echo "===================="
echo "Code Coverage Report"
echo "===================="
xcrun llvm-cov report "$BINARY_PATH" -instr-profile="$PROFDATA_PATH"

# 4. (Optional) Generate HTML report
if [[ "$1" == "--html" ]]; then
  OUTDIR="coverage-html"
  echo
  echo "Generating HTML coverage report in $OUTDIR/ ..."
  xcrun llvm-cov show "$BINARY_PATH" -instr-profile="$PROFDATA_PATH" -format=html -output-dir="$OUTDIR"
  echo "Open $OUTDIR/index.html in your browser to view the report."
fi