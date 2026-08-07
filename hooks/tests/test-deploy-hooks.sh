#!/bin/bash
# Fixture-harness tests for deploy-hooks.sh.
#
# This script overwrites files under ~/.claude/hooks/, so its branching deserves
# coverage more than most of this repo: a wrong branch here silently ships the
# wrong hook, or clobbers a live one.
#
# Two seams, both real (not test-only backdoors): $CLAUDE_HOOKS_DIR overrides the
# destination, and SRC_DIR derives from the script's own location — so a fixture
# repo is just a temp dir holding a copy of the script plus a hooks/ subdir.
#
# Every positive assertion is paired with its negative counterpart, and the
# check-mode cases assert BOTH the classification and that nothing was written.
#
# Usage: bash test-deploy-hooks.sh   |   Exit 0 all pass, 1 any fail.

set -u

REAL_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/deploy-hooks.sh"

PASS_COUNT=0; FAIL_COUNT=0
TESTDIR=$(mktemp -d)
if [ -z "$TESTDIR" ] || [ ! -d "$TESTDIR" ]; then
  echo "FATAL: mktemp -d failed" >&2; exit 1
fi
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

[ -f "$REAL_SCRIPT" ] || { echo "FATAL: deploy-hooks.sh not found at $REAL_SCRIPT" >&2; exit 1; }

