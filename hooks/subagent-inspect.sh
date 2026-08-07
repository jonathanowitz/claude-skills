#!/bin/bash
# SubagentStop hook — inspect what a subagent actually did before its result lands.
#
# Closes the missing half of the delegation loop (#1186 scope item 2). The
# dispatch gate pushes work OUT to a subagent; until now nothing looked at what
# came back. There was zero coverage on this event.
#
# WHY THIS EVENT IS THE ONE THAT MATTERS: the 2,966-dispatch mining run could
# not build a `rework` detector at all — only 4 sidechain Edit/Write calls exist
# across 65,330 sampled parent-transcript records, because subagent work is
# written to a SEPARATE transcript file. SubagentStop is the first payload that
# carries `agent_transcript_path`, i.e. the parent->subagent linkage. This hook
# exists to start capturing exactly the data that was previously impossible to
# collect.
#
# LENIENT, exactly like dispatch-gate-reset.sh's scoring: observe and log, never
# block, never alter the subagent's result. The blocking threshold gets set from
# real numbers later, not guessed now. Same reasoning as #1116 — shipping a
# strict bar before the evidence exists trains bypass on the hook.
#
# DELIBERATELY DOES NOT EMIT hookSpecificOutput.additionalContext. Per the
# 2.1.217 binary, that field on SubagentStop is "non-error feedback delivered to
# the subagent; the subagent continues so it can act on it" — i.e. it RESTARTS
# the subagent. That is the documented Stop-hook continuation footgun
# (anthropics/claude-code#55754, #58348): a hook that blocks on an unsatisfiable
# condition loops until it eats the whole session budget. A log-only hook cannot
# loop. `stop_hook_active` is checked anyway, per the binary's own guidance
# ("For Stop/SubagentStop hooks, check stop_hook_active in the input and return
# success while it's true"), so the guard is already in place if this ever does
# grow a blocking mode.
#
# No `set -e` — same fail-open requirement as the dispatch-gate scripts; every
# extraction is guarded so malformed input degrades to a safe default.
#
# SUBAGENT_INSPECT_LOG overrides the output log (testability interface, matching
# DISPATCH_GATE_EVENTS_LOG).

LOG="${SUBAGENT_INSPECT_LOG:-$HOME/.claude/subagent-stop-events.jsonl}"

hook_input=$(cat)
event=$(echo "$hook_input" | jq -r '.hook_event_name // empty' 2>/dev/null) || event=""
[ "$event" = "SubagentStop" ] || exit 0

