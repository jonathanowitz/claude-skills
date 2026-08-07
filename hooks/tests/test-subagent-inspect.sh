#!/bin/bash
# Fixture-harness tests for subagent-inspect.sh (#1186 scope item 2).
#
# Contract under test: on SubagentStop, emit exactly one JSONL record of what
# the subagent MECHANICALLY did (from its own transcript) versus what it CLAIMED
# (from last_assistant_message) — and never block, never write stdout, never
# emit additionalContext.
#
# Every claim-detection assertion is paired with its negative counterpart on the
# same claim text, differing only in the transcript evidence. A flag stuck at
# `true` cannot pass.
#
# Fixture note: the transcript shape here was copied from a REAL subagent
# transcript (agent-a19ff7bde8fc17f9b.jsonl, 2026-07-22), not invented — tool
# calls live at .message.content[] with .type=="tool_use", .name, .input on
# records whose top-level .type=="assistant".
#
# Usage: bash test-subagent-inspect.sh   |   Exit 0 all pass, 1 any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSPECT="$HOOKS_DIR/subagent-inspect.sh"

PASS_COUNT=0; FAIL_COUNT=0
TESTDIR=$(mktemp -d)
if [ -z "$TESTDIR" ] || [ ! -d "$TESTDIR" ]; then
  echo "FATAL: mktemp -d failed" >&2; exit 1
fi
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

# tool_use_line <name> <input-json>
tool_use_line() {
  jq -nc --arg n "$1" --argjson inp "$2" \
    '{type:"assistant", message:{role:"assistant", content:[{type:"tool_use", name:$n, input:$inp}]}}'
}
text_line() {
  jq -nc --arg t "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:$t}]}}'
}

# payload <transcript_path> <final_message> [stop_hook_active] [event_name] [decoy_transcript]
payload() {
  jq -n --arg tp "$1" --arg f "$2" --arg sa "${3:-false}" --arg ev "${4:-SubagentStop}" \
        --arg decoy "${5:-/nonexistent/parent.jsonl}" \
    '{hook_event_name:$ev, stop_hook_active:($sa=="true"),
      agent_id:"a19ff7bde8fc17f9b", agent_type:"general-purpose",
      session_id:"s1", cwd:"/", transcript_path:$decoy,
      agent_transcript_path:$tp, last_assistant_message:$f}'
}

