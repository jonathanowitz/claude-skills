#!/bin/bash
# Fixture-harness test suite for the Mechanical Dispatch Gate.
# Spec: dev-reference/briefs/mechanical-dispatch-gate.md § Verification
# (Fixture-Harness Assertions 1-13, covering behavior map entries B1-B12).
#
# RED state (now): dispatch-gate-{post,pre,reset,report}.sh are behaviorally
# inert stubs (consume input, exit 0, never write a lock / never deny / never
# clear / never report). Assertions that check for NEW behavior must fail
# here with a real expected-vs-got mismatch, not a "command not found".
#
# Several assertions are structurally unable to distinguish "real negative
# result" from "stub does nothing" — these are marked STUB-VACUOUS below and
# are justified only in combination with their positive-case counterpart
# (the contrastive-control pattern from Stage 4 step 4 of
# dev-reference/workflows/development-process.md). They are not deleted
# because they become real regression guards once the implementation exists.
#
# GREEN state (after implementation): every assertion must pass, including
# the STUB-VACUOUS ones now exercising real logic instead of a no-op.
#
# Usage: bash test-dispatch-gate.sh
# Exit code: 0 if all assertions pass, 1 if any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POST="$HOOKS_DIR/dispatch-gate-post.sh"
PRE="$HOOKS_DIR/dispatch-gate-pre.sh"
RESET="$HOOKS_DIR/dispatch-gate-reset.sh"
REPORT="$HOOKS_DIR/dispatch-gate-report.sh"
SETTINGS_JSON="$HOOKS_DIR/../settings.json"

PASS_COUNT=0
FAIL_COUNT=0

TESTDIR=$(mktemp -d)
# Guard against mktemp failing (e.g. full disk) and leaving TESTDIR empty —
# without this, cleanup()'s `rm -rf "$TESTDIR"` becomes `rm -rf ""` (a
# harmless no-op, but silently so) and TEST_LOCK_DIR resolves to `/locks`
# at the filesystem root. Found via cross-model review (Gemini).
[ -n "$TESTDIR" ] && [ -d "$TESTDIR" ] || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
TEST_LOCK_DIR="$TESTDIR/locks"
mkdir -p "$TEST_LOCK_DIR"
cleanup() {
  # Locks now live entirely under $TEST_LOCK_DIR (via DISPATCH_GATE_LOCK_DIR
  # passed to every POST/PRE/RESET invocation below), which is nested inside
  # $TESTDIR — a single rm -rf removes both. No more sweeping the real /tmp
  # namespace by worktree-header inspection (the prior stopgap, needed only
  # because locks used to be written directly to /tmp regardless of TESTDIR).
  rm -rf "$TESTDIR"
}
trap cleanup EXIT

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "PASS: $1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo "FAIL: $1"
  echo "  expected: $2"
  echo "  got:      $3"
}

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# Real git-inited temp dirs so `git -C <dir> rev-parse --show-toplevel`
# resolves (matching how test-review-gate-{pre,post}.sh resolve worktrees).
# Lock-file isolation from production locks comes from DISPATCH_GATE_LOCK_DIR
# (passed to every POST/PRE/RESET invocation below, pointed at
# $TEST_LOCK_DIR) — distinct worktree hashes alone aren't enough once
# reset.sh globs every lock in its directory rather than resolving one by
# hash (see dispatch-gate-reset.sh's header).
make_worktree() {
  local dir="$TESTDIR/$1"
  mkdir -p "$dir/src"
  git -C "$dir" init -q
  echo "$dir"
}

# Canonicalize the same way the hooks do (git -C <dir> rev-parse
# --show-toplevel), not just the raw path string. On macOS, /tmp and /var
# are symlinks to /private/tmp and /private/var — git's resolution
# canonicalizes through them, so hashing the raw mktemp path would silently
# diverge from what the hooks actually compute. This bit dispatch-gate-
# reset.sh's cwd-based resolution specifically (a real, existing directory,
# so git always resolves it) even though file-path-based resolution masked
# the same issue when the referenced file's parent directory didn't yet
# exist on disk (never true for a real Write/Edit call in production).
canonical_worktree() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || echo "$1"; }
worktree_hash() { echo -n "$(canonical_worktree "$1")" | shasum -a 256 | cut -c1-8; }
lock_path_for() { echo "$TEST_LOCK_DIR/dispatch-gate-pending-$(worktree_hash "$1").lock"; }