# Continuation-loop guard. Nothing below blocks, so this is belt-and-braces for
# a future blocking mode — but it also short-circuits redundant logging when a
# turn is already being re-driven by another Stop hook.
stop_active=$(echo "$hook_input" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_active="false"
[ "$stop_active" = "true" ] && exit 0

agent_id=$(echo "$hook_input" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""
agent_type=$(echo "$hook_input" | jq -r '.agent_type // empty' 2>/dev/null) || agent_type=""
# NOT `.transcript_path` — that base field is the PARENT session's transcript.
# The subagent's own transcript is `.agent_transcript_path`. Reading the wrong
# one yields a hook that inspects the orchestrator and silently finds nothing.
tpath=$(echo "$hook_input" | jq -r '.agent_transcript_path // empty' 2>/dev/null) || tpath=""
final=$(echo "$hook_input" | jq -r '.last_assistant_message // empty' 2>/dev/null) || final=""

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

tool_calls=0
files_json="[]"
ran_tests=false
gate_bypass=false
transcript_read=false

if [ -n "$tpath" ] && [ -r "$tpath" ] && [ -s "$tpath" ]; then
  transcript_read=true

  # STREAMING, never `jq -s`. Slurp mode is all-or-nothing: one unparseable line
  # fails the WHOLE file and every fact silently falls back to its zero value at
  # once. That is not a hypothetical here — SubagentStop can fire before the
  # final transcript record is flushed, so a truncated last line is a live race
  # and the common case, not the rare one. Verified: on a 2-line fixture whose
  # second line is truncated, `jq -s` errors out and yields nothing, while
  # streaming still recovers the intact record.
  tool_calls=$(jq -r 'select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use") | .name' "$tpath" 2>/dev/null | grep -c '' ) || tool_calls=0
  case "$tool_calls" in ''|*[!0-9]*) tool_calls=0 ;; esac

  files_json=$(jq -r 'select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use")
      | select(.name=="Write" or .name=="Edit" or .name=="NotebookEdit")
      | .input.file_path // empty' "$tpath" 2>/dev/null \
    | sort -u | jq -R . 2>/dev/null | jq -s -c . 2>/dev/null) || files_json="[]"
  [ -n "$files_json" ] || files_json="[]"

  # No `|| cmds=""` here, deliberately. jq exits non-zero when it hits the
  # truncated line, and that `||` would then DISCARD the commands it had already
  # streamed — reintroducing the exact all-or-nothing failure this stopped using
  # `jq -s` to avoid. Command substitution keeps the partial stdout on its own;
  # there is no `set -e`, so a non-zero exit here is harmless.
  cmds=$(jq -r 'select(.type=="assistant") | .message.content[]?
      | select(.type=="tool_use") | select(.name=="Bash")
      | .input.command // empty' "$tpath" 2>/dev/null)

  # Did it actually run a test suite? This is the evidence half of the
  # "claimed tests pass" check below. Every runner missed here manufactures a
  # false unverified_test_claim, so the shorthands (`npm t`, `make test`) are
  # included deliberately.
  if printf '%s' "$cmds" | grep -qE '(npm|pnpm|yarn)[[:space:]]+(run[[:space:]]+)?(test|t|e2e)\b|make[[:space:]]+test|vitest|playwright|jest|pytest|go[[:space:]]+test|cargo[[:space:]]+test|bats[[:space:]]'; then
    ran_tests=true
  fi

  # #1116's trained-bypass behavior, made visible. The Slice 2b agent `rm`-ed a
  # dispatch-gate lock twice. The pre-hook guard should make that unnecessary
  # now; this records whether it still happens, in the subagent's OWN
  # transcript, where the parent could never see it before.
  #
  # Anchored on a word boundary and covering rmdir. Without the leading
  # boundary, "confi[rm ]dispatch-gate-pending-foo.lock" matches — a command
  # merely DISCUSSING the lock scored as a bypass. Without `dir`, the lock's own
  # `.lockdir` mutex being removed is missed, which is how it would actually go.
  if printf '%s' "$cmds" | grep -qE '(^|[[:space:]])rm(dir)?[[:space:]].*(dispatch-gate-pending|review-tests-pending|test-review-gate)'; then
    gate_bypass=true
  fi
fi

# --- claim vs. evidence -----------------------------------------------------
# Mode 2 in the labeled telemetry ("agent claims relayed as fact") is frequent.
# It is currently caught by human review; this makes the cheapest slice of it
# mechanical. Only the greppable half is checked — an assertion that the tests
# pass, against whether a test runner was actually invoked. Deliberately NOT
# attempting to judge whether the work is *correct*; that is not greppable, and
# a fake proxy for it would produce a confident wrong number.
claims_tests_pass=false
if printf '%s' "$final" | grep -qiE 'tests? (all )?pass|all tests pass|tests? (are )?(passing|green)|suite (is )?green|[0-9]+ passed|0 failed|passed=[0-9]+ failed=0'; then
  claims_tests_pass=true
fi

# Both derived flags are suppressed when the transcript could not be read at
# all. Otherwise "no evidence collected" is indistinguishable from "no evidence
# found": an unreadable transcript plus a truthful "42 passed, 0 failed" scores
# unverified_test_claim=true for an agent that DID run the suite, and the record
# carries nothing to recover the difference in analysis. That is exactly the
# confident wrong number this file's header refuses to manufacture.
unverified_test_claim=false
if [ "$transcript_read" = true ] && [ "$claims_tests_pass" = true ] && [ "$ran_tests" = false ]; then
  unverified_test_claim=true
fi

# An agent that asserts it verified something while having called no tools at
# all cannot have verified anything.
claims_verified=false
if printf '%s' "$final" | grep -qiE '\bverified\b|\bconfirmed\b|i checked|double-checked'; then
  claims_verified=true
fi

no_tool_claim=false
if [ "$transcript_read" = true ] && [ "$claims_verified" = true ] && [ "$tool_calls" -eq 0 ]; then
  no_tool_claim=true
fi

file_count=$(printf '%s' "$files_json" | jq 'length' 2>/dev/null) || file_count=0
case "$file_count" in ''|*[!0-9]*) file_count=0 ;; esac

# `-c` is load-bearing, not style: jq pretty-prints by default, so without it a
# single record spans 15+ lines in a file named .jsonl. Two consequences —
# line-oriented consumers read garbage, and concurrent appends from parallel
# subagents finishing together (the normal case here) can interleave mid-record,
# since only single writes under PIPE_BUF are atomic. Measured before fixing:
# the live log held 106 lines for 6 records.
record=$(jq -n -c --arg ts "$ts" --arg aid "$agent_id" --arg at "$agent_type" \
  --argjson tc "$tool_calls" --argjson files "$files_json" --argjson fc "$file_count" \
  --argjson tr "$transcript_read" \
  --argjson rt "$ran_tests" --argjson ctp "$claims_tests_pass" \
  --argjson utc "$unverified_test_claim" --argjson ntc "$no_tool_claim" \
  --argjson gb "$gate_bypass" --argjson flen "${#final}" \
  '{timestamp: $ts, event: "subagent_stop", agent_id: $aid, agent_type: $at,
    tool_calls: $tc, files_touched: $files, file_count: $fc,
    transcript_read: $tr, ran_tests: $rt, claims_tests_pass: $ctp,
    unverified_test_claim: $utc, no_tool_claim: $ntc,
    gate_bypass: $gb, final_message_len: $flen}' 2>/dev/null)

if [ -n "$record" ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  echo "$record" >> "$LOG" 2>/dev/null
fi

exit 0
