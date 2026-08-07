#!/bin/bash
# Fixture-harness tests for bash-post-hook.sh's `cd` target resolution (#1191).
#
# Same defect as pre-pr-create-gate.sh, second file: `sed 's/["\x27]//g'` ate
# every ", x, 2 and 7 out of the parsed path, `[ -d ]` failed, and EFFECTIVE_CWD
# silently stayed the SESSION's cwd.
#
# It matters more here than in the gate, because here it is silent. Every step
# downstream — PR lookup, head-branch resolution, REVIEW_CWD — then runs against
# the wrong repo. Both review scripts diff a checkout whose HEAD already matches
# its base, print "No diff found. Nothing to review.", and exit 0. The PR gets
# NO review and nothing reports a failure. Observed live on dev-reference#3 and
# claude-config#13, both opened from worktrees ending in `-fix`.
#
# HOW THIS TESTS SAFELY: the PR-create branch launches two REAL background
# reviews (a Claude fan-out plus Gemini calls each) — a test must never fire
# those. So every case here drives the branch where the PR number cannot be
# extracted: no `/pull/N` URL in tool_response.stdout, and a repo with no remote
# so `gh pr view` fails. That path echoes EFFECTIVE_CWD in its recovery message
# and launches nothing, which is exactly the value under test.
#
# Usage: bash test-bash-post-hook-cwd.sh   |   Exit 0 all pass, 1 any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# BASH_POST_HOOK overrides which copy is exercised — same testability interface
# as DISPATCH_GATE_EVENTS_LOG. Used to confirm this suite goes RED against the
# pre-fix copy before trusting it green against the fixed one.
HOOK="${BASH_POST_HOOK:-$HOOKS_DIR/bash-post-hook.sh}"

PASS_COUNT=0; FAIL_COUNT=0

# Hand-built temp dir, not `mktemp -d`: mktemp's random suffix routinely
# contains x/2/7 — the characters the bug eats — which would mangle every
# fixture path including the controls. See test-pr-create-gate.sh.
i=0
while :; do
  TESTDIR="/tmp/bashposthook-test-$(printf '%s' "$i" | tr '27' 'ab')"
  mkdir "$TESTDIR" 2>/dev/null && break
  i=$((i + 1))
  if [ "$i" -gt 500 ]; then echo "FATAL: no free test dir under /tmp" >&2; exit 1; fi
done
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

# STRUCTURAL guard against this suite ever launching a real review.
#
# Every case here is designed to reach the "could not extract PR number"
# branch, which launches nothing. But that defence was ambient: the fallback
# is `gh pr view --json number`, and `gh` resolves a repo from GH_REPO /
# GH_CONFIG_DIR in the ENVIRONMENT, not only from git remotes. With GH_REPO
# set, that call could return a real PR number and the hook would then run
# run-code-review.sh and run-test-coverage-review.sh against a LIVE PR —
# posting comments and burning a Claude fan-out plus Gemini calls.
# (PR #13 cross-model review, W2.)
#
# So: a stub `gh` that always fails, first on PATH. No fixture can reach the
# network regardless of ambient env.
mkdir -p "$TESTDIR/bin"
printf '#!/bin/sh\nexit 1\n' > "$TESTDIR/bin/gh"
chmod +x "$TESTDIR/bin/gh"
PATH="$TESTDIR/bin:$PATH"
export PATH

case "$TESTDIR" in
  *x*|*2*|*7*)
    echo "FATAL: TESTDIR [$TESTDIR] contains x/2/7 — controls would fail for the wrong reason." >&2
    exit 1 ;;
esac

contains() { # label, haystack, needle
  case "$2" in
    *"$3"*) PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1" ;;
    *) FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected to contain: $3"; echo "        got: $2" ;;
  esac
}

not_contains() { # label, haystack, needle
  case "$2" in
    *"$3"*) FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected NOT to contain: $3"; echo "        got: $2" ;;
    *) PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1" ;;
  esac
}

# A git repo with NO remote, so `gh pr view` cannot resolve a PR number and the
# hook takes its launch-nothing recovery branch.
make_repo() { # name
  local name="$1"
  local w="$TESTDIR/$name"
  mkdir -p "$w"
  git init -q -b main "$w"
  git -C "$w" config user.email t@t.t
  git -C "$w" config user.name t
  echo seed > "$w/seed.txt"
  git -C "$w" add seed.txt
  git -C "$w" commit -qm seed
  echo "$w"
}