# Seed a lock file directly (bypassing dispatch-gate-post.sh) so PreToolUse /
# reset assertions can start from known prior state instead of depending on
# post.sh already working.
#
# Canonicalizes $1 for the `# worktree=` header line (not just the lock
# path) to match what real dispatch-gate-post.sh always writes there (its
# `worktree` var comes straight out of `git rev-parse --show-toplevel`).
# reset.sh reads that header verbatim rather than re-deriving it, so a
# fixture writing the raw mktemp path (pre-symlink-resolution, e.g. /var/...
# instead of /private/var/... on macOS) would silently diverge from what
# events_count's canonicalized filter expects.
seed_lock() {
  local raw_worktree="$1" worktree cumulative="$2" threshold="${3:-5}"
  local lock
  worktree=$(canonical_worktree "$raw_worktree")
  lock=$(lock_path_for "$raw_worktree")
  {
    printf '# DISPATCH_GATE lock\n'
    printf '# cumulative_edits=%s\n' "$cumulative"
    printf '# threshold=%s\n' "$threshold"
    printf '# worktree=%s\n' "$worktree"
    printf '# first_seen=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local i
    for i in $(seq 1 "$cumulative"); do
      printf '%s/seed-file-%s.ts\tEdit\t%s\n' "$worktree" "$i" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    done
  } > "$lock"
  echo "$lock"
}

write_payload() {
  local worktree="$1" file_path="$2"
  jq -n --arg cwd "$worktree" --arg fp "$file_path" \
    '{tool_name: "Write", cwd: $cwd, tool_input: {file_path: $fp, content: "x"}}'
}

bash_payload() {
  local worktree="$1" command="$2"
  jq -n --arg cwd "$worktree" --arg cmd "$command" \
    '{tool_name: "Bash", cwd: $cwd, tool_input: {command: $cmd}}'
}

agent_payload() {
  local worktree="$1" subagent_type="$2"
  jq -n --arg cwd "$worktree" --arg st "$subagent_type" \
    '{tool_name: "Agent", cwd: $cwd, tool_input: {description: "test dispatch", subagent_type: $st, prompt: "do the thing"}}'
}

lock_cumulative() {
  local lock="$1"
  [ -f "$lock" ] || { echo "MISSING"; return; }
  grep -E '^# cumulative_edits=' "$lock" | head -1 | sed -E 's/.*=//'
}

# Per-assertion isolated events log so telemetry checks never touch the real
# production log (~/.claude/dispatch-gate-events.jsonl). Interface: the
# implementation must honor $DISPATCH_GATE_EVENTS_LOG when set (see
# dispatch-gate-report.sh stub header for the same override on the read side).
events_count() {
  local log="$1" event="$2" worktree
  worktree=$(canonical_worktree "$3")
  [ -f "$log" ] || { echo 0; return; }
  jq -sr --arg ev "$event" --arg wt "$worktree" \
    '[.[] | select(.event == $ev and .worktree == $wt)] | length' "$log" 2>/dev/null || echo 0
}

echo "=== Mechanical Dispatch Gate — fixture-harness assertions ==="
echo

# ---------------------------------------------------------------------------
# 1. Five sequential non-allowlisted Edit payloads → cumulative reaches 5,
#    exactly one trigger event. Covers B1, B3.
# ---------------------------------------------------------------------------
wt1=$(make_worktree "wt1")
lock1=$(lock_path_for "$wt1")
events1="$TESTDIR/events1.jsonl"
rm -f "$lock1"
for i in 1 2 3 4 5; do
  write_payload "$wt1" "$wt1/src/foo${i}.ts" | DISPATCH_GATE_EVENTS_LOG="$events1" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null
done
cum1=$(lock_cumulative "$lock1")
trig1=$(events_count "$events1" "trigger" "$wt1")
if [ "$cum1" = "5" ] && [ "$trig1" = "1" ]; then
  pass "1: five non-allowlisted edits -> lock cumulative=5, exactly 1 trigger event"
else
  fail "1: five non-allowlisted edits -> lock cumulative=5, exactly 1 trigger event" \
    "cumulative=5, trigger_events=1" "cumulative=$cum1, trigger_events=$trig1"
