#!/bin/bash
# Standalone, non-LLM metrics report for the Mechanical Dispatch Gate.
# Run manually or via a periodic (non-LLM) cron entry — never inside a
# Claude session (that would defeat the zero-LLM-cost tracking constraint
# the whole telemetry design exists to satisfy).
#
# Usage: dispatch-gate-report.sh [log_path]
#   Log path resolution: $1 (optional arg) > $DISPATCH_GATE_EVENTS_LOG env >
#   default ~/.claude/dispatch-gate-events.jsonl
#
# Prints: trigger count, reset count, escape-hatch-inferred count (see
# inference logic below), and the underlying dispatch rate (Agent calls ÷
# Edit+Write calls across recent session transcripts).
#
# Spec: dev-reference/briefs/mechanical-dispatch-gate.md
#
# Escape-hatch inference: a manual `rm <lock>` is never itself logged (it
# happens outside the tool-call lifecycle). Inferred as a gap: for two
# consecutive `trigger` events on the same worktree, if no `reset` event for
# that worktree falls between them, the first trigger's lock must have been
# cleared some other way (i.e. manually) before the second trigger could
# accumulate from zero.

LOG="${1:-${DISPATCH_GATE_EVENTS_LOG:-$HOME/.claude/dispatch-gate-events.jsonl}}"

if [ ! -f "$LOG" ]; then
  echo "Dispatch Gate Report"
  echo "Log: $LOG (not found)"
  echo "Triggers: 0"
  echo "Resets: 0"
  echo "Escape-hatch-inferred: 0"
  echo "Dispatch rate: N/A (no telemetry yet)"
  exit 0
fi

triggers=$(jq -s '[.[] | select(.event == "trigger")] | length' "$LOG" 2>/dev/null)
resets=$(jq -s '[.[] | select(.event == "reset")] | length' "$LOG" 2>/dev/null)
case "$triggers" in ''|*[!0-9]*) triggers=0 ;; esac
case "$resets" in ''|*[!0-9]*) resets=0 ;; esac

escape_hatch=$(jq -s '
  group_by(.worktree) |
  map(
    (map(select(.event == "trigger")) | sort_by(.timestamp)) as $triggers |
    (map(select(.event == "reset")) | sort_by(.timestamp)) as $resets |
    ([range(0; (($triggers | length) - 1))] |
      map(
        ($triggers[.].timestamp) as $t1 |
        ($triggers[.+1].timestamp) as $t2 |
        if ([$resets[] | select(.timestamp > $t1 and .timestamp < $t2)] | length) > 0
        then 0 else 1 end
      ) | add) // 0
  ) | add // 0
' "$LOG" 2>/dev/null)
case "$escape_hatch" in ''|*[!0-9]*) escape_hatch=0 ;; esac

# Best-effort dispatch rate over the last 7 days of session transcripts —
# same computation this investigation already did by hand from transcript
# JSONL. Degrades to N/A rather than failing the report if transcripts are
# unreadable or jq/find are unavailable in a cron context.
dispatch_rate="N/A"
projects_dir="$HOME/.claude/projects"
if [ -d "$projects_dir" ]; then
  counts=$(find "$projects_dir" -name '*.jsonl' -mtime -7 -print0 2>/dev/null \
    | xargs -0 jq -sr '
        [.[] | .message.content[]? | select(.type == "tool_use")] as $tools
        | ([$tools[] | select(.name == "Agent")] | length) as $agent
        | ([$tools[] | select(.name == "Write" or .name == "Edit")] | length) as $editwrite
        | "\($agent) \($editwrite)"
      ' 2>/dev/null)
  if [ -n "$counts" ]; then
    agent_total=0
    editwrite_total=0
    while read -r a e; do
      case "$a" in ''|*[!0-9]*) a=0 ;; esac
      case "$e" in ''|*[!0-9]*) e=0 ;; esac
      agent_total=$((agent_total + a))
      editwrite_total=$((editwrite_total + e))
    done <<< "$counts"
    if [ "$editwrite_total" -gt 0 ]; then
      dispatch_rate=$(awk -v a="$agent_total" -v e="$editwrite_total" 'BEGIN { printf "%.1f%% (%d Agent / %d Edit+Write, last 7 days)", (a/e)*100, a, e }')
    fi
  fi
fi

echo "Dispatch Gate Report"
echo "Log: $LOG"
echo "Triggers: $triggers"
echo "Resets: $resets"
echo "Escape-hatch-inferred: $escape_hatch"
echo "Dispatch rate: $dispatch_rate"
