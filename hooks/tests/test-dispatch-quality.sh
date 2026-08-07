#!/bin/bash
# Fixture-harness tests for dispatch-quality scoring (#1186), LENIENT mode.
#
# Contract under test: dispatch-gate-reset.sh scores every Agent dispatch,
# emits one `dispatch` event carrying the flags, and NEVER blocks — a weak
# dispatch must still clear the lock exactly as before. Lenient is deliberate:
# #1116 documents an agent reflexively `rm`-ing a lock, so a strict bar
# shipped before the evidence exists would train bypass on a hook whose whole
# value is that it is not bypassable.
#
# The flags scored are the ones the evidence supports. `has_escalation` is the
# load-bearing one: mining 2,966 dispatches showed agents essentially never
# hard-fail (err 1.3%), while the 154 labeled telemetry events show the
# dominant failure is a brief with a false premise — and the proven mitigation
# is an explicit escalation clause.
#
# Each positive assertion is paired with its negative counterpart so a flag
# stuck at a constant cannot pass by accident.
#
# Usage: bash test-dispatch-quality.sh   |   Exit 0 all pass, 1 any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESET="$HOOKS_DIR/dispatch-gate-reset.sh"
POST="$HOOKS_DIR/dispatch-gate-post.sh"

PASS_COUNT=0; FAIL_COUNT=0
TESTDIR=$(mktemp -d)
if [ -z "$TESTDIR" ] || [ ! -d "$TESTDIR" ]; then
  echo "FATAL: mktemp -d failed" >&2; exit 1
fi
TEST_LOCK_DIR="$TESTDIR/locks"; mkdir -p "$TEST_LOCK_DIR"
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

make_worktree() { local d="$TESTDIR/$1"; mkdir -p "$d/src"; git -C "$d" init -q; echo "$d"; }

# payload: worktree, subagent_type, model, prompt
payload() {
  jq -n --arg cwd "$1" --arg st "$2" --arg m "$3" --arg p "$4" \
    '{tool_name:"Agent", cwd:$cwd,
      tool_input:({description:"t", subagent_type:$st, prompt:$p}
                  + (if $m == "" then {} else {model:$m} end))}'
}