fi

# ---------------------------------------------------------------------------
# 2. Allowlisted docs/briefs/x.md Write -> lock unchanged. Covers B2.
#    Paired contrastive control: same seeded state, non-allowlisted edit DOES
#    increment. Without the control this assertion is STUB-VACUOUS (a no-op
#    stub also "leaves the lock unchanged").
# ---------------------------------------------------------------------------
wt2=$(make_worktree "wt2")
seed_lock "$wt2" 3 >/dev/null
lock2=$(lock_path_for "$wt2")
mkdir -p "$wt2/docs/briefs"
events2="$TESTDIR/events2.jsonl"
write_payload "$wt2" "$wt2/docs/briefs/x.md" | DISPATCH_GATE_EVENTS_LOG="$events2" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null
cum2_after_allowlisted=$(lock_cumulative "$lock2")
write_payload "$wt2" "$wt2/src/bar.ts" | DISPATCH_GATE_EVENTS_LOG="$events2" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null
cum2_after_nonallowlisted=$(lock_cumulative "$lock2")
if [ "$cum2_after_allowlisted" = "3" ] && [ "$cum2_after_nonallowlisted" = "4" ]; then
  pass "2: allowlisted write leaves cumulative at 3; non-allowlisted control increments to 4"
else
  fail "2: allowlisted write leaves cumulative at 3; non-allowlisted control increments to 4" \
    "3, then 4" "$cum2_after_allowlisted, then $cum2_after_nonallowlisted"
fi

