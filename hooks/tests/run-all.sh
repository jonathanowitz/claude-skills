#!/usr/bin/env bash
# Run every hook test suite in this directory.
#
# Exists because manual-invocation-only test files are the same class of drift
# deploy-hooks.sh was written to fix: a suite nobody has a single command for is
# a suite that stops being run. One entry point, non-zero if any suite fails.
#
# Usage: ./run-all.sh

set -uo pipefail
shopt -s nullglob

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
self="$(basename "${BASH_SOURCE[0]}")"

total_pass=0; total_fail=0; failed_suites=()

for t in "$DIR"/test-*.sh; do
  name="$(basename "$t")"
  [ "$name" = "$self" ] && continue
  printf '\n>>> %s\n' "$name"
  out=$(bash "$t" 2>&1); status=$?
  printf '%s\n' "$out" | tail -2
  # Parse both suite formats: "passed=N failed=N" and "=== Summary: N passed, N failed ==="
  p=$(printf '%s' "$out" | sed -nE 's/.*passed=([0-9]+) failed=[0-9]+.*/\1/p;s/.*Summary: ([0-9]+) passed, [0-9]+ failed.*/\1/p' | tail -1)
  f=$(printf '%s' "$out" | sed -nE 's/.*passed=[0-9]+ failed=([0-9]+).*/\1/p;s/.*Summary: [0-9]+ passed, ([0-9]+) failed.*/\1/p' | tail -1)
  total_pass=$((total_pass + ${p:-0}))
  total_fail=$((total_fail + ${f:-0}))
  # A suite that exits non-zero without a parsable tally still counts as failed.
  [ "$status" -eq 0 ] || failed_suites+=("$name")
done

echo
echo "=============================================="
echo "TOTAL: passed=$total_pass failed=$total_fail"
if [ "${#failed_suites[@]}" -gt 0 ]; then
  echo "FAILED SUITES: ${failed_suites[*]}"
  exit 1
fi
echo "all suites green"
exit 0