ok() { if [ "$2" = "$3" ]; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
       else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected=$3 got=$2"; fi }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
        else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected to contain: $3"; echo "        got: $2"; fi }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected NOT to contain: $3";
          else PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1"; fi }

# new_repo <name> -> echoes the fixture repo root (with deploy-hooks.sh + hooks/)
new_repo() {
  local r="$TESTDIR/$1"
  mkdir -p "$r/hooks"
  cp "$REAL_SCRIPT" "$r/deploy-hooks.sh"
  chmod +x "$r/deploy-hooks.sh"
  echo "$r"
}

echo "=== deploy-hooks.sh ==="

# --- A. check mode classifies all three drift states, and writes nothing -----
R=$(new_repo a); LIVE="$TESTDIR/live-a"; mkdir -p "$LIVE"
printf 'same\n'     > "$R/hooks/insync.sh";   printf 'same\n'    > "$LIVE/insync.sh"
printf 'repo-ver\n' > "$R/hooks/drifted.sh";  printf 'live-ver\n' > "$LIVE/drifted.sh"
printf 'new\n'      > "$R/hooks/repoonly.sh"
printf 'orphan\n'   > "$LIVE/liveonly.sh"

OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" --check 2>&1); rc=$?
ok    "A1 check mode exits 1 when drift exists" "$rc" "1"
has   "A2 DRIFTED classified"    "$OUT" "DRIFTED:                    drifted.sh"
has   "A3 REPO-ONLY classified"  "$OUT" "REPO-ONLY (never deployed): repoonly.sh"
has   "A4 LIVE-ONLY classified"  "$OUT" "LIVE-ONLY (untracked in repo):  liveonly.sh"
hasnt "A5 in-sync file not listed" "$OUT" "insync.sh"
# The load-bearing half: check mode must be read-only.
ok    "A6 check mode did NOT deploy the drifted file" "$(cat "$LIVE/drifted.sh")" "live-ver"
ok    "A7 check mode did NOT create the repo-only file" "$([ -e "$LIVE/repoonly.sh" ] && echo yes || echo no)" "no"
ok    "A8 check mode did NOT delete the live-only file" "$([ -e "$LIVE/liveonly.sh" ] && echo yes || echo no)" "yes"

# --- B. in-sync repo reports clean and exits 0 (negative control for A1) -----
R=$(new_repo b); LIVE="$TESTDIR/live-b"; mkdir -p "$LIVE"
printf 'same\n' > "$R/hooks/only.sh"; printf 'same\n' > "$LIVE/only.sh"
OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" 2>&1); rc=$?
ok  "B1 no-args defaults to check mode, exits 0 when in sync" "$rc" "0"
has "B2 reports in sync" "$OUT" "in sync"

# --- C. named deploy: copies, backs up, sets +x ------------------------------
R=$(new_repo c); LIVE="$TESTDIR/live-c"; mkdir -p "$LIVE"
printf 'repo-ver\n' > "$R/hooks/target.sh"
printf 'live-ver\n' > "$LIVE/target.sh"; chmod -x "$LIVE/target.sh"
printf 'untouched\n' > "$R/hooks/other.sh"
OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" target.sh 2>&1); rc=$?
ok  "C1 deploy exits 0"                "$rc" "0"
ok  "C2 live file replaced"            "$(cat "$LIVE/target.sh")" "repo-ver"
ok  "C3 live file made executable"     "$([ -x "$LIVE/target.sh" ] && echo yes || echo no)" "yes"
ok  "C4 previous version backed up"    "$(cat "$LIVE"/.backup/target.sh.* 2>/dev/null)" "live-ver"
# Named deploy must be scoped — an unnamed repo hook must NOT be pushed.
ok  "C5 unnamed hook NOT deployed"     "$([ -e "$LIVE/other.sh" ] && echo yes || echo no)" "no"

# --- D. unchanged file is skipped and NOT backed up -------------------------
R=$(new_repo d); LIVE="$TESTDIR/live-d"; mkdir -p "$LIVE"
printf 'same\n' > "$R/hooks/same.sh"; printf 'same\n' > "$LIVE/same.sh"
OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" same.sh 2>&1)
has "D1 reports unchanged" "$OUT" "unchanged: same.sh"
ok  "D2 no backup churn for an unchanged file" "$(ls "$LIVE/.backup" 2>/dev/null | wc -l | tr -d ' ')" "0"

# --- E. naming a hook the repo doesn't have fails loudly --------------------
R=$(new_repo e); LIVE="$TESTDIR/live-e"; mkdir -p "$LIVE"
printf 'x\n' > "$R/hooks/real.sh"
OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" ghost.sh 2>&1); rc=$?
ok  "E1 unknown target exits non-zero" "$rc" "1"
has "E2 unknown target reported"       "$OUT" "SKIP (not in repo): ghost.sh"

# --- F. --all deploys every tracked hook ------------------------------------
R=$(new_repo f); LIVE="$TESTDIR/live-f"; mkdir -p "$LIVE"
printf 'one\n' > "$R/hooks/one.sh"; printf 'two\n' > "$R/hooks/two.sh"
OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" --all 2>&1); rc=$?
ok "F1 --all exits 0"        "$rc" "0"
ok "F2 --all deployed one.sh" "$(cat "$LIVE/one.sh" 2>/dev/null)" "one"
ok "F3 --all deployed two.sh" "$(cat "$LIVE/two.sh" 2>/dev/null)" "two"

# --- G. nullglob: an EMPTY hooks/ must not produce a phantom `*.sh` ----------
# Without `shopt -s nullglob` the glob yields the literal string, which surfaces
# as a bogus REPO-ONLY entry in check mode and a spurious SKIP+exit-1 under --all.
R=$(new_repo g); LIVE="$TESTDIR/live-g"; mkdir -p "$LIVE"
OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" --check 2>&1); rc=$?
hasnt "G1 empty hooks/ produces no phantom *.sh entry" "$OUT" "*.sh"
ok    "G2 empty hooks/ reports in sync, exit 0" "$rc" "0"
OUT=$(CLAUDE_HOOKS_DIR="$LIVE" "$R/deploy-hooks.sh" --all 2>&1); rc=$?
ok    "G3 --all over empty hooks/ exits 0" "$rc" "0"
hasnt "G4 --all over empty hooks/ skips nothing" "$OUT" "SKIP"

# --- H. --help stops at the usage block, never spilling into code -----------
R=$(new_repo h)
OUT=$("$R/deploy-hooks.sh" --help 2>&1)
has   "H1 help shows usage"                 "$OUT" "./deploy-hooks.sh <name>..."
hasnt "H2 help does not leak shell options"  "$OUT" "set -uo pipefail"

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