# ---------------------------------------------------------------------------
# 3. pre.sh with cumulative < threshold -> exits 0, no deny. Covers B4 (negative).
#    STUB-VACUOUS alone (a no-op stub also never denies) — justified only
#    paired with assertion 4's positive case.
# ---------------------------------------------------------------------------
wt3=$(make_worktree "wt3")
seed_lock "$wt3" 3 >/dev/null
out3=$(write_payload "$wt3" "$wt3/src/foo.ts" | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE")
code3=$?
if [ "$code3" -eq 0 ] && [ -z "$out3" ]; then
  pass "3: pre.sh below threshold -> exit 0, no deny output [STUB-VACUOUS, see assertion 4]"
else
  fail "3: pre.sh below threshold -> exit 0, no deny output" "exit 0, empty stdout" "exit $code3, stdout='$out3'"
fi

# ---------------------------------------------------------------------------
# 4. pre.sh with cumulative >= threshold, non-allowlisted -> deny. Covers B4.
# ---------------------------------------------------------------------------
wt4=$(make_worktree "wt4")
seed_lock "$wt4" 5 >/dev/null
out4=$(write_payload "$wt4" "$wt4/src/foo.ts" | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE")
decision4=$(echo "$out4" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null)
if [ "$decision4" = "deny" ]; then
  pass "4: pre.sh at/above threshold, non-allowlisted -> permissionDecision=deny"
else
  fail "4: pre.sh at/above threshold, non-allowlisted -> permissionDecision=deny" "deny" "'$decision4' (raw: $out4)"
fi

# ---------------------------------------------------------------------------
# 5. pre.sh with cumulative >= threshold, allowlisted (CLAUDE.md) -> no deny.
#    Covers B2+B4 interaction. STUB-VACUOUS alone — justified paired with
#    assertion 4 (same threshold state, non-allowlisted DOES deny).
# ---------------------------------------------------------------------------
wt5=$(make_worktree "wt5")
seed_lock "$wt5" 5 >/dev/null
out5=$(write_payload "$wt5" "$wt5/CLAUDE.md" | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE")
code5=$?
if [ "$code5" -eq 0 ] && [ -z "$out5" ]; then
  pass "5: pre.sh at/above threshold, allowlisted CLAUDE.md -> no deny [STUB-VACUOUS, see assertion 4]"
else
  fail "5: pre.sh at/above threshold, allowlisted CLAUDE.md -> no deny" "exit 0, empty stdout" "exit $code5, stdout='$out5'"
fi

# ---------------------------------------------------------------------------
# 6. reset.sh with subagent_type=general-purpose, existing lock, Agent call's
#    cwd DELIBERATELY set to a DIFFERENT worktree than the one holding the
#    lock -> lock still removed, reset event still appended. Covers B5.
#
#    The cwd mismatch is the point, not an oversight: real orchestrator usage
#    never `cd`s into a worktree (global CLAUDE.md convention — edits target
#    worktrees by absolute file_path instead), so the Agent tool call's cwd
#    is always the session's fixed launch directory, never the worktree that
#    actually accumulated the edits. An earlier version of reset.sh resolved
#    a single worktree from cwd and cleared only that lock — passed this
#    assertion only because the original fixture happened to pass the same
#    path as both cwd and the seeded lock's worktree. A live-session check
#    (two real Agent dispatches, one lock keyed to the session cwd and one
#    keyed to a different real worktree) showed the session-cwd lock cleared
#    but the other worktree's lock did not, which is the realistic case and
#    would have made the gate never clear in production. Fixed by having
#    reset.sh glob-clear every active lock on any real dispatch instead of
#    resolving one from cwd — this fixture now encodes that fix.
# ---------------------------------------------------------------------------
wt6=$(make_worktree "wt6")
session_cwd6=$(make_worktree "wt6-session")
seed_lock "$wt6" 5 >/dev/null
lock6=$(lock_path_for "$wt6")
events6="$TESTDIR/events6.jsonl"
agent_payload "$session_cwd6" "general-purpose" | DISPATCH_GATE_EVENTS_LOG="$events6" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null
reset6=$(events_count "$events6" "reset" "$wt6")
if [ ! -f "$lock6" ] && [ "$reset6" = "1" ]; then
  pass "6: real Agent dispatch (cwd != locked worktree) -> lock removed, 1 reset event"
else
  fail "6: real Agent dispatch (cwd != locked worktree) -> lock removed, 1 reset event" \
    "lock absent, reset_events=1" "lock_exists=$([ -f "$lock6" ] && echo yes || echo no), reset_events=$reset6"
fi

# ---------------------------------------------------------------------------
# 7. reset.sh with subagent_type=Explore, existing lock -> lock NOT removed,
#    no event. Covers B6. STUB-VACUOUS alone — justified paired with
#    assertion 6 (general-purpose DOES clear the same starting state).
# ---------------------------------------------------------------------------
wt7=$(make_worktree "wt7")
seed_lock "$wt7" 5 >/dev/null
lock7=$(lock_path_for "$wt7")
events7="$TESTDIR/events7.jsonl"
agent_payload "$wt7" "Explore" | DISPATCH_GATE_EVENTS_LOG="$events7" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null
reset7=$(events_count "$events7" "reset" "$wt7")
if [ -f "$lock7" ] && [ "$reset7" = "0" ]; then
  pass "7: Explore dispatch -> lock NOT removed, no reset event [STUB-VACUOUS, see assertion 6]"
else
  fail "7: Explore dispatch -> lock NOT removed, no reset event" \
    "lock present, reset_events=0" "lock_exists=$([ -f "$lock7" ] && echo yes || echo no), reset_events=$reset7"
fi

# ---------------------------------------------------------------------------
# 8. reset.sh with no existing lock -> exits 0, no error, no event.
#    Covers B7. Defensive/robustness check — expected to pass even at stub
#    stage; becomes a real regression guard once real logic exists.
# ---------------------------------------------------------------------------
wt8=$(make_worktree "wt8")
events8="$TESTDIR/events8.jsonl"
agent_payload "$wt8" "general-purpose" | DISPATCH_GATE_EVENTS_LOG="$events8" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null
code8=$?
reset8=$(events_count "$events8" "reset" "$wt8")
if [ "$code8" -eq 0 ] && [ "$reset8" = "0" ]; then
  pass "8: reset.sh with no lock -> exit 0, no event"
else
  fail "8: reset.sh with no lock -> exit 0, no event" "exit 0, reset_events=0" "exit $code8, reset_events=$reset8"
fi

# ---------------------------------------------------------------------------
# 9. Malformed/missing fields -> all three scripts exit 0 (fail-open).
#    Covers B10. Expected to pass even at stub stage (stub is already an
#    unconditional no-op) — becomes a real regression guard once jq parsing
#    logic exists that could otherwise throw on garbage input.
# ---------------------------------------------------------------------------
bad_inputs=('{}' '{"tool_name": null}' 'not json at all' '')
all_ok=1
detail=""
for bad in "${bad_inputs[@]}"; do
  for script in "$POST" "$PRE" "$RESET"; do
    out=$(printf '%s' "$bad" | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$script" 2>&1)
    code=$?
    if [ "$code" -ne 0 ]; then
      all_ok=0
      detail="$detail | $(basename "$script") on '$bad' exited $code"
    fi
  done
done
if [ "$all_ok" -eq 1 ]; then
  pass "9: malformed/missing-field input -> all three scripts exit 0 (fail-open)"
else
  fail "9: malformed/missing-field input -> all three scripts exit 0 (fail-open)" "exit 0 always" "$detail"
fi

# ---------------------------------------------------------------------------
# 10. Two distinct worktrees -> distinct lock hashes, no cross-contamination.
#     Covers B9.
# ---------------------------------------------------------------------------
wtA=$(make_worktree "wtA")
wtB=$(make_worktree "wtB")
lockA=$(lock_path_for "$wtA")
lockB=$(lock_path_for "$wtB")
eventsAB="$TESTDIR/eventsAB.jsonl"
for i in 1 2 3 4 5; do
  write_payload "$wtA" "$wtA/src/foo${i}.ts" | DISPATCH_GATE_EVENTS_LOG="$eventsAB" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null
done
write_payload "$wtB" "$wtB/src/bar.ts" | DISPATCH_GATE_EVENTS_LOG="$eventsAB" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null
cumA=$(lock_cumulative "$lockA")
cumB=$(lock_cumulative "$lockB")
if [ "$lockA" != "$lockB" ] && [ "$cumA" = "5" ] && [ "$cumB" = "1" ]; then
  pass "10: two worktrees -> distinct lock paths, independent cumulative counts (5 vs 1)"
else
  fail "10: two worktrees -> distinct lock paths, independent cumulative counts (5 vs 1)" \
    "distinct paths, cumA=5, cumB=1" "lockA=$lockA lockB=$lockB, cumA=$cumA, cumB=$cumB"
fi

# ---------------------------------------------------------------------------
# 11. Bash bypass: gate active, sed -i / real redirect / real tee pipe ->
#     denied. Pattern text (sed -i, >, tee) appearing only inside a quoted
#     arg -> NOT denied. Covers B11.
#
#     Originally only tested the sed -i quoted case, which was already safe
#     because of its command-start anchoring — that left the actually-broken
#     branches (redirect, tee) completely uncovered. A cross-model review
#     (Gemini) caught this as a test-harness blindspot after finding the
#     real bug it was masking: `[^&|;]*>[[:space:]]*[^&]` and `.*\btee\b`
#     matched ANYWHERE in the string, not just at a real shell-metacharacter
#     position, so `npm test -- --grep "user > account"`, `echo "sweet
#     tee"`, and `gh issue comment --body "see the tee pipe example"` were
#     all false-positive denied. Fixed by stripping quoted substrings before
#     the sed/perl/tee/redirect check (see dispatch-gate-pre.sh's Bash-arm
#     comment) — this assertion now covers both the fix and the gap that let
#     it ship uncaught the first time.
# ---------------------------------------------------------------------------
wt11=$(make_worktree "wt11")
seed_lock "$wt11" 5 >/dev/null
decide11() {
  # pre.sh prints NOTHING on allow (bare exit 0), only JSON on deny — jq
  # errors (and produces no stdout) on empty input, so the `// "allow"`
  # fallback inside a jq filter never fires for the allow case. Check for
  # empty output before invoking jq at all.
  local out decision
  out=$(bash_payload "$wt11" "$1" | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE")
  [ -n "$out" ] || { echo "allow"; return; }
  decision=$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  echo "${decision:-allow}"
}
d_sed_real=$(decide11 "sed -i 's/x/y/' src/foo.ts")
d_sed_quoted=$(decide11 'gh pr create --body "run sed -i on the server"')
d_redirect_real=$(decide11 'cat src/foo.ts > src/bar.ts')
d_redirect_quoted=$(decide11 'npm run test -- --grep "user > account"')
d_tee_real=$(decide11 'echo hi | tee src/foo.ts')
d_tee_quoted=$(decide11 'echo "sweet tee"')
d_tee_quoted2=$(decide11 'gh issue comment 5 --body "see the tee pipe example"')
if [ "$d_sed_real" = "deny" ] && [ "$d_sed_quoted" = "allow" ] \
  && [ "$d_redirect_real" = "deny" ] && [ "$d_redirect_quoted" = "allow" ] \
  && [ "$d_tee_real" = "deny" ] && [ "$d_tee_quoted" = "allow" ] && [ "$d_tee_quoted2" = "allow" ]; then
  pass "11: real sed -i/redirect/tee denied; same pattern text inside a quoted arg allowed (all 3 mutation classes)"
else
  fail "11: real sed -i/redirect/tee denied; same pattern text inside a quoted arg allowed (all 3 mutation classes)" \
    "deny,allow,deny,allow,deny,allow,allow" \
    "sed=$d_sed_real/$d_sed_quoted redirect=$d_redirect_real/$d_redirect_quoted tee=$d_tee_real/$d_tee_quoted/$d_tee_quoted2"
fi

# ---------------------------------------------------------------------------
# 12. Concurrent post.sh invocations against the same lock -> no dropped
#     increments, no corrupted lock. Covers B12.
# ---------------------------------------------------------------------------
wt12=$(make_worktree "wt12")
lock12=$(lock_path_for "$wt12")
events12="$TESTDIR/events12.jsonl"
rm -f "$lock12"
N=10
pids=()
for i in $(seq 1 "$N"); do
  ( write_payload "$wt12" "$wt12/src/concurrent${i}.ts" | DISPATCH_GATE_EVENTS_LOG="$events12" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null ) &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
cum12=$(lock_cumulative "$lock12")
lines12=0
[ -f "$lock12" ] && lines12=$(grep -vc '^#' "$lock12")
if [ "$cum12" = "$N" ] && [ "$lines12" = "$N" ]; then
  pass "12: $N concurrent post.sh invocations -> cumulative=$N, $N data lines, no corruption"
else
  fail "12: $N concurrent post.sh invocations -> cumulative=$N, $N data lines, no corruption" \
    "cumulative=$N, lines=$N" "cumulative=$cum12, lines=$lines12"
fi

# ---------------------------------------------------------------------------
# 13. report.sh escape-hatch inference against constructed JSONL fixtures.
#     Covers C7 (previously untested per Gemini review finding).
# ---------------------------------------------------------------------------
fixture13a="$TESTDIR/fixture13a.jsonl"
cat > "$fixture13a" <<EOF
{"timestamp":"2026-07-11T10:00:00Z","event":"trigger","worktree":"/tmp/wt-x","cumulative":5,"files":["a.ts"]}
{"timestamp":"2026-07-11T11:00:00Z","event":"trigger","worktree":"/tmp/wt-x","cumulative":6,"files":["b.ts"]}
EOF
out13a=$(DISPATCH_GATE_EVENTS_LOG="$fixture13a" "$REPORT" "$fixture13a" 2>&1)
escape13a=$(echo "$out13a" | grep -Eio 'escape-hatch-inferred:[[:space:]]*[0-9]+' | grep -Eo '[0-9]+' | head -1)

fixture13b="$TESTDIR/fixture13b.jsonl"
cat > "$fixture13b" <<EOF
{"timestamp":"2026-07-11T10:00:00Z","event":"trigger","worktree":"/tmp/wt-y","cumulative":5,"files":["a.ts"]}
{"timestamp":"2026-07-11T10:05:00Z","event":"reset","worktree":"/tmp/wt-y","cumulative_at_reset":6,"subagent_type":"general-purpose"}
EOF
out13b=$(DISPATCH_GATE_EVENTS_LOG="$fixture13b" "$REPORT" "$fixture13b" 2>&1)
escape13b=$(echo "$out13b" | grep -Eio 'escape-hatch-inferred:[[:space:]]*[0-9]+' | grep -Eo '[0-9]+' | head -1)

if [ "$escape13a" = "1" ] && [ "$escape13b" = "0" ]; then
  pass "13: report.sh infers 1 escape-hatch event for unmatched trigger, 0 for trigger+matching reset"
else
  fail "13: report.sh infers 1 escape-hatch event for unmatched trigger, 0 for trigger+matching reset" \
    "1, then 0" "'$escape13a' (raw: $out13a), then '$escape13b' (raw: $out13b)"
fi

# ---------------------------------------------------------------------------
# 14. Two DISTINCT worktrees both have active locks; one real Agent dispatch
#     (cwd matching neither) -> BOTH locks removed, 2 reset events, each
#     tagged with its own worktree and cumulative_at_reset. Directly exercises
#     the glob-all-locks fix from assertion 6 under the case it exists for:
#     a session with pending edit debt in more than one worktree at once.
# ---------------------------------------------------------------------------
wt14a=$(make_worktree "wt14a")
wt14b=$(make_worktree "wt14b")
session_cwd14=$(make_worktree "wt14-session")
seed_lock "$wt14a" 5 >/dev/null
seed_lock "$wt14b" 7 >/dev/null
lock14a=$(lock_path_for "$wt14a")
lock14b=$(lock_path_for "$wt14b")
events14="$TESTDIR/events14.jsonl"
agent_payload "$session_cwd14" "general-purpose" | DISPATCH_GATE_EVENTS_LOG="$events14" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null
reset14a=$(events_count "$events14" "reset" "$wt14a")
reset14b=$(events_count "$events14" "reset" "$wt14b")
if [ ! -f "$lock14a" ] && [ ! -f "$lock14b" ] && [ "$reset14a" = "1" ] && [ "$reset14b" = "1" ]; then
  pass "14: one real Agent dispatch -> clears locks in TWO distinct worktrees, 1 reset event each"
else
  fail "14: one real Agent dispatch -> clears locks in TWO distinct worktrees, 1 reset event each" \
    "both locks absent, 1 reset event each" \
    "lockA_exists=$([ -f "$lock14a" ] && echo yes || echo no), lockB_exists=$([ -f "$lock14b" ] && echo yes || echo no), resetA=$reset14a, resetB=$reset14b"
fi

# ---------------------------------------------------------------------------
# 15. Worktree-suffixed repo-name path (e.g. .../claude-config-dispatch-gate/
#     hooks/foo.sh, matching the real Git Workflow worktree-naming
#     convention `<repo>-<short-description>`) -> allowlisted, never counted.
#     Found live: a literal `*/claude-config/*` pattern never matches a
#     worktree of claude-config, so every edit to this project's OWN
#     worktree was wrongly counted for the whole implementation session.
#     Paired contrastive control: an unrelated worktree with a plain name
#     (no repo-name prefix) DOES increment, proving this isn't STUB-VACUOUS.
# ---------------------------------------------------------------------------
wt15_suffixed=$(make_worktree "claude-config-faketest")
wt15_plain=$(make_worktree "wt15plain")
lock15_suffixed=$(lock_path_for "$wt15_suffixed")
lock15_plain=$(lock_path_for "$wt15_plain")
events15="$TESTDIR/events15.jsonl"
for i in 1 2 3 4 5; do
  write_payload "$wt15_suffixed" "$wt15_suffixed/hooks/foo${i}.sh" | DISPATCH_GATE_EVENTS_LOG="$events15" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null
done
cum15_suffixed=$(lock_cumulative "$lock15_suffixed")
write_payload "$wt15_plain" "$wt15_plain/src/foo.ts" | DISPATCH_GATE_EVENTS_LOG="$events15" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$POST" >/dev/null
cum15_plain=$(lock_cumulative "$lock15_plain")
if [ "$cum15_suffixed" = "MISSING" ] && [ "$cum15_plain" = "1" ]; then
  pass "15: worktree-suffixed claude-config-* path -> never counted (no lock); plain worktree control increments to 1"
else
  fail "15: worktree-suffixed claude-config-* path -> never counted (no lock); plain worktree control increments to 1" \
    "suffixed=MISSING (no lock), plain=1" "suffixed=$cum15_suffixed, plain=$cum15_plain"
fi


# ---------------------------------------------------------------------------
# 16. Registration-phase regression guard (#1109). dispatch-gate-reset.sh's
#     own clearing logic has always been correct (assertions 6-8, 14 above
#     exercise it directly, calling the script in isolation) — the
#     production bug was that settings.json registered it on PostToolUse
#     for the Agent matcher. PostToolUse fires only after the WHOLE
#     subagent run completes, so a subagent dispatched while the gate was
#     armed spent its entire run blocked: the credit meant to unblock it
#     never lands until the dispatch has already returned. Evidence
#     (issue #1109): 6 consecutive `trigger` events with zero resets across
#     a real ~30-minute dispatch; the subagent used the `rm` escape hatch
#     4 times because it had no other way to clear a lock the gate itself
#     told it to clear by dispatching — which it already was.
#
#     None of assertions 1-15 can catch this class of bug: they invoke
#     $RESET / $PRE directly, bypassing settings.json entirely, so they
#     verify the scripts' internal logic but not which phase actually
#     fires them. This assertion closes that gap by reading the REAL
#     registration out of this repo's settings.json (not a hardcoded
#     assumption) and simulating the real event ordering:
#       1. Seed an armed lock (cumulative=threshold=5) in a worktree.
#       2. Only if dispatch-gate-reset.sh is registered under PreToolUse
#          for the Agent matcher, run it now — mirroring the harness
#          firing PreToolUse hooks BEFORE the Agent tool (the subagent)
#          actually executes. If it is registered under PostToolUse (the
#          bug) or missing entirely, this step is skipped, because in
#          production neither would have run yet either.
#       3. Simulate the subagent's own first edit mid-dispatch by invoking
#          dispatch-gate-pre.sh against the SAME worktree's lock.
#     Correctly wired (PreToolUse): the lock is already cleared by step 2,
#     so the subagent's edit is allowed. Wired to PostToolUse, or missing
#     (both are "not fired before dispatch" — the exact defect class this
#     guards, whether from a phase regression or the reset block being
#     dropped/renamed): the lock is still armed, so pre.sh denies the
#     subagent's own sanctioned edit — reproducing the issue's failure
#     mode exactly.
#
#     At the time this assertion was added, claude-config/settings.json
#     had NO Agent-matcher entry for dispatch-gate-reset.sh at all (it had
#     drifted out of sync with the live ~/.claude/settings.json that
#     actually produced the #1109 evidence — see commit body for the full
#     drift finding). reset_phase below reports "MISSING" for that RED
#     run, not "PostToolUse" — both are the same underlying defect
#     (reset not wired to fire before the dispatch), so this assertion is
#     written to fail identically either way.
# ---------------------------------------------------------------------------
reset_phase=$(jq -r '
  [ .hooks.PreToolUse[]?  | select(.matcher == "Agent") | .hooks[]? | select(.command | test("dispatch-gate-reset\\.sh")) ] as $pre
  | [ .hooks.PostToolUse[]? | select(.matcher == "Agent") | .hooks[]? | select(.command | test("dispatch-gate-reset\\.sh")) ] as $post
  | if ($pre | length) > 0 then "PreToolUse"
    elif ($post | length) > 0 then "PostToolUse"
    else "MISSING"
    end
' "$SETTINGS_JSON" 2>/dev/null)

wt16=$(make_worktree "wt16")
seed_lock "$wt16" 5 >/dev/null
events16="$TESTDIR/events16.jsonl"

if [ "$reset_phase" = "PreToolUse" ]; then
  agent_payload "$wt16" "general-purpose" | DISPATCH_GATE_EVENTS_LOG="$events16" DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$RESET" >/dev/null
fi

# The subagent's own first edit, simulated exactly as it would fire
# mid-dispatch: dispatch-gate-pre.sh checking the SAME worktree's lock.
out16=$(write_payload "$wt16" "$wt16/src/subagent-edit.ts" | DISPATCH_GATE_LOCK_DIR="$TEST_LOCK_DIR" "$PRE")
if [ -z "$out16" ]; then
  decision16="allow"
else
  decision16=$(echo "$out16" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  decision16="${decision16:-allow}"
fi

if [ "$decision16" = "allow" ]; then
  pass "16: reset registered under '$reset_phase' -> subagent's own mid-dispatch edit is NOT blocked (#1109)"
else
  fail "16: reset registered under '$reset_phase' -> subagent's own mid-dispatch edit is NOT blocked (#1109)" \
    "allow (reset must run before the subagent's first edit)" \
    "$decision16 (reset_phase=$reset_phase)"
fi

echo
echo "=== Summary: $PASS_COUNT passed, $FAIL_COUNT failed ==="
[ "$FAIL_COUNT" -eq 0 ]
