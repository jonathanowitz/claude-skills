#!/bin/bash
set -e

# PostToolUse hook: validate that test files contain real assertions.
# Fires after Write or Edit on files matching e2e/*.spec.js or tests/**/*.test.js
#
# Checks:
# 1. test.todo() calls → DENY (not a real test)
# 2. test.skip() without justification comment → WARN
# 3. test() blocks with no expect()/assert/toBeVisible/toHaveText → WARN
#
# This hook exists because of a 2026-03-19 incident where 15 test.todo()
# stubs were written, called "Stage 3.5 tests," and approved — then two
# showstopper integration bugs went undetected until manual testing.

hook_input=$(cat)
tool_name=$(echo "$hook_input" | jq -r '.tool_name // ""')
file_path=""

if [ "$tool_name" = "Write" ]; then
  file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // ""')
elif [ "$tool_name" = "Edit" ]; then
  file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // ""')
else
  exit 0
fi

# Only check test files
case "$file_path" in
  */e2e/*.spec.js|*/e2e/*.spec.ts|*/tests/*.test.js|*/tests/*.test.ts)
    ;;
  *)
    exit 0
    ;;
esac

# File must exist (Write may have just created it)
if [ ! -f "$file_path" ]; then
  exit 0
fi

content=$(cat "$file_path")

# Check 1: test.todo() calls — these are not real tests
todo_count=$(echo "$content" | grep -cE '(it|test)\.todo\(' 2>/dev/null || true)
if [ "$todo_count" -gt 0 ]; then
  echo "TEST_ASSERTION_CHECK: Found $todo_count test.todo() call(s) in $file_path. test.todo() is NOT a real test — write actual assertions with expect(). See Stage 3.5 of development-process.md."
  exit 0
fi

# Check 2: test.skip() without a reason comment on the same or preceding line
skip_lines=$(echo "$content" | grep -nE '(it|test)\.skip\(' 2>/dev/null || true)
if [ -n "$skip_lines" ]; then
  bad_skips=0
  while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    # Check if the skip line or the line before it has a comment with a reason
    prev=$((lineno - 1))
    context=$(echo "$content" | sed -n "${prev},${lineno}p")
    if ! echo "$context" | grep -qE '//.*\S{3,}'; then
      bad_skips=$((bad_skips + 1))
    fi
  done <<< "$skip_lines"

  if [ "$bad_skips" -gt 0 ]; then
    echo "TEST_ASSERTION_CHECK: Found $bad_skips test.skip() call(s) without justification comments in $file_path. Add a // comment explaining why the test is skipped."
  fi
fi

# Check 3: test() blocks with no assertions
# Count test blocks vs assertion calls
test_count=$(echo "$content" | grep -cE "^\s*(it|test)\(" 2>/dev/null || true)
# Don't count test.describe, test.beforeEach, etc.
assertion_count=$(echo "$content" | grep -cE "(expect\(|\.toBeVisible|\.toHaveText|\.toHaveClass|\.toHaveURL|\.toHaveCount|\.toContainText|\.toPass|assert\.|\.toBe|\.toEqual|\.toBeNull|\.toHaveProperty|\.toBeTruthy|\.toBeFalsy)" 2>/dev/null || true)

if [ "$test_count" -gt 0 ] && [ "$assertion_count" -eq 0 ]; then
  echo "TEST_ASSERTION_CHECK: $file_path has $test_count test block(s) but ZERO assertions. Every test must have at least one expect() call. Placeholder tests give false confidence."
  exit 0
fi

# Ratio check: if tests outnumber assertions 3:1, something's wrong
if [ "$test_count" -gt 3 ] && [ "$assertion_count" -lt "$((test_count / 2))" ]; then
  echo "TEST_ASSERTION_CHECK: $file_path has $test_count test blocks but only $assertion_count assertions. Most test blocks appear to be missing expect() calls. Target: at least 1 assertion per test."
fi

exit 0
