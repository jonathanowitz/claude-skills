#!/bin/bash
# PostToolUse hook — /review-tests mechanical gate tracker.
#
# Fires after Write or Edit on test files. Tracks cumulative test-writing
# activity in the current worktree. When cumulative count reaches the
# threshold (default 5), creates an active lock at
#   /tmp/review-tests-pending-<worktree_hash>.lock
# which the PreToolUse gate (test-review-gate-pre.sh) enforces.
#
# Lock is cleared by /review-tests skill at Stage 5 when verdict=PASS, OR
# manually with `rm /tmp/review-tests-pending-*.lock` (explicit escape hatch).
#
# Evidence for existence: 2026-04-21 (#680 Slice 0) — wrote 32 unit tests
# across 2 files, skipped /review-tests, went straight to GREEN. Memory
# telemetry target #1 (proactive-gate compliance) was at ~55% baseline;
# advisory memory wasn't enough. Gate is mechanical belt-and-suspenders
# to catch the same miss regardless of skill-invocation path.

set -e

THRESHOLD=5

hook_input=$(cat)
tool_name=$(echo "$hook_input" | jq -r '.tool_name // ""')
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // ""')
cwd=$(echo "$hook_input" | jq -r '.cwd // ""')

case "$tool_name" in Write|Edit) ;; *) exit 0 ;; esac
case "$file_path" in
  */tests/*.test.js|*/tests/*.test.ts|*/e2e/*.spec.js|*/e2e/*.spec.ts) ;;
  *) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

# Resolve to actual worktree root so parallel sessions keyed to the same
# session cwd (main checkout) don't share a lock across different worktrees.
worktree=$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
worktree_hash=$(echo -n "$worktree" | shasum -a 256 | cut -c1-8)
LOCK="/tmp/review-tests-pending-${worktree_hash}.lock"

count_in_file=$(grep -cE "^\s*(it|test)\(" "$file_path" 2>/dev/null || true)
count_in_file=${count_in_file:-0}
[ "$count_in_file" -gt 0 ] || exit 0

# Rewrite lock file: preserve other files' entries, update this file's entry,
# recompute cumulative, rewrite header.
tmp=$(mktemp)
if [ -f "$LOCK" ]; then
  grep -v '^#' "$LOCK" 2>/dev/null | grep -v "^${file_path}	" > "$tmp" || true
fi
printf '%s\t%s\n' "$file_path" "$count_in_file" >> "$tmp"

cumulative=$(awk -F'\t' '{s+=$2} END {print s+0}' "$tmp")

{
  printf '# REVIEW_TESTS gate lock\n'
  printf '# cumulative_tests=%s\n' "$cumulative"
  printf '# threshold=%s\n' "$THRESHOLD"
  printf '# worktree=%s\n' "$worktree"
  printf '# first_seen=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat "$tmp"
} > "$LOCK"
rm -f "$tmp"

if [ "$cumulative" -ge "$THRESHOLD" ]; then
  echo "REVIEW_TESTS_GATE active: $cumulative tests across $(grep -vc '^#' "$LOCK") file(s). Run /review-tests before writing implementation code or running the test suite. Files:"
  grep -v '^#' "$LOCK" | awk -F'\t' '{printf "  %s (%s tests)\n", $1, $2}'
  echo "Lock: $LOCK"
fi
exit 0
