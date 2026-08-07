#!/bin/bash
# Fixture-harness tests for pre-pr-create-gate.sh (#1191).
#
# Contract under test: gate `gh pr create` on a fresh tmp/pr-gate.green
# sentinel — but ONLY for the repo the command actually targets, and only for
# repos that ship scripts/pr-gate.sh.
#
# THE BUG THIS PINS: the hook parsed the target directory out of a leading
# `cd`, then ran the result through `sed 's/["\x27]//g'` to strip quotes. BSD
# sed does not read `\x27` as an escape for `'` — inside a bracket expression
# it is the literal characters x, 2, 7. So the class was effectively ["x27]
# and the command stripped every ", x, 2 and 7 from the path.
#
#   $ echo 'abc-fix' | sed 's/["\x27]//g'
#   abc-fi
#
# A worktree at .../dev-reference-review-base-fix therefore parsed to a
# nonexistent .../dev-reference-review-base-fi, `[ -d ]` failed, EFFECTIVE_CWD
# silently fell back to the SESSION's cwd, and a dev-reference PR was gated
# against an unrelated example-app worktree owned by a concurrent session —
# with a confident, specific, entirely irrelevant error message.
#
# `x`, `2` and `7` are common in our paths: `fix/…` is one of the two standard
# worktree prefixes, so a large share of bugfix worktrees hit this.
#
# Each positive assertion is paired with a negative counterpart so a gate stuck
# at allow-everything (or deny-everything) cannot pass by accident.
#
# Usage: bash test-pr-create-gate.sh   |   Exit 0 all pass, 1 any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# PRE_PR_GATE overrides which copy is exercised — same testability interface as
# BASH_POST_HOOK. Used to confirm this suite goes RED against the pre-fix copy.
GATE="${PRE_PR_GATE:-$HOOKS_DIR/pre-pr-create-gate.sh}"

PASS_COUNT=0; FAIL_COUNT=0

# TESTDIR is built by hand rather than with `mktemp -d`, and that is
# load-bearing. mktemp's random suffix routinely contains `x`, `2` or `7` —
# the exact characters the bug eats — so under mktemp EVERY fixture path is
# mangled, including the ones that exist to prove unaffected paths still work.
# The negative counterparts would then fail for the same reason as the
# regression and prove nothing. So: a name we fully control, with the digits
# mapped off the danger set, probing upward for a free slot.
i=0
while :; do
  TESTDIR="/tmp/prgate-gate-test-$(printf '%s' "$i" | tr '27' 'ab')"
  mkdir "$TESTDIR" 2>/dev/null && break
  i=$((i + 1))
  if [ "$i" -gt 500 ]; then echo "FATAL: no free test dir under /tmp" >&2; exit 1; fi
done
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

# Guard the guard: if a future edit reintroduces a random temp path, say so
# loudly instead of silently hollowing out every negative counterpart below.
case "$TESTDIR" in
  *x*|*2*|*7*)
    echo "FATAL: TESTDIR [$TESTDIR] contains x/2/7 — the negative counterparts" >&2
    echo "       in this suite would fail for the wrong reason. Fix the path." >&2
    exit 1 ;;
esac

ok() { if [ "$2" = "$3" ]; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
       else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected=$3 got=$2"; fi }

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

# A git repo. gated=yes ships scripts/pr-gate.sh; sentinel=fresh|stale|none.
make_repo() { # name, gated, sentinel
  local name="$1" gated="$2" sentinel="$3"
  local w="$TESTDIR/$name"
  mkdir -p "$w"
  git init -q -b main "$w"
  git -C "$w" config user.email t@t.t
  git -C "$w" config user.name t
  echo seed > "$w/seed.txt"
  git -C "$w" add seed.txt
  git -C "$w" commit -qm seed
  if [ "$gated" = "yes" ]; then
    mkdir -p "$w/scripts"
    echo '#!/bin/bash' > "$w/scripts/pr-gate.sh"
    # Commit it so linked worktrees (section 9) inherit the gate marker.
    git -C "$w" add scripts/pr-gate.sh
    git -C "$w" commit -qm gate
  fi
  mkdir -p "$w/tmp"
  case "$sentinel" in
    fresh) git -C "$w" rev-parse HEAD > "$w/tmp/pr-gate.green" ;;
    stale) echo "0000000000000000000000000000000000000000" > "$w/tmp/pr-gate.green" ;;
    none)  : ;;
  esac
  echo "$w"
}

# Returns the hook's stdout ("" means allowed).
run_gate() { # cwd, command
  jq -n --arg c "$2" --arg w "$1" \
    '{tool_name:"Bash", cwd:$w, tool_input:{command:$c}}' \
    | bash "$GATE" 2>/dev/null
}

