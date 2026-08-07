#!/bin/bash
# PreToolUse hook — Mechanical Dispatch Gate auto-clear.
#
# Fires before every Agent tool call executes (i.e. before the dispatched
# subagent's run, not after it returns — see #1109: registered on
# PostToolUse originally, which fires only once the whole subagent run has
# already completed, so the credit this hook grants could never reach the
# subagent it was meant to unblock; moved here with no logic change, since
# the credit is for the *act of dispatching*, which is fully known at call
# time from tool_input.subagent_type). When the subagent_type is a real
# delegation (not Explore/Plan, which are research, not dispatch), clears
# EVERY active dispatch-gate lock on disk and logs one JSONL reset event per
# lock cleared. Unlike every other gate in this codebase, this hook clears
# the lock automatically in response to a *different* tool call happening —
# there's no equivalent skill-verdict PASS to key off of (see brief's
# Reuse & Adaptation row 2).
#
# Safe as a PreToolUse hook: every exit path here is a bare `exit 0` and
# the script never writes anything to stdout (its only output is the JSONL
# append to $EVENTS_LOG, a file write, not a hookSpecificOutput/deny
# payload) — so there is no code path that could be interpreted as a
# PreToolUse deny under the hook contract dispatch-gate-pre.sh uses.
#
# Deliberately NOT keyed to the Agent call's own worktree. Originally this
# resolved a single worktree from the hook payload's `cwd` field (mirroring
# dispatch-gate-post.sh's file_path-based resolution) and cleared only that
# worktree's lock. Empirically wrong: the orchestrator's global convention
# is to never `cd` into a worktree — Write/Edit calls carry a file_path that
# resolves to the real worktree, but the Agent tool has no file_path, only
# the session's fixed launch-directory cwd. In two live dispatches during
# implementation testing, a lock seeded for the session's own cwd cleared
# correctly, but a lock seeded for a *different* worktree (the realistic
# case — edits happen in a worktree, the Agent call does not) was never
# touched. That's the primary flow this hook exists to serve, so the
# cwd-keyed version would have silently never worked in production.
#
# Clearing every active lock on any real dispatch over-credits in the rare
# case where a session has unrelated pending edit debt in a second worktree
# it hasn't dispatched for yet — but that debt just re-triggers on its next
# 5 edits (cumulative resets to 0, same threshold applies). Under-crediting
# (the cwd-keyed bug) instead produces a false DENY right after a legitimate
# dispatch, which is the failure mode that erodes trust in the gate. This
# hook is a behavioral nudge, not a security boundary, so over-crediting is
# the safer direction to err in.
#
# Must never deny anything — it only observes and clears. If no locks
# exist, that's a silent no-op (the common case), not an error.
#
# Spec: dev-reference/briefs/mechanical-dispatch-gate.md
#
# No `set -e` — see dispatch-gate-post.sh header for why. Every jq
# extraction is guarded with `|| var=""` so malformed input degrades to a
# safe default (fail-open, B10) instead of aborting.
#
# DISPATCH_GATE_LOCK_DIR overrides the lock directory (default /tmp), same
# testability interface as DISPATCH_GATE_EVENTS_LOG. Mandatory for tests to
# set: this script globs EVERY lock file in this directory below, so
# invoking it directly against the real /tmp during a test run clears
# whatever real, unrelated locks happen to exist there too (found live
# during implementation testing — a genuine production lock vanished this
# way when the test harness ran without this override).

EVENTS_LOG="${DISPATCH_GATE_EVENTS_LOG:-$HOME/.claude/dispatch-gate-events.jsonl}"
LOCK_DIR="${DISPATCH_GATE_LOCK_DIR:-/tmp}"

