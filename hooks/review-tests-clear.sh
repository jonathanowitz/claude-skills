#!/bin/bash
# Record a completed /review-tests verdict and clear the Gate-1 lock.
# Invoked by /review-tests Stage 5. Not a hook.
#
#   review-tests-clear.sh <verdict> <blocked_on> <test-file> [<test-file> ...]
#
#     verdict     PASS | REQUEST_CHANGES
#     blocked_on  none | source
#
# Writes the reviewed baseline — each file's test count and content hash at review time — to
#   /tmp/review-tests-reviewed-<worktree_hash>.tsv
# Then removes the lock.
#
# STATUS OF THE BASELINE (corrected 2026-07-24): it is RECORDED FOR A FUTURE CONSUMER and is
# not yet read by anything. The intent is that later edits charge only the tests they ADD, and
# that a git-mv'd file is recognized by hash at its new path — but `test-review-gate-post.sh`
# computes its cumulative from the LOCK and never opens this ledger. Nothing reads
# ledger_path(); count_tests_in()/hash_of() have exactly one caller, the writer below. This
# header previously described that intent in the present tense, which is the same defect this
# change fixes in the gate's `rm` escape-hatch text: asserting a guarantee the code does not
# provide. Land the consumer, or keep this paragraph honest.
#
# Only two combinations are legal:
#
#   PASS none              the review is clean; the gate has done its job.
#   REQUEST_CHANGES source the review's unresolved findings are in the source, and
#                          the source cannot be fixed while the gate denies source
#                          edits and suite runs. Clearing is the only way forward.
#
# Everything else is refused. In particular REQUEST_CHANGES + none: findings about
# the TESTS are fixable by editing test files, which the gate already allows, so no
# unlock is needed. Clearing there would be the "the blocker is in the source, not
# in the tests, so the tests pass" rationalisation — a gate whose trigger condition
# can be argued around teaches you to argue around it.
#
# Evidence: 2026-07-09 (decidr #3, PR #6) — /review-tests returned REQUEST_CHANGES
# for a bug in src/lib/session.js. Remediation needed source edits (denied) and a
# suite run (denied); the verdict could not reach PASS without the fix, and the fix
# could not be made without the verdict. Four manual unlocks in one session.
# Filed as USER/claude-config#5.

set -e

source "$(dirname "$0")/review-tests-count.sh"

usage() {
  echo "usage: $(basename "$0") <PASS|REQUEST_CHANGES> <none|source> <test-file>..." >&2
  exit 2
}

[ $# -ge 3 ] || usage
verdict="$1"
blocked_on="$2"
shift 2

case "$verdict" in PASS|REQUEST_CHANGES) ;; *) usage ;; esac
case "$blocked_on" in none|source) ;; *) usage ;; esac

if [ "$verdict" = "PASS" ] && [ "$blocked_on" != "none" ]; then
  echo "REFUSED: a PASS verdict cannot be blocked on anything." >&2
  exit 1
fi

if [ "$verdict" != "PASS" ] && [ "$blocked_on" != "source" ]; then
  cat >&2 <<'MSG'
REFUSED: verdict is not PASS and the blocker is not in the source.

Findings about the TESTS are fixable by editing test files, which the gate already
allows. Fix them and re-run /review-tests. The lock stays.

Only pass `source` when the unresolved finding is in implementation code that the
gate is actively denying you permission to edit.
MSG
  exit 1
fi

