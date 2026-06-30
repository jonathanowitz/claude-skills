#!/bin/bash
# PreToolUse hook: Before `git commit`, if a RED checkpoint is active,
# run the listed test files with name filters and block if ANY tests pass.
#
# RED checkpoint is active when tmp/red-checkpoint.txt exists.
# Format: one entry per line: file_path|test_name_pattern
#   e.g., tests/lib/filters.test.js|selectedModifiers
# The pattern is passed to vitest -t to run only matching tests.
#
# Lifecycle:
#   1. Night-shift or test-writing session creates tmp/red-checkpoint.txt
#   2. Every git commit is gated: matched tests must ALL fail
#   3. When implementation begins, delete tmp/red-checkpoint.txt
#
# Evidence: 2026-04-03 — 4 tests passed vacuously at RED because filterEntries
# ignored the new selectedModifiers param. Caught by USER, not by automation.

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$hook_input" | jq -r '.cwd // empty')

# Only fire on git commit commands
echo "$command" | grep -qE '^\s*git\s+commit' || exit 0

PROJECT_DIR="${cwd:-.}"
CHECKPOINT_FILE="$PROJECT_DIR/tmp/red-checkpoint.txt"

# No checkpoint file = no gate
[ -f "$CHECKPOINT_FILE" ] || exit 0

TOTAL_PASSED=0
TOTAL_FAILED=0
VIOLATIONS=""

# Process each line: file|pattern
while IFS='|' read -r test_file test_pattern; do
  # Skip comments and blank lines
  [[ "$test_file" =~ ^[[:space:]]*# ]] && continue
  [[ -z "$test_file" ]] && continue

  # Run vitest with test name filter
  OUTPUT=$(cd "$PROJECT_DIR" && npx vitest run "$test_file" -t "$test_pattern" 2>&1)

  PASSED=$(echo "$OUTPUT" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+')
  FAILED=$(echo "$OUTPUT" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '[0-9]+')
  PASSED=${PASSED:-0}
  FAILED=${FAILED:-0}

  TOTAL_PASSED=$((TOTAL_PASSED + PASSED))
  TOTAL_FAILED=$((TOTAL_FAILED + FAILED))

  if [ "$PASSED" -gt 0 ]; then
    VIOLATIONS="$VIOLATIONS\n  $test_file (pattern: $test_pattern): $PASSED passed, $FAILED failed"
  fi
done < "$CHECKPOINT_FILE"

if [ "$TOTAL_PASSED" -gt 0 ]; then
  jq -n \
    --arg passed "$TOTAL_PASSED" \
    --arg failed "$TOTAL_FAILED" \
    --arg violations "$VIOLATIONS" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ("RED CHECKPOINT GATE: " + $passed + " test(s) PASS but should all FAIL.\nAll new tests must fail at RED checkpoint — passing tests are vacuous.\nAdd control assertions, then retry.\n\nViolations:" + $violations)
      }
    }'
  exit 0
fi

if [ "$TOTAL_FAILED" -eq 0 ]; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "RED CHECKPOINT GATE: No test failures detected — vitest may not have run correctly."
    }
  }'
  exit 0
fi

# All matched tests fail — gate passes
echo "RED_CHECKPOINT_GATE: All $TOTAL_FAILED test(s) fail as expected. Gate passed."
exit 0
