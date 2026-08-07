#!/bin/bash
# Shared helpers. Sourced by test-review-gate-post.sh and test-review-gate-pre.sh (for the
# audit helpers below) and by review-tests-clear.sh (which also uses count_tests_in/hash_of).
#
# COUNTER STATUS — corrected 2026-07-24; this header previously claimed an invariant the code
# does not hold. The INTENT is that the gate's count and the baseline's count must agree: if
# the gate counts a file at 9 and the baseline records 7, every later edit charges a phantom 2
# and the gate re-arms for nothing. THEY DO NOT AGREE TODAY — test-review-gate-post.sh keeps a
# narrower inline pattern (`^\s*(it|test)\(`) and never calls count_tests_in(), which also
# matches `it.each`/`test.only` forms. That divergence is currently harmless ONLY because
# nothing reads the baseline ledger, so the two counts never meet. It becomes a live
# phantom-rearm bug the moment a ledger consumer lands: unify the counters BEFORE or WITH that
# consumer, never after.

# count_tests_in <file> -> integer on stdout
count_tests_in() {
  local f="$1" n
  [ -f "$f" ] || { echo 0; return 0; }
  # The old pattern `^\s*(it|test)\(` demanded `(` immediately after the function name, so
  # every modifier form slipped past it: `it.each(`, `test.each(`, `it.only(`, `test.skip(`.
  # Allowing `[.(]` catches them — but it also starts matching Playwright's `test.describe(`
  # and friends, which are structure rather than tests, so those are subtracted.
  n=$(grep -E '^[[:space:]]*(it|test)[.(]' "$f" 2>/dev/null \
    | grep -vcE '^[[:space:]]*test\.(describe|beforeEach|afterEach|beforeAll|afterAll|step|use|slow|setTimeout|extend|info|fail|fixme)' \
    || true)
  echo "${n:-0}"
}

# Content hash of a file — used to recognize an already-reviewed test file after a
# `git mv` rename or a fresh worktree's copy (same bytes, new path). The baseline
# keys on path first; a path miss then falls back to this hash so a pure rename/copy
# charges 0 instead of re-arming the gate. Any real edit changes the bytes ⇒ the hash
# differs ⇒ it correctly charges as new. Always returns 0 (never trips `set -e`).
hash_of() { # hash_of <file> -> sha256 hex on stdout ("" if missing/unreadable)
  [ -f "$1" ] || { echo ""; return 0; }
  shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  return 0
}

# Path helpers — every consumer keys state off the worktree root, never the
# session cwd, so parallel sessions sharing a main checkout don't share a lock.
worktree_of() { # worktree_of <file-inside-repo> <fallback>
  worktree_of_dir "$(dirname "$1")" "$2"
}

worktree_of_dir() { # worktree_of_dir <dir-inside-repo> <fallback>
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || echo "$2"
}

lock_path() { echo "/tmp/review-tests-pending-$(echo -n "$1" | shasum -a 256 | cut -c1-8).lock"; }
ledger_path() { echo "/tmp/review-tests-reviewed-$(echo -n "$1" | shasum -a 256 | cut -c1-8).tsv"; }

# ── audit trail (USER 2026-07-24, after two bare-`rm` clears in one session) ──────
#
# WHY: the lock and the ledger both live in /tmp and are per-worktree — the ledger is
# overwritten by each review and both vanish on reboot — so NOTHING durable recorded that
# a gate had been cleared, or how. That made a sanctioned Stage-5 clear and a bare
# `rm /tmp/review-tests-pending-*.lock` the SAME observable event, which made "is the agent
# circumventing this gate?" unanswerable except through the agent's own self-report — the
# exact instrument measurement target #1 (first-person verification failure) says not to
# trust. One append-only log, OUTSIDE /tmp, written by whoever changes lock state.
audit_path() { echo "${CLAUDE_REVIEW_AUDIT_LOG:-$HOME/.claude/review-tests-audit.log}"; }

# The STAMP is what makes an unrecorded clear DETECTABLE. It is armed alongside the lock and
# removed only by review-tests-clear.sh. A bare `rm *.lock` therefore leaves the stamp
# behind, and a stamp with no lock is positive evidence the lock was removed by hand — which
# the next hook invocation reports as UNRECORDED_CLEAR. Absence of evidence becomes evidence.
stamp_path() { echo "/tmp/review-tests-armed-$(echo -n "$1" | shasum -a 256 | cut -c1-8).stamp"; }

# audit_log <event> <worktree> [key=value ...]
# NEVER fails the caller: this is instrumentation, and a gate hook that died because it
# could not append a log line would be strictly worse than the missing line.
audit_log() {
  local event="$1" worktree="$2"; shift 2
  local log line kv
  log=$(audit_path)

  # mkdir MUST happen outside the redirection. `{ mkdir …; printf …; } >> "$log"` looks right
  # but the shell opens the redirection BEFORE running the block — so on a machine where the
  # log's directory does not exist yet, the open fails with ENOENT, the whole block is skipped
  # (mkdir never runs), and `|| true` swallows it. The audit log would then never be written
  # at all, silently, forever. Caught in pre-PR cross-model review 2026-07-24.
  mkdir -p "$(dirname "$log")" 2>/dev/null || true

  # ONE line built in memory, appended with ONE write. A block of several printfs under a
  # single `>>` is several write() syscalls, and parallel sessions share this file — their
  # fields would interleave and corrupt the record. A single short append is atomic in
  # practice (well under PIPE_BUF) on the local filesystems this runs on.
  line=$(printf '%s\t%s\t%s\tsession=%s\tpid=%s' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$worktree" \
    "${CLAUDE_SESSION_ID:-unknown}" "$$")
  for kv in "$@"; do line="$line$(printf '\t%s' "$kv")"; done
  printf '%s\n' "$line" >> "$log" 2>/dev/null || true
  return 0
}

# Call at the top of any hook that inspects lock state. Reports — ONCE — that a lock
# disappeared without going through review-tests-clear.sh, then drops the stamp so the same
# event is not re-reported on every subsequent test-file write.
detect_unrecorded_clear() { # detect_unrecorded_clear <worktree>
  local worktree="$1" lock stamp
  lock=$(lock_path "$worktree"); stamp=$(stamp_path "$worktree")
  if [ -f "$stamp" ] && [ ! -f "$lock" ]; then
    audit_log "UNRECORDED_CLEAR" "$worktree" "armed_at=$(cat "$stamp" 2>/dev/null)" \
      "note=lock removed without review-tests-clear.sh"
    rm -f "$stamp"
    return 0
  fi
  return 1
}