run() { # transcript, final, [stop_active], [event], [decoy] -> echoes log path
  local log="$TESTDIR/log.$RANDOM.jsonl"
  payload "$1" "$2" "${3:-false}" "${4:-SubagentStop}" "${5:-/nonexistent/parent.jsonl}" | \
    SUBAGENT_INSPECT_LOG="$log" "$INSPECT" >/dev/null 2>&1
  echo "$log"
}
field() {
  [ -f "$1" ] || { echo MISSING; return; }
  # Not `.[$f] // "ABSENT"`: jq's `//` treats literal false as absent, which
  # would make every negative half of a contrastive pair read ABSENT.
  jq -sr --arg f "$2" '.|last|if has($f) then .[$f] else "ABSENT" end' "$1" 2>/dev/null || echo ERR
}
nrec() { [ -f "$1" ] || { echo 0; return; }; jq -s 'length' "$1" 2>/dev/null || echo 0; }
ok() { if [ "$2" = "$3" ]; then PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";
       else FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected=$3 got=$2"; fi }

CLAIM_TESTS="Done. All tests pass — 42 passed, 0 failed."
CLAIM_VERIFIED="Done. I verified the change end to end."

echo "=== subagent-inspect.sh (#1186, log-only) ==="

# --- A. Claimed tests pass, contrastive on the EVIDENCE only ----------------
T="$TESTDIR/no-tests.jsonl"
tool_use_line Bash '{"command":"ls -la src/"}' > "$T"
L=$(run "$T" "$CLAIM_TESTS")
ok "A1 claims tests pass, ran none -> unverified_test_claim=true" "$(field "$L" unverified_test_claim)" "true"
ok "A1 ran_tests=false" "$(field "$L" ran_tests)" "false"

T="$TESTDIR/with-tests.jsonl"
tool_use_line Bash '{"command":"npm test -- --run"}' > "$T"
L=$(run "$T" "$CLAIM_TESTS")
ok "A2 same claim, tests actually run -> unverified_test_claim=false" "$(field "$L" unverified_test_claim)" "false"
ok "A2 ran_tests=true" "$(field "$L" ran_tests)" "true"

# A3 — no claim at all must not flag, even with no tests run. Guards against
# the flag degenerating into "did not run tests".
L=$(run "$TESTDIR/no-tests.jsonl" "Done. Here is what I found.")
ok "A3 no claim + no tests -> unverified_test_claim=false" "$(field "$L" unverified_test_claim)" "false"

# --- B. Files touched — the parent->subagent linkage that did not exist -----
T="$TESTDIR/files.jsonl"
{ tool_use_line Write '{"file_path":"/w/src/a.ts"}'
  tool_use_line Edit  '{"file_path":"/w/src/b.ts"}'
  tool_use_line Edit  '{"file_path":"/w/src/a.ts"}'
  tool_use_line Bash  '{"command":"echo hi"}'; } > "$T"
L=$(run "$T" "Done.")
ok "B1 file_count dedupes 3 edits over 2 files" "$(field "$L" file_count)" "2"
ok "B2 files_touched captured" "$(jq -sr '.|last|.files_touched|join(",")' "$L")" "/w/src/a.ts,/w/src/b.ts"
ok "B3 tool_calls counts all 4" "$(field "$L" tool_calls)" "4"
# B4 — NotebookEdit is in the extraction list but was never exercised.
T="$TESTDIR/notebook.jsonl"
tool_use_line NotebookEdit '{"file_path":"/w/nb.ipynb"}' > "$T"
ok "B4 NotebookEdit counts as a file touch" "$(field "$(run "$T" "Done.")" file_count)" "1"
# B5 — identity fields pass through to the record rather than being dropped.
ok "B5 agent_id passed through"   "$(field "$L" agent_id)"   "a19ff7bde8fc17f9b"
ok "B5 agent_type passed through" "$(field "$L" agent_type)" "general-purpose"
# B6 — claims_tests_pass asserted standalone, not only via the derived flag.
# Without this a bug flipping it goes unseen whenever ran_tests happens to be true.
ok "B6 claims_tests_pass true on a passing claim"  "$(field "$(run "$TESTDIR/with-tests.jsonl" "$CLAIM_TESTS")" claims_tests_pass)" "true"
ok "B6 claims_tests_pass false with no such claim" "$(field "$(run "$TESTDIR/with-tests.jsonl" "Done, here is a summary.")" claims_tests_pass)" "false"

# --- C. Claimed verification with zero tool use ------------------------------
T="$TESTDIR/empty.jsonl"
text_line "thinking out loud" > "$T"
L=$(run "$T" "$CLAIM_VERIFIED")
ok "C1 claims verified, zero tools -> no_tool_claim=true" "$(field "$L" no_tool_claim)" "true"
L=$(run "$TESTDIR/files.jsonl" "$CLAIM_VERIFIED")
ok "C2 same claim with tool calls -> no_tool_claim=false" "$(field "$L" no_tool_claim)" "false"

# --- D. Gate bypass — #1116's trained-bypass behavior, made visible ---------
T="$TESTDIR/bypass.jsonl"
tool_use_line Bash '{"command":"rm -f /tmp/dispatch-gate-pending-a1b2c3d4.lock"}' > "$T"
L=$(run "$T" "Done.")
ok "D1 rm of a gate lock -> gate_bypass=true" "$(field "$L" gate_bypass)" "true"
T="$TESTDIR/ordinary-rm.jsonl"
tool_use_line Bash '{"command":"rm -f /tmp/scratch-output.txt"}' > "$T"
L=$(run "$T" "Done.")
ok "D2 ordinary rm -> gate_bypass=false" "$(field "$L" gate_bypass)" "false"

# --- E. Reads agent_transcript_path, NOT the parent's transcript_path -------
# The resume brief for this work asserted SubagentStop carries "transcript_path
# (the subagent's)". It carries BOTH: base transcript_path is the PARENT's.
# A hook written off that wording inspects the orchestrator and finds nothing.
# Decoy is a 5-tool-call parent transcript; the real one has 1.
DECOY="$TESTDIR/decoy-parent.jsonl"
for i in 1 2 3 4 5; do tool_use_line Write "{\"file_path\":\"/parent/p$i.ts\"}"; done > "$DECOY"
T="$TESTDIR/real-sub.jsonl"
tool_use_line Bash '{"command":"echo only-one"}' > "$T"
L=$(run "$T" "Done." false SubagentStop "$DECOY")
ok "E1 uses the SUBAGENT transcript (1 call, not the decoy's 5)" "$(field "$L" tool_calls)" "1"
ok "E1 no parent files leaked into files_touched" "$(field "$L" file_count)" "0"

# --- F. Continuation-loop guard ---------------------------------------------
L=$(run "$TESTDIR/files.jsonl" "Done." true)
ok "F1 stop_hook_active=true -> no record written" "$(nrec "$L")" "0"

# --- G. Only fires on its own event -----------------------------------------
L=$(run "$TESTDIR/files.jsonl" "Done." false "Stop")
ok "G1 Stop event -> no record" "$(nrec "$L")" "0"
L=$(run "$TESTDIR/files.jsonl" "Done." false "SubagentStop")
ok "G2 CONTROL SubagentStop -> exactly one record" "$(nrec "$L")" "1"

# --- H. Never blocks, never speaks ------------------------------------------
out=$(payload "$TESTDIR/files.jsonl" "Done." | SUBAGENT_INSPECT_LOG="$TESTDIR/h.jsonl" "$INSPECT" 2>/dev/null)
ok "H1 no stdout emitted" "${#out}" "0"
payload "$TESTDIR/files.jsonl" "Done." | SUBAGENT_INSPECT_LOG="$TESTDIR/h2.jsonl" "$INSPECT" >/dev/null 2>&1
ok "H2 exit 0" "$?" "0"

# --- I. Fail-open ------------------------------------------------------------
echo 'not json' | SUBAGENT_INSPECT_LOG="$TESTDIR/i.jsonl" "$INSPECT" >/dev/null 2>&1
ok "I1 malformed input exits 0" "$?" "0"
L=$(run "/nonexistent/gone.jsonl" "$CLAIM_TESTS")
ok "I2 unreadable transcript still logs a record" "$(nrec "$L")" "1"
ok "I3 unreadable transcript defaults tool_calls=0" "$(field "$L" tool_calls)" "0"
# I4/I5 — "no evidence COLLECTED" must not be scored as "no evidence FOUND".
# Without this the same claim that legitimately flags at A1 also flags for an
# agent that may well have run the suite, and the record cannot tell them apart.
ok "I4 unreadable transcript -> transcript_read=false"     "$(field "$L" transcript_read)"        "false"
ok "I4 unreadable transcript -> claim NOT flagged"         "$(field "$L" unverified_test_claim)"  "false"
L=$(run "/nonexistent/gone.jsonl" "$CLAIM_VERIFIED")
ok "I5 unreadable transcript -> no_tool_claim NOT flagged" "$(field "$L" no_tool_claim)"          "false"
ok "I5 CONTROL readable-but-empty IS flagged"              "$(field "$(run "$TESTDIR/empty.jsonl" "$CLAIM_VERIFIED")" no_tool_claim)" "true"

# --- J. One record == one LINE ----------------------------------------------
# jq pretty-prints by default, which puts multi-line blocks in a .jsonl: every
# reader in this repo uses jq -s and parses them anyway, so no existing test
# could catch it. Measured on the live log before the fix: 106 lines, 6 records.
L="$TESTDIR/lines.jsonl"
for i in 1 2 3; do
  payload "$TESTDIR/files.jsonl" "Done." | SUBAGENT_INSPECT_LOG="$L" "$INSPECT" >/dev/null 2>&1
done
ok "J1 3 invocations -> 3 lines" "$(wc -l < "$L" | tr -d ' ')" "3"
ok "J1 3 invocations -> 3 records" "$(nrec "$L")" "3"

# --- K. Streaming, not slurp: one truncated line must not zero every fact ----
# SubagentStop can fire before the final record is flushed, so a truncated last
# line is a live race. Under jq -s the whole file fails and tool_calls, files
# and cmds all fall back at once.
T="$TESTDIR/truncated.jsonl"
{ tool_use_line Bash '{"command":"npm test"}'
  tool_use_line Write '{"file_path":"/w/src/keep.ts"}'
  printf '{"type":"assistant","message":{"cont\n'; } > "$T"
L=$(run "$T" "$CLAIM_TESTS")
ok "K1 truncated tail -> intact records still counted" "$(field "$L" tool_calls)" "2"
ok "K1 truncated tail -> test run still detected"      "$(field "$L" ran_tests)"  "true"
ok "K1 truncated tail -> claim NOT falsely flagged"    "$(field "$L" unverified_test_claim)" "false"
ok "K1 truncated tail -> file still captured"          "$(field "$L" file_count)" "1"

# --- L. gate_bypass word boundary -------------------------------------------
T="$TESTDIR/confirm.jsonl"
tool_use_line Bash '{"command":"echo confirm dispatch-gate-pending-foo.lock exists"}' > "$T"
ok "L1 'confi(rm )dispatch-gate-...' is NOT a bypass" "$(field "$(run "$T" "Done.")" gate_bypass)" "false"
T="$TESTDIR/rmdir.jsonl"
tool_use_line Bash '{"command":"rmdir /tmp/dispatch-gate-pending-a1.lock.lockdir"}' > "$T"
ok "L2 rmdir of the lock IS a bypass" "$(field "$(run "$T" "Done.")" gate_bypass)" "true"

# --- M. Test-runner shorthands ----------------------------------------------
for c in "npm t" "make test"; do
  T="$TESTDIR/runner.jsonl"
  jq -nc --arg cmd "$c" '{type:"assistant", message:{role:"assistant", content:[{type:"tool_use", name:"Bash", input:{command:$cmd}}]}}' > "$T"
  ok "M1 '$c' counts as running tests" "$(field "$(run "$T" "$CLAIM_TESTS")" ran_tests)" "true"
done
T="$TESTDIR/notrunner.jsonl"
tool_use_line Bash '{"command":"npm install"}' > "$T"
ok "M2 CONTROL 'npm install' does not" "$(field "$(run "$T" "$CLAIM_TESTS")" ran_tests)" "false"

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