for f in "$@"; do
  case "$f" in /*) ;; *) echo "REFUSED: '$f' is not an absolute path." >&2; exit 1 ;; esac
  [ -f "$f" ] || { echo "REFUSED: '$f' does not exist." >&2; exit 1; }
done

# REFUSE outside a git repo rather than guessing. Every lock/ledger/stamp path is keyed off the
# worktree root; the hooks fall back to the session cwd when `rev-parse` fails, while this
# script used to fall back to the test file's own directory. Outside a repo those hash to
# DIFFERENT lock paths, so this script would write a ledger, remove a lock that was never
# there, log CLEARED, print success — and leave the real lock and stamp untouched. A
# silent-success is the worst outcome for a script whose entire job is to be trustworthy.
worktree=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$worktree" ]; then
  echo "REFUSED: '$1' is not inside a git repository." >&2
  echo "  The gate keys its lock, ledger and stamp off the worktree root, so there is no" >&2
  echo "  well-defined lock to clear here. Run this against a test file in the worktree" >&2
  echo "  whose gate you mean to clear." >&2
  exit 1
fi
LOCK=$(lock_path "$worktree")
LEDGER=$(ledger_path "$worktree")

# Carry forward baselines for files this review did not cover; overwrite the ones
# it did. A review may legitimately cover a subset of the worktree's test files.
tmp=$(mktemp)
if [ -f "$LEDGER" ]; then
  grep -v '^#' "$LEDGER" > "$tmp" 2>/dev/null || true
fi
cleared_tests=0
for f in "$@"; do
  cleared_tests=$((cleared_tests + $(count_tests_in "$f")))
  # awk with an exact string compare, NOT `grep -v "^${f}\t"` — a file path is not a regex.
  # Unescaped `.` matches any character, so a ledger holding both `/r/tests/thing.test.js` and
  # `/r/tests/thingXtest.js` would silently drop the second's row while rewriting the first.
  awk -F'\t' -v p="$f" '$1 != p' "$tmp" > "$tmp.next" 2>/dev/null || true
  mv "$tmp.next" "$tmp"
  # Third column is the content hash, so a future consumer can recognize a git-mv'd or copied
  # file as already-reviewed by content even at a new path.
  printf '%s\t%s\t%s\n' "$f" "$(count_tests_in "$f")" "$(hash_of "$f")" >> "$tmp"
done

{
  printf '# REVIEW_TESTS reviewed baseline\n'
  printf '# verdict=%s\n' "$verdict"
  printf '# blocked_on=%s\n' "$blocked_on"
  printf '# reviewed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '# worktree=%s\n' "$worktree"
  sort "$tmp"
} > "$LEDGER"
rm -f "$tmp"

# STAMP FIRST, then the lock. Order matters: a hook firing between the two removals sees
# stamp-without-lock and would record a PERMANENT false UNRECORDED_CLEAR accusation. Removing
# the stamp first means the in-between state is lock-without-stamp, which merely re-arms the
# stamp (a harmless duplicate ARMED line) instead of libelling a legitimate clear.
rm -f "$(stamp_path "$worktree")"
rm -f "$LOCK"

# The durable record. Everything above lives in /tmp and is overwritten by the next review
# or lost on reboot; this line is what the next /maintenance actually reads.
#
# `tests=` must SUM test counts, never COUNT rows. The ledger is one row per FILE, so the
# original `grep -vc '^#'` reported the file count: clearing 2 files holding 20 tests logged
# `files=2 tests=2` — a wrong number that reads as plausible, in the one durable line this
# mechanism exists to produce, and incomparable with ARMED's real cumulative count.
#
# `tests=` is scoped to THIS invocation so it pairs with `files=$#`. Summing the whole ledger
# instead would silently mix scopes — `files=2 tests=26` where the 26 spans three files across
# two separate reviews — which is exactly the kind of plausible-but-wrong figure this field was
# just fixed for. The worktree-wide total is still recorded, as its own `baseline_tests=`.
audit_log "CLEARED" "$worktree" \
  "verdict=$verdict" "blocked_on=$blocked_on" "files=$#" \
  "tests=$cleared_tests" "baseline_tests=$(awk -F'\t' '!/^#/{s+=$2} END{print s+0}' "$LEDGER" 2>/dev/null || echo 0)"

echo "REVIEW_TESTS cleared: verdict=$verdict blocked_on=$blocked_on"
echo "  worktree: $worktree"
echo "  baseline: $LEDGER"
echo "  audit:    $(audit_path)"
grep -v '^#' "$LEDGER" | awk -F'\t' '{printf "    %s (%s tests reviewed)\n", $1, $2}'
if [ "$verdict" != "PASS" ]; then
  echo "  The lock is gone so the SOURCE can be fixed. The verdict is NOT resolved:"
  echo "  re-run /review-tests to PASS before opening a PR."
fi