echo "=== pre-pr-create-gate (#1191) ==="

[ -f "$GATE" ] || { echo "FATAL: gate not found at $GATE" >&2; exit 1; }

# The "session cwd" for every test: a gated repo with NO sentinel. If the hook
# ever falls back to it wrongly, the test sees a deny that names THIS path.
SESSION=$(make_repo session-repo yes none)

# --- 1. THE REGRESSION -----------------------------------------------------
# Target repo is ungated, so the correct answer is ALLOW. Its path ends in
# `-fix`; the old sed ate the `x`, so the hook fell back to $SESSION (gated,
# no sentinel) and denied.
TARGET_X=$(make_repo target-base-fix no none)
out=$(run_gate "$SESSION" "cd $TARGET_X; gh pr create --title t --body b")
ok "path containing 'x' targets the right repo (allowed)" "$out" ""
not_contains "denial does not name the session repo" "$out" "session-repo"

# Digits 2 and 7 are mangled by the same broken class.
TARGET_27=$(make_repo target-slice-27 no none)
out=$(run_gate "$SESSION" "cd $TARGET_27; gh pr create --title t")
ok "path containing '2' and '7' targets the right repo (allowed)" "$out" ""

# --- 2. NEGATIVE COUNTERPART ----------------------------------------------
# A path with no x/2/7 parsed correctly even before the fix. It must still
# work, otherwise the fix broke the common case.
TARGET_PLAIN=$(make_repo plain-base no none)
out=$(run_gate "$SESSION" "cd $TARGET_PLAIN; gh pr create --title t")
ok "path with no x/2/7 still targets the right repo (allowed)" "$out" ""

# --- 3. Quote stripping — the sed's actual job — still works ---------------
TARGET_Q=$(make_repo quoted-base-repo no none)
out=$(run_gate "$SESSION" "cd \"$TARGET_Q\"; gh pr create --title t")
ok "double-quoted cd path is unquoted correctly (allowed)" "$out" ""
out=$(run_gate "$SESSION" "cd '$TARGET_Q'; gh pr create --title t")
ok "single-quoted cd path is unquoted correctly (allowed)" "$out" ""

# --- 4. The gate still GATES — deny half of every pair above ---------------
GATED_NONE=$(make_repo gated-none yes none)
out=$(run_gate "$SESSION" "cd $GATED_NONE; gh pr create --title t")
contains "gated repo with no sentinel is denied" "$out" '"permissionDecision": "deny"'
contains "denial names the targeted repo, not the session repo" "$out" "gated-none"

GATED_STALE=$(make_repo gated-stale yes stale)
out=$(run_gate "$SESSION" "cd $GATED_STALE; gh pr create --title t")
contains "gated repo with a stale sentinel is denied" "$out" '"permissionDecision": "deny"'
contains "stale denial explains staleness" "$out" "stale after new commits"

GATED_FRESH=$(make_repo gated-fresh yes fresh)
out=$(run_gate "$SESSION" "cd $GATED_FRESH; gh pr create --title t")
ok "gated repo with a fresh sentinel is allowed" "$out" ""

# --- 5. No leading cd: gate the session cwd itself -------------------------
out=$(run_gate "$GATED_FRESH" "gh pr create --title t")
ok "no-cd command uses session cwd (fresh sentinel, allowed)" "$out" ""
out=$(run_gate "$GATED_NONE" "gh pr create --title t")
contains "no-cd command uses session cwd (no sentinel, denied)" "$out" '"permissionDecision": "deny"'

# --- 6. Only gh pr create is gated ----------------------------------------
out=$(run_gate "$GATED_NONE" "gh pr view 12")
ok "gh pr view is not gated" "$out" ""
out=$(run_gate "$GATED_NONE" "gh issue create --body \"how to gh pr create\"")
ok "'gh pr create' inside a quoted arg is not gated" "$out" ""

# --- 7. Unresolvable cd target: DON'T GATE --------------------------------
# When the `cd` target can't be resolved we don't know which repo the PR
# targets, so the gate must stand down rather than guess.
#
# Both other options were tried and are worse. Falling back to the session cwd
# is the original #1191 bug — it evaluates a different repo and denies while
# naming another session's worktree. Denying instead (the first pass at fixing
# #1191) turned a silent wrong answer into a hard, unclearable block: the
# parse is pure text with no shell expansion, so every case below failed to
# resolve and got denied, including in repos this gate promises not to touch.
# Caught by cross-model review on PR #13 (B1/B2) and confirmed live.
out=$(run_gate "$SESSION" "cd /no/such/directory/anywhere; gh pr create --title t")
ok "unresolvable cd target does not gate (allowed)" "$out" ""
not_contains "unresolvable cd target does not blame the session repo" "$out" "stale after new commits"