field() { # log, event-type, field
  # NOTE: must not use `.[$f] // "ABSENT"` — jq's `//` treats a literal
  # `false` as absent, so every false-valued flag would read as ABSENT and
  # the negative half of each contrastive pair would fail spuriously.
  [ -f "$1" ] || { echo MISSING; return; }
  jq -sr --arg ev "$2" --arg f "$3" \
    '[.[]|select(.event==$ev)]|last|if has($f) then .[$f] else "ABSENT" end' "$1" 2>/dev/null || echo ERR
}
count_ev() {
  [ -f "$1" ] || { echo 0; return; }
  jq -sr --arg ev "$2" '[.[]|select(.event==$ev)]|length' "$1" 2>/dev/null || echo 0
}
ok() { if [ "$2" = "$3" ]; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
       else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected=$3 got=$2"; fi }

ESCALATION="Implement the slice. The tests are the spec — if the brief contradicts what you find, stop and report the contradiction. Do not work around it."
PLAIN="Implement the slice and make the suite green."

echo "=== dispatch-quality scoring (#1186, lenient) ==="

# A1/A2 — contrastive pair on the load-bearing flag.
wt=$(make_worktree wtA); LOG="$TESTDIR/a.jsonl"
payload "$wt" "general-purpose" "" "$PLAIN" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "A1 no escalation clause -> has_escalation=false" "$(field "$LOG" dispatch has_escalation)" "false"
ok "A1 no escalation clause -> weak_dispatch=true"   "$(field "$LOG" dispatch weak_dispatch)"  "true"

LOG="$TESTDIR/b.jsonl"
payload "$wt" "general-purpose" "" "$ESCALATION" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "A2 escalation clause present -> has_escalation=true" "$(field "$LOG" dispatch has_escalation)" "true"
ok "A2 escalation clause present -> weak_dispatch=false" "$(field "$LOG" dispatch weak_dispatch)"  "false"

# B — model pinning and named type recorded independently of weakness.
LOG="$TESTDIR/c.jsonl"
payload "$wt" "code-reviewer" "sonnet" "$ESCALATION" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "B1 model pinned -> model_pinned=true"  "$(field "$LOG" dispatch model_pinned)" "true"
ok "B2 named type   -> named_type=true"    "$(field "$LOG" dispatch named_type)"   "true"
LOG="$TESTDIR/d.jsonl"
payload "$wt" "general-purpose" "" "$PLAIN" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "B3 unpinned model -> model_pinned=false" "$(field "$LOG" dispatch model_pinned)" "false"
ok "B4 generic type   -> named_type=false"   "$(field "$LOG" dispatch named_type)"   "false"

# B5/B6 — has_freshness, the one scored flag that had no assertions. It targets
# the dominant failure mode (a brief grounded on a stale local tree or doc), so
# an unasserted flag here is the one most likely to read clean while being broken.
LOG="$TESTDIR/c2.jsonl"
payload "$wt" "general-purpose" "" "Implement it. Verify every factual premise against origin/main before editing." | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "B5 freshness language -> has_freshness=true" "$(field "$LOG" dispatch has_freshness)" "true"
LOG="$TESTDIR/c3.jsonl"
payload "$wt" "general-purpose" "" "$PLAIN" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "B6 no freshness language -> has_freshness=false" "$(field "$LOG" dispatch has_freshness)" "false"

# C — every dispatch scored, including ones that clear no lock. This is the
# whole point: 81% of historical resets beat the gate, so lock-only logging
# would sample the minority and bias the threshold.
ok "C1 dispatch event emitted with no lock present" "$(count_ev "$TESTDIR/d.jsonl" dispatch)" "1"

# D — LENIENT: a weak dispatch must STILL clear the lock. If this ever fails,
# the gate has silently become blocking and #1116's bypass risk is live.
wtD=$(make_worktree wtD); LOG="$TESTDIR/e.jsonl"
for i in 1 2 3 4 5; do
  jq -n --arg fp "$wtD/src/f$i.ts" '{tool_name:"Write", cwd:"/", tool_input:{file_path:$fp}}' | \
    DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null 2>&1
done
before=$(ls "$TEST_LOCK_DIR"/dispatch-gate-pending-*.lock 2>/dev/null | wc -l | tr -d ' ')
payload "$wtD" "general-purpose" "" "$PLAIN" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
after=$(ls "$TEST_LOCK_DIR"/dispatch-gate-pending-*.lock 2>/dev/null | wc -l | tr -d ' ')
ok "D1 lock existed before weak dispatch" "$before" "1"
ok "D2 LENIENT: weak dispatch still cleared it" "$after" "0"
ok "D3 weak dispatch still logged a reset event" "$(count_ev "$LOG" reset)" "1"

# E — Explore is research, not delegation: unchanged early exit, no scoring.
LOG="$TESTDIR/f.jsonl"
payload "$wt" "Explore" "sonnet" "$ESCALATION" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "E1 Explore emits no dispatch event" "$(count_ev "$LOG" dispatch)" "0"

# F — must never write to stdout (a PreToolUse hook writing stdout risks
# being read as a deny payload).
out=$(payload "$wt" "general-purpose" "" "$PLAIN" | \
  DISPATCH_GATE_EVENTS_LOG="$TESTDIR/g.jsonl" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" 2>/dev/null)
ok "F1 no stdout emitted" "${#out}" "0"

# G — fail-open on garbage input.
echo 'not json' | DISPATCH_GATE_EVENTS_LOG="$TESTDIR/h.jsonl" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "G1 malformed input exits 0" "$?" "0"

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
