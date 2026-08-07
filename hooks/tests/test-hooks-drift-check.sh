#!/bin/bash
# Fixture-harness tests for hooks-drift-check.sh — the SessionStart drift warning (#1231).
#
# The two behaviors worth pinning are silence-on-clean and non-silence-on-drift, plus
# the guards that keep a SessionStart hook from ever misbehaving: it must stay silent
# (never a bodyless banner) when deploy-hooks.sh errors, and it must never block a
# session (always exit 0). The throttle — report a drift set at most once a day, but
# re-fire immediately when the set changes — is the other half.
#
# Three seams, all real (not test-only backdoors): CLAUDE_CONFIG_REPO points the hook
# at a fixture repo (a temp dir holding a copy of deploy-hooks.sh + hooks/),
# CLAUDE_HOOKS_DIR is deploy-hooks.sh's own DEST override, and CLAUDE_DRIFT_STATE is
# the throttle's state file. Every positive assertion is paired with its negative.
#
# Usage: bash test-hooks-drift-check.sh   |   Exit 0 all pass, 1 any fail.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$ROOT/hooks/hooks-drift-check.sh"
REAL_DEPLOY="$ROOT/deploy-hooks.sh"

PASS_COUNT=0; FAIL_COUNT=0
TESTDIR=$(mktemp -d)
if [ -z "$TESTDIR" ] || [ ! -d "$TESTDIR" ]; then
  echo "FATAL: mktemp -d failed" >&2; exit 1
fi
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

[ -f "$HOOK" ]        || { echo "FATAL: hooks-drift-check.sh not found at $HOOK" >&2; exit 1; }
[ -f "$REAL_DEPLOY" ] || { echo "FATAL: deploy-hooks.sh not found at $REAL_DEPLOY" >&2; exit 1; }

ok() { if [ "$2" = "$3" ]; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
       else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected=$3 got=$2"; fi }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
        else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected to contain: $3"; echo "        got: $2"; fi }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected NOT to contain: $3";
          else PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1"; fi }

# new_repo <name> -> echoes a fixture repo root (deploy-hooks.sh + empty hooks/)
new_repo() {
  local r="$TESTDIR/$1"
  mkdir -p "$r/hooks"
  cp "$REAL_DEPLOY" "$r/deploy-hooks.sh"
  chmod +x "$r/deploy-hooks.sh"
  echo "$r"
}

# run <repo> <live> <state> -> sets OUT and rc
run() {
  OUT=$(CLAUDE_CONFIG_REPO="$1" CLAUDE_HOOKS_DIR="$2" CLAUDE_DRIFT_STATE="$3" bash "$HOOK" 2>&1); rc=$?
}

echo "=== hooks-drift-check.sh ==="

# --- A. in sync -> silent, exit 0 -------------------------------------------
R=$(new_repo a); LIVE="$TESTDIR/live-a"; mkdir -p "$LIVE"
printf 'same\n' > "$R/hooks/only.sh"; printf 'same\n' > "$LIVE/only.sh"
run "$R" "$LIVE" "$TESTDIR/a.state"
ok "A1 exits 0 when in sync"    "$rc"  "0"
ok "A2 prints nothing in sync"  "$OUT" ""

# --- B. drift -> exits 0 (never blocks), prints banner, filters correctly ----
R=$(new_repo b); LIVE="$TESTDIR/live-b"; mkdir -p "$LIVE"
printf 'repo-ver\n' > "$R/hooks/drifted.sh"; printf 'live-ver\n' > "$LIVE/drifted.sh"
run "$R" "$LIVE" "$TESTDIR/b.state"
ok    "B1 never blocks — exits 0 even on drift"  "$rc" "0"
has   "B2 prints the drift banner"               "$OUT" "HOOK DRIFT"
has   "B3 keeps the DRIFTED line"                "$OUT" "DRIFTED:                    drifted.sh"
hasnt "B4 drops deploy-hooks.sh's summary line"  "$OUT" "file(s) out of sync"
hasnt "B5 drops deploy-hooks.sh's === header"    "$OUT" "=== hook drift"
has   "B6 reconcile hint interpolates \$REPO"     "$OUT" "Reconcile from $R"

# --- C. missing deploy-hooks.sh -> silent, exit 0 ---------------------------
NOREPO="$TESTDIR/c-norepo"; mkdir -p "$NOREPO"   # no deploy-hooks.sh in it
LIVE="$TESTDIR/live-c"; mkdir -p "$LIVE"
run "$NOREPO" "$LIVE" "$TESTDIR/c.state"
ok "C1 missing deploy-hooks.sh exits 0" "$rc"  "0"
ok "C2 missing deploy-hooks.sh silent"  "$OUT" ""

# --- D. deploy-hooks.sh ERRORS (non-zero, empty stdout) -> silent, no banner -
# Regression guard for the empty-report bug: deploy-hooks.sh's FATAL path exits 1
# with nothing on stdout; a naive `[ $? -eq 0 ] && exit 0` would then print a
# headline with no body. Removing hooks/ triggers that FATAL path.
R=$(new_repo d); rm -rf "$R/hooks"
LIVE="$TESTDIR/live-d"; mkdir -p "$LIVE"
run "$R" "$LIVE" "$TESTDIR/d.state"
ok    "D1 erroring deploy still exits 0" "$rc"  "0"
ok    "D2 erroring deploy is silent"     "$OUT" ""
hasnt "D3 no bodyless HOOK DRIFT banner" "$OUT" "HOOK DRIFT"

# --- E. throttle: same drift set, same day -> printed once, then silent ------
R=$(new_repo e); LIVE="$TESTDIR/live-e"; mkdir -p "$LIVE"
ST="$TESTDIR/e.state"
printf 'repo-ver\n' > "$R/hooks/x.sh"; printf 'live-ver\n' > "$LIVE/x.sh"
run "$R" "$LIVE" "$ST"
has "E1 first run prints"                 "$OUT" "HOOK DRIFT"
run "$R" "$LIVE" "$ST"
ok  "E2 repeat, same drift set, is silent" "$OUT" ""

# --- F. throttle: a CHANGED drift set re-fires same day (the merge catch) -----
printf 'repo-ver\n' > "$R/hooks/y.sh"; printf 'live-ver\n' > "$LIVE/y.sh"
run "$R" "$LIVE" "$ST"
has "F1 changed drift set re-fires same day" "$OUT" "HOOK DRIFT"

# --- G. throttle is content-sensitive: same filename, NEW repo content re-fires
# The core "merged but not deployed" catch — a hook already in the drift set gets a
# fresh merged version. A basename-only signature would suppress this for 24h.
R=$(new_repo g); LIVE="$TESTDIR/live-g"; mkdir -p "$LIVE"; ST="$TESTDIR/g.state"
printf 'repo-v1\n' > "$R/hooks/z.sh"; printf 'live-ver\n' > "$LIVE/z.sh"
run "$R" "$LIVE" "$ST"
has "G1 first drift prints"                          "$OUT" "HOOK DRIFT"
run "$R" "$LIVE" "$ST"
ok  "G2 same content, same day, is silent"           "$OUT" ""
printf 'repo-v2\n' > "$R/hooks/z.sh"   # still drifted vs live, but new repo content
run "$R" "$LIVE" "$ST"
has "G3 same filename, new repo content re-fires"    "$OUT" "HOOK DRIFT"

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
