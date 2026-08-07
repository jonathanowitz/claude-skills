#!/bin/bash
# Fixture-harness tests for #1116 Defect 2 — the dispatch gate must not fire
# inside the subagent it asked for.
#
# Contract under test: when the hook payload carries `agent_id` (present ONLY
# inside a subagent), dispatch-gate-pre.sh never denies and dispatch-gate-post.sh
# never counts. On the main thread (`agent_id` absent) both behave exactly as
# before.
#
# Every subagent-suppression assertion is paired with its main-thread positive
# control on the SAME input, so a guard that suppressed everything — or a gate
# that had quietly stopped firing for an unrelated reason — cannot pass. Without
# the paired control, "no deny was emitted" proves nothing.
#
# Fixture note: agent_id is a TOP-LEVEL payload field, not tool_input. Verified
# against a live PreToolUse payload on 2026-07-22 (main thread agent_id=null;
# dispatched subagent agent_id="a19ff7bde8fc17f9b", agent_type
# "general-purpose", identical session_id in both).
#
# Usage: bash test-dispatch-subagent-guard.sh   |   Exit 0 all pass, 1 any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRE="$HOOKS_DIR/dispatch-gate-pre.sh"
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

# write_payload <file_path> <agent_id>   — agent_id "" means main thread.
write_payload() {
  jq -n --arg fp "$1" --arg aid "$2" \
    '{tool_name:"Write", cwd:"/", tool_input:{file_path:$fp}}
     + (if $aid == "" then {} else {agent_id:$aid, agent_type:"general-purpose"} end)'
}
# bash_payload <command> <cwd> <agent_id>
bash_payload() {
  jq -n --arg c "$1" --arg cwd "$2" --arg aid "$3" \
    '{tool_name:"Bash", cwd:$cwd, tool_input:{command:$c}}
     + (if $aid == "" then {} else {agent_id:$aid, agent_type:"general-purpose"} end)'
}

# Arm a lock at/above threshold for the given worktree, main-thread only.
arm_lock() {
  local wt="$1" i
  for i in 1 2 3 4 5; do
    write_payload "$wt/src/armed$i.ts" "" | \
      DISPATCH_GATE_EVENTS_LOG="$TESTDIR/arm.jsonl" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" \
      "$POST" >/dev/null 2>&1
  done
}