# B2 — the parse does NO shell expansion, so these are all unresolvable text.
# Each previously hard-denied. `cd ~/Projects/…` is an everyday command.
out=$(run_gate "$SESSION" "cd ~/Projects/dev-reference && gh pr create --title t")
ok "unexpanded ~ target does not gate (allowed)" "$out" ""
out=$(run_gate "$SESSION" "cd \"\$WORKTREE\" && gh pr create --title t")
ok "unexpanded \$VAR target does not gate (allowed)" "$out" ""
out=$(run_gate "$SESSION" "cd \"$TESTDIR/path with spaces\" && gh pr create --title t")
ok "space-containing target does not gate (allowed)" "$out" ""

# B1 — the same, originating from an UNGATED repo. The old parse-failure deny
# fired before the "does this repo even ship scripts/pr-gate.sh?" check, so it
# denied in repos the gate is scoped to ignore, pointing at a script that does
# not exist there. dev-reference is exactly such a repo.
UNGATED=$(make_repo ungated-session no none)
out=$(run_gate "$UNGATED" "cd /no/such/directory/anywhere; gh pr create --title t")
ok "unresolvable cd from an UNGATED repo does not gate (allowed)" "$out" ""
out=$(run_gate "$UNGATED" "cd ~/Projects/whatever && gh pr create --title t")
ok "unexpanded ~ from an UNGATED repo does not gate (allowed)" "$out" ""

# NEGATIVE COUNTERPART: standing down on unresolvable paths must not have
# turned the gate off. A resolvable, gated, sentinel-less repo still denies.
out=$(run_gate "$SESSION" "cd $GATED_NONE; gh pr create --title t")
contains "gate still denies when the path DOES resolve" "$out" '"permissionDecision": "deny"'

# --- 8. Cross-repo `--repo X`: gate the target, not the cwd (#1198 / #1201 Tier 1) ---
# `gh pr create --repo other` from a gated, sentinel-less cwd must NOT gate the cwd
# repo. The live bug: a dev-reference PR opened with --repo from an example-app session
# cwd was denied against a stale example-app sentinel. SESSION is gated with no sentinel,
# so without the fix every case below would deny.
out=$(run_gate "$SESSION" "gh pr create --repo USER/other-repo --title t")
ok "--repo naming a DIFFERENT repo stands down (allowed)" "$out" ""
not_contains "--repo stand-down does not blame the session repo" "$out" "session-repo"
out=$(run_gate "$SESSION" "gh pr create --repo=witzcraft/other-repo --title t")
ok "--repo=X (equals form) stands down (allowed)" "$out" ""

# NEGATIVE COUNTERPART: --repo naming the SAME repo as the cwd must still gate it,
# else the stand-down is just the gate turned off.
out=$(run_gate "$SESSION" "gh pr create --repo USER/session-repo --title t")
contains "--repo naming the SAME repo still gates (denied)" "$out" '"permissionDecision": "deny"'

# --- 9. Denial names the BRANCH'S OWN worktree, not an unrelated one (#1198 defect 2) ---
# The reported bug: a PR from a fresh sentinel-less worktree was denied with a message
# naming ANOTHER session's stale sentinel in an unrelated worktree. Build exactly that:
# a gated main checkout, an unrelated worktree carrying a stale sentinel, and the
# branch being PR'd in its own sentinel-less worktree.
MULTI=$(make_repo multi-main yes none)
git -C "$MULTI" worktree add -q "$TESTDIR/multi-unrelated" -b other/unrelated
mkdir -p "$TESTDIR/multi-unrelated/tmp"
echo "0000000000000000000000000000000000000000" > "$TESTDIR/multi-unrelated/tmp/pr-gate.green"
git -C "$MULTI" worktree add -q "$TESTDIR/multi-branch" -b feature/mine
out=$(run_gate "$TESTDIR/multi-branch" "gh pr create --title t")
contains "multi-worktree PR from a sentinel-less worktree is denied" "$out" '"permissionDecision": "deny"'
contains "denial names the branch being PR'd" "$out" "feature/mine"
not_contains "denial does NOT name the unrelated worktree's stale sentinel" "$out" "multi-unrelated"
not_contains "denial does NOT claim staleness (there is no sentinel here)" "$out" "stale after new commits"

echo
echo "=== Summary: $PASS_COUNT passed, $FAIL_COUNT failed ==="
[ "$FAIL_COUNT" -eq 0 ] || exit 1