# stdout carries no /pull/N URL, so PR_NUM extraction fails by design.
run_hook() { # cwd, command
  jq -n --arg c "$2" --arg w "$1" \
    '{tool_name:"Bash", cwd:$w, tool_input:{command:$c}, tool_response:{stdout:"", stderr:""}}' \
    | bash "$HOOK" 2>/dev/null
}

echo "=== bash-post-hook cd resolution (#1191) ==="

[ -f "$HOOK" ] || { echo "FATAL: hook not found at $HOOK" >&2; exit 1; }

SESSION=$(make_repo session-repo)

# --- 1. THE REGRESSION: a path ending in -fix ------------------------------
TARGET_X=$(make_repo target-base-fix)
out=$(run_hook "$SESSION" "cd $TARGET_X; gh pr create --title t")
contains "path with 'x' resolves to the target repo" "$out" "$TARGET_X"
not_contains "path with 'x' does not fall back to the session cwd" "$out" "EFFECTIVE_CWD=$SESSION"

# Digits 2 and 7, same broken class.
TARGET_27=$(make_repo target-slice-27)
out=$(run_hook "$SESSION" "cd $TARGET_27; gh pr create --title t")
contains "path with '2' and '7' resolves to the target repo" "$out" "$TARGET_27"

# --- 2. CONTROL: a path with none of those characters ---------------------
# Resolved correctly even before the fix; must still work after it.
TARGET_PLAIN=$(make_repo plain-base)
out=$(run_hook "$SESSION" "cd $TARGET_PLAIN; gh pr create --title t")
contains "path with no x/2/7 still resolves to the target repo" "$out" "$TARGET_PLAIN"

# --- 3. Quote stripping — the line's actual job ---------------------------
TARGET_Q=$(make_repo quoted-base-repo)
out=$(run_hook "$SESSION" "cd \"$TARGET_Q\"; gh pr create --title t")
contains "double-quoted cd path resolves" "$out" "$TARGET_Q"
out=$(run_hook "$SESSION" "cd '$TARGET_Q'; gh pr create --title t")
contains "single-quoted cd path resolves" "$out" "$TARGET_Q"

# --- 4. No leading cd: session cwd is used ---------------------------------
out=$(run_hook "$SESSION" "gh pr create --title t")
contains "no-cd command uses the session cwd" "$out" "EFFECTIVE_CWD=$SESSION"

# --- 5. Unresolvable cd target warns instead of failing silently ----------
# PostToolUse cannot block, but a silent fallback is indistinguishable from a
# review that ran and found nothing — which is how #1191 went unnoticed.
out=$(run_hook "$SESSION" "cd /no/such/directory/anywhere; gh pr create --title t")
contains "unresolvable cd target emits a warning" "$out" "CWD_PARSE_WARNING"
contains "warning names the directory that did not resolve" "$out" "/no/such/directory/anywhere"

# --- 6. The warning does NOT fire on a good path (negative counterpart) ---
out=$(run_hook "$SESSION" "cd $TARGET_X; gh pr create --title t")
not_contains "no warning when the cd target resolves fine" "$out" "CWD_PARSE_WARNING"

# --- 7. The warning is scoped to commands that CONSUME the resolved cwd ---
# This helper runs for every Bash command starting with `cd`, ahead of every
# branch guard. Unscoped, it claimed "the PR review below is evaluating the
# wrong repo" on a bare `git status`, where no review, gate or check runs at
# all — and PostToolUse stdout lands in context, so it read as a recurring
# review failure. (PR #13 cross-model review, W1.)
out=$(run_hook "$SESSION" "cd /no/such/directory/anywhere && git status")
not_contains "no warning for a non-consumer command (git status)" "$out" "CWD_PARSE_WARNING"
out=$(run_hook "$SESSION" "cd /no/such/directory/anywhere && npm test")
not_contains "no warning for a non-consumer command (npm test)" "$out" "CWD_PARSE_WARNING"

# ...but it MUST still fire for the consumers. Negative counterpart to the two
# above, so a `case` that silently matches nothing cannot pass.
out=$(run_hook "$SESSION" "cd /no/such/directory/anywhere && gh pr merge 1")
contains "warning still fires for gh pr merge" "$out" "CWD_PARSE_WARNING"

echo
echo "=== Summary: $PASS_COUNT passed, $FAIL_COUNT failed ==="
[ "$FAIL_COUNT" -eq 0 ] || exit 1