denied() { # reads stdout of a pre-hook run, echoes yes/no
  if printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo yes; else echo no; fi
}
lock_count() { ls "$TEST_LOCK_DIR"/dispatch-gate-pending-*.lock 2>/dev/null | wc -l | tr -d ' '; }
ok() { if [ "$2" = "$3" ]; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
       else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected=$3 got=$2"; fi }

echo "=== #1116 Defect 2 — gate must not fire inside a subagent ==="

# --- A. Write/Edit deny path, contrastive on agent_id only ------------------
wtA=$(make_worktree wtA)
arm_lock "$wtA"

out=$(write_payload "$wtA/src/target.ts" "" | \
  DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE" 2>/dev/null)
ok "A1 CONTROL main thread over threshold -> DENIED" "$(denied "$out")" "yes"

out=$(write_payload "$wtA/src/target.ts" "a19ff7bde8fc17f9b" | \
  DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE" 2>/dev/null)
ok "A2 same lock, inside subagent -> NOT denied" "$(denied "$out")" "no"
ok "A2 subagent path emits no stdout at all"     "${#out}"          "0"

# --- B. Bash mutation-pattern deny path, same pairing -----------------------
out=$(bash_payload "sed -i '' s/a/b/ $wtA/src/target.ts" "$wtA" "" | \
  DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE" 2>/dev/null)
ok "B1 CONTROL main thread sed -i -> DENIED" "$(denied "$out")" "yes"

out=$(bash_payload "sed -i '' s/a/b/ $wtA/src/target.ts" "$wtA" "a19ff7bde8fc17f9b" | \
  DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE" 2>/dev/null)
ok "B2 same command, inside subagent -> NOT denied" "$(denied "$out")" "no"

# --- C. Counting half: a subagent's edits must not accrue orchestrator debt --
# Without this the defect just moves one step later — reset.sh clears the lock
# on dispatch, then the subagent's own edits rebuild it and the orchestrator is
# denied the instant the subagent returns.
rm -f "$TEST_LOCK_DIR"/dispatch-gate-pending-*.lock
wtC=$(make_worktree wtC)
for i in 1 2 3 4 5 6; do
  write_payload "$wtC/src/sub$i.ts" "a19ff7bde8fc17f9b" | \
    DISPATCH_GATE_EVENTS_LOG="$TESTDIR/c.jsonl" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" \
    "$POST" >/dev/null 2>&1
done
ok "C1 6 subagent edits create NO lock" "$(lock_count)" "0"

wtD=$(make_worktree wtD)
arm_lock "$wtD"
ok "C2 CONTROL 5 main-thread edits DO create a lock" "$(lock_count)" "1"

# --- D. Guard is scoped to agent_id, not a blanket disable ------------------
# Below threshold the main thread must also pass — proves A2/B2 above were the
# guard doing its job, not the gate being inert in this harness.
rm -f "$TEST_LOCK_DIR"/dispatch-gate-pending-*.lock
wtE=$(make_worktree wtE)
write_payload "$wtE/src/one.ts" "" | \
  DISPATCH_GATE_EVENTS_LOG="$TESTDIR/e.jsonl" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null 2>&1
out=$(write_payload "$wtE/src/one.ts" "" | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE" 2>/dev/null)
ok "D1 main thread below threshold -> not denied" "$(denied "$out")" "no"

# --- F. reset.sh records WHO dispatched, so nested dispatches are filterable --
# A nested dispatch still clears the lock — that is the documented-safe
# over-crediting direction. But its quality event must not be indistinguishable
# from an orchestrator's: unlike the lock, which self-heals in five edits, a
# polluted `dispatch` event permanently biases the dataset the blocking
# threshold gets set from.
RESET="$HOOKS_DIR/dispatch-gate-reset.sh"
agent_payload() { # subagent_type, agent_id
  jq -n --arg st "$1" --arg aid "$2" \
    '{tool_name:"Agent", cwd:"/", tool_input:{description:"t", subagent_type:$st, prompt:"do the thing"}}
     + (if $aid == "" then {} else {agent_id:$aid, agent_type:"general-purpose"} end)'
}
dfield() { jq -sr --arg f "$2" '[.[]|select(.event=="dispatch")]|last|if has($f) then .[$f] else "ABSENT" end' "$1" 2>/dev/null; }

LOG="$TESTDIR/f1.jsonl"
agent_payload "general-purpose" "" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "F1 main-thread dispatch -> dispatched_by_agent_id empty" "$(dfield "$LOG" dispatched_by_agent_id)" ""

LOG="$TESTDIR/f2.jsonl"
agent_payload "general-purpose" "a19ff7bde8fc17f9b" | \
  DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
ok "F2 nested dispatch -> dispatched_by_agent_id recorded" "$(dfield "$LOG" dispatched_by_agent_id)" "a19ff7bde8fc17f9b"

# One record must be one LINE — jq pretty-prints by default, and no existing
# test could catch it because every reader here uses jq -s.
LOG="$TESTDIR/f3.jsonl"
for i in 1 2 3; do
  agent_payload "general-purpose" "" | \
    DISPATCH_GATE_EVENTS_LOG="$LOG" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null 2>&1
done
ok "F3 3 dispatches -> 3 lines"   "$(wc -l < "$LOG" | tr -d ' ')" "3"
ok "F3 3 dispatches -> 3 records" "$(jq -s length "$LOG" 2>/dev/null)" "3"

# --- E. Fail-open ------------------------------------------------------------
echo 'not json' | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE" >/dev/null 2>&1
ok "E1 pre-hook malformed input exits 0" "$?" "0"
echo 'not json' | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null 2>&1
ok "E2 post-hook malformed input exits 0" "$?" "0"

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
