#!/bin/bash
# PostToolUse hook — /review-tests mechanical gate tracker.
#
# Fires after Write or Edit on test files. Tracks cumulative test-writing
# activity in the current worktree. When cumulative count reaches the
# threshold (default 5), creates an active lock at
#   /tmp/review-tests-pending-<worktree_hash>.lock
# which the PreToolUse gate (test-review-gate-pre.sh) enforces.
#
# Lock is cleared by review-tests-clear.sh (invoked by /review-tests Stage 5), which
# records the verdict and appends a CLEARED line to the audit log. A bare
# `rm /tmp/review-tests-pending-*.lock` still works as an escape hatch, but it is no
# longer INVISIBLE: this hook arms a stamp file alongside the lock, and a stamp left
# without its lock is reported to the audit log as UNRECORDED_CLEAR on the next write.
# (USER 2026-07-24 — the two clears were indistinguishable from each other, so
# "is this justified or sloppy?" could only be answered by the agent that did it.)
#
# Evidence for existence: 2026-04-21 (#680 Slice 0) — wrote 32 unit tests
# across 2 files, skipped /review-tests, went straight to GREEN. Memory
# telemetry target #1 (proactive-gate compliance) was at ~55% baseline;
# advisory memory wasn't enough. Gate is mechanical belt-and-suspenders
# to catch the same miss regardless of skill-invocation path.

set -e

# Sourced for the audit helpers (audit_log / stamp_path / detect_unrecorded_clear) only.
#
# GUARDED, and the fallbacks are no-ops rather than an abort. deploy-hooks.sh deploys an
# EXPLICIT FILE LIST by design, so deploying this hook without review-tests-count.sh is normal
# usage — and an unguarded `.` under `set -e` would kill the hook before it read its input. A
# PreToolUse/PostToolUse hook that dies does not block anything: the gate would fail OPEN and
# silently stop enforcing, which is far worse for this feature than losing the audit line. So
# a missing helper degrades to "gate still enforces, audit goes dark", never "gate evaporates".
SHARED="$(dirname "$0")/review-tests-count.sh"
if [ -f "$SHARED" ]; then
  . "$SHARED"
else
  audit_log() { :; }
  detect_unrecorded_clear() { return 1; }
  stamp_path() { echo "/tmp/review-tests-armed-$(echo -n "$1" | shasum -a 256 | cut -c1-8).stamp"; }
fi

# NOTE: this hook deliberately keeps its own inline test count below rather than adopting
# count_tests_in() — the two implementations DO differ (count_tests_in also matches `it.each`
# /`test.only` modifier forms), so switching would change how fast the gate arms. That
# reconciliation is a separate change; doing it here would smuggle a behavior change into an
# instrumentation commit. See review-tests-count.sh's COUNTER STATUS header.

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

# Before touching lock state: if a stamp survives with no lock, the lock was removed by hand
# rather than through review-tests-clear.sh. Record that once, then continue normally — this
# is instrumentation, never an additional block.
detect_unrecorded_clear "$worktree" || true

count_in_file=$(grep -cE "^\s*(it|test)\(" "$file_path" 2>/dev/null || true)
count_in_file=${count_in_file:-0}
[ "$count_in_file" -gt 0 ] || exit 0

# Rewrite lock file: preserve other files' entries, update this file's entry,
# recompute cumulative, rewrite header.
tmp=$(mktemp)
if [ -f "$LOCK" ]; then
  # awk with an exact string compare — a file path is not a regex. `grep -v "^${file_path}\t"`
  # treats `.` as any-character, so an entry for `foo.test.js` would also match and silently
  # drop a sibling `fooXtest.js`.
  grep -v '^#' "$LOCK" 2>/dev/null | awk -F'\t' -v p="$file_path" '$1 != p' > "$tmp" || true
fi
printf '%s\t%s\n' "$file_path" "$count_in_file" >> "$tmp"

cumulative=$(awk -F'\t' '{s+=$2} END {print s+0}' "$tmp")

lock_new=$(mktemp "${LOCK}.XXXXXX")
{
  printf '# REVIEW_TESTS gate lock\n'
  printf '# cumulative_tests=%s\n' "$cumulative"
  printf '# threshold=%s\n' "$THRESHOLD"
  printf '# worktree=%s\n' "$worktree"
  printf '# first_seen=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat "$tmp"
} > "$lock_new"
# Build then RENAME, never truncate in place. `> "$LOCK"` empties the file before the block
# runs, and the PreToolUse gate reads this same file — a read landing in that window parses
# cumulative_tests as empty, defaults it to 0, and silently ALLOWS a write the gate should
# have denied. rename(2) is atomic: a concurrent reader sees the old lock or the new one,
# never an empty one. (Cross-model review, 2026-07-24.)
#
# The staging file is mktemp'd, NOT a fixed "$LOCK.new": two sessions writing tests in the same
# worktree would otherwise open the identical staging path for truncating write and interleave
# their content. rename(2) being atomic does not help when the source is already garbage.
mv -f "$lock_new" "$LOCK"
rm -f "$tmp"

if [ "$cumulative" -ge "$THRESHOLD" ]; then
  # Arm the stamp on the ARMING edge only (no stamp yet), so the audit log gets one ARMED
  # line per gate episode rather than one per test-file write.
  STAMP=$(stamp_path "$worktree")
  if [ ! -f "$STAMP" ]; then
    date -u +%Y-%m-%dT%H:%M:%SZ > "$STAMP" 2>/dev/null || true
    audit_log "ARMED" "$worktree" "tests=$cumulative" \
      "files=$(grep -vc '^#' "$LOCK" 2>/dev/null || echo 0)"
  fi

  # `grep -vc` exits 1 when the count is 0, and under `set -e` an unguarded command
  # substitution propagates that — crashing the hook on an entries-only lock.
  echo "REVIEW_TESTS_GATE active: $cumulative tests across $(grep -vc '^#' "$LOCK" 2>/dev/null || echo 0) file(s). Run /review-tests before writing implementation code or running the test suite. Files:"
  grep -v '^#' "$LOCK" | awk -F'\t' '{printf "  %s (%s tests)\n", $1, $2}'
  echo "Lock: $LOCK"
  # Resolved from $0, not hardcoded to ~/.claude/hooks — under CLAUDE_HOOKS_DIR or a
  # worktree-local run the hardcoded path names a script that isn't the one running.
  echo "Clear it with: $(dirname "$0")/review-tests-clear.sh <PASS|REQUEST_CHANGES> <none|source> <test-file>..."
fi
exit 0