hook_input=$(cat)
tool_name=$(echo "$hook_input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
subagent_type=$(echo "$hook_input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || subagent_type=""

[ "$tool_name" = "Agent" ] || exit 0

# --- dispatch-quality scoring (#1186) -------------------------------------
# LENIENT MODE: score every dispatch, log the flags, never block. The gate
# still clears exactly as before. The point is to accumulate evidence so the
# blocking threshold can be set from real numbers instead of a guess — there
# are already 158 baseline resets, and #1116 documents an agent reflexively
# `rm`-ing a lock, so shipping a strict bar first risks training bypass on a
# hook whose whole value is that it is not bypassable.
#
# Why THESE flags: mining 2,966 historical dispatches showed agent failure is
# semantic and invisible to transcript mining (err 1.3%, empty 0.9% — agents
# essentially never hard-fail). The 154 human-labeled telemetry events show
# the dominant failure mode is a brief carrying a false or incomplete
# premise, and that the single highest-yield mitigation already proven in the
# log is an explicit escalation clause ("report contradictions, do not work
# around them") — agents given it caught the orchestrator's own errors at
# least four separate times.
#
# NOT scored: "carries product facts, not just tech spec." It is the second
# most load-bearing criterion and it is NOT reliably detectable by regex.
# Faking a mechanical proxy for it would produce a confident wrong number,
# which is worse than a missing one. Left to human review, deliberately.
model=$(echo "$hook_input" | jq -r '.tool_input.model // empty' 2>/dev/null) || model=""
prompt=$(echo "$hook_input" | jq -r '.tool_input.prompt // empty' 2>/dev/null) || prompt=""
prompt_len=${#prompt}

# Recorded, NOT acted on. A subagent that itself dispatches an Agent still
# clears the orchestrator's lock, which is the documented-safe direction (see
# the over-crediting rationale in this file's header: over-crediting self-heals
# in five edits, under-crediting produces a false deny right after a legitimate
# delegation). But a nested dispatch's quality event is otherwise
# indistinguishable from an orchestrator's, and unlike the lock that pollution
# never self-heals — it permanently biases the very dataset the blocking
# threshold is meant to be set from. Empty on the main thread.
agent_id=$(echo "$hook_input" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""

has_escalation=false
if printf '%s' "$prompt" | grep -qiE \
  'do not (work around|fix|edit|modify) (it|them|the test)|report (the )?(contradiction|discrepanc|mismatch)|escalat|stop and (report|ask|surface)|tests? (are|is) the spec|flag .{0,30}(rather than|instead of)|surface .{0,30}(contradiction|conflict|discrepanc)|report,? do not'; then
  has_escalation=true
fi

has_freshness=false
if printf '%s' "$prompt" | grep -qiE 'origin/main|git fetch|against origin|grep-verif|verify .{0,40}(against|before)'; then
  has_freshness=true
fi

model_pinned=false
[ -n "$model" ] && model_pinned=true

named_type=false
case "$subagent_type" in
  ''|general-purpose) named_type=false ;;
  *) named_type=true ;;
esac

# A dispatch is "weak" on the criterion that actually predicts failure:
# no escalation clause. Logged, not enforced.
weak=false
[ "$has_escalation" = false ] && weak=true

# Read-only research subagents aren't delegation — don't clear on these.
case "$subagent_type" in
  Explore|Plan) exit 0 ;;
esac

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Emit one quality event for EVERY dispatch, whether or not a lock is cleared.
# Deliberate: 81% of historical resets happened at cumulative<5, i.e. the
# dispatch beat the gate — and dispatches with no lock at all currently
# produce no record whatsoever. Logging only lock-clearing dispatches would
# sample the minority and bias the threshold this data exists to set.
# `-c`: jq pretty-prints by default, which puts multi-line records in a .jsonl
# and lets concurrent appends interleave mid-record. The live log carried
# multi-line events from 2026-07-11 until this was fixed.
qevent=$(jq -n -c --arg ts "$ts" --arg st "$subagent_type" --arg m "$model" \
  --arg aid "$agent_id" \
  --argjson plen "$prompt_len" --argjson esc "$has_escalation" \
  --argjson fresh "$has_freshness" --argjson pin "$model_pinned" \
  --argjson named "$named_type" --argjson weak "$weak" \
  '{timestamp: $ts, event: "dispatch", subagent_type: $st, model: $m,
    dispatched_by_agent_id: $aid,
    prompt_len: $plen, has_escalation: $esc, has_freshness: $fresh,
    model_pinned: $pin, named_type: $named, weak_dispatch: $weak}' 2>/dev/null)
if [ -n "$qevent" ]; then
  mkdir -p "$(dirname "$EVENTS_LOG")" 2>/dev/null
  echo "$qevent" >> "$EVENTS_LOG" 2>/dev/null
fi

shopt -s nullglob
locks=("$LOCK_DIR"/dispatch-gate-pending-*.lock)
shopt -u nullglob

# Defensive: no locks means nothing to clear. Cheap, unremarkable, no reset event.
[ "${#locks[@]}" -gt 0 ] || exit 0

for LOCK in "${locks[@]}"; do
  LOCKDIR="${LOCK}.lockdir"

  # Portable mutex: mkdir is atomic on POSIX filesystems, unlike `flock`,
  # which doesn't exist on macOS. Same primitive as dispatch-gate-post.sh,
  # taken before checking-then-deleting the lock to avoid a race against a
  # concurrent post.sh increment.
  #
  # Re-registered each iteration (single-quoted, so $LOCKDIR is read at
  # fire time, not registration time) so a SIGINT/crash mid-iteration still
  # releases whichever mutex is currently held — post.sh has this via its
  # own trap; found missing here via cross-model review (Gemini). Without
  # it an orphaned .lockdir is still self-healing (the next acquirer's
  # 250-iteration/~5s spin breaks a stale one), just a needless stall, not
  # a permanent hang.
  trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT
  waited=0
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    waited=$((waited + 1))
    [ "$waited" -gt 250 ] && { rmdir "$LOCKDIR" 2>/dev/null; break; }
    sleep 0.02
  done

  # Re-check inside the lock — a concurrent dispatch-gate-post.sh could have
  # been mid-write, or another reset could have already cleared it.
  if [ ! -f "$LOCK" ]; then
    rmdir "$LOCKDIR" 2>/dev/null
    continue
  fi

  worktree=$(grep -E '^# worktree=' "$LOCK" 2>/dev/null | head -1 | sed -E 's/^# worktree=//')
  cumulative=$(grep -E '^# cumulative_edits=' "$LOCK" 2>/dev/null | head -1 | sed -E 's/.*=//')
  case "$cumulative" in ''|*[!0-9]*) cumulative=0 ;; esac

  rm -f "$LOCK"
  rmdir "$LOCKDIR" 2>/dev/null

  event=$(jq -n -c --arg ts "$ts" --arg wt "$worktree" --argjson cum "$cumulative" --arg st "$subagent_type" \
    --arg aid "$agent_id" \
    --argjson esc "$has_escalation" --argjson weak "$weak" \
    '{timestamp: $ts, event: "reset", worktree: $wt, cumulative_at_reset: $cum, subagent_type: $st,
      dispatched_by_agent_id: $aid, has_escalation: $esc, weak_dispatch: $weak}' 2>/dev/null)
  if [ -n "$event" ]; then
    mkdir -p "$(dirname "$EVENTS_LOG")" 2>/dev/null
    echo "$event" >> "$EVENTS_LOG" 2>/dev/null
  fi
done

exit 0
