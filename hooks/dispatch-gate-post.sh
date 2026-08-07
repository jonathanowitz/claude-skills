#!/bin/bash
# PostToolUse hook — Mechanical Dispatch Gate tracker.
#
# Fires after Write or Edit. Tracks cumulative non-allowlisted edit activity
# in the current worktree. When the cumulative count first reaches the
# threshold (default 5), logs one JSONL trigger event and prints a
# DISPATCH_GATE_ACTIVE notice. dispatch-gate-pre.sh enforces the deny;
# dispatch-gate-reset.sh clears the lock on a real Agent dispatch; a manual
# `rm` is the escape hatch.
#
# Spec: dev-reference/briefs/mechanical-dispatch-gate.md
#
# Evidence for existence: 7-day transcript analysis found 38 runs of 5+
# consecutive direct Edit/Write with no intervening Agent dispatch, totaling
# $1,490.22 ($1,222.95 genuine hands-on execution that should have been
# delegated). The documented two-stage dispatch protocol
# (claude-config/rules/hooks-and-agents.md) is advisory-only and wasn't
# being followed (79 Agent dispatches vs. thousands of direct edits).
#
# Deliberately does NOT use `set -e` (unlike test-review-gate-{pre,post}.sh):
# `set -e` aborts a script on a failing command substitution even with
# stderr redirected (e.g. `x=$(echo bad | jq ... 2>/dev/null)` still trips
# it on malformed JSON), which would violate the fail-open requirement this
# hook is explicitly tested against (B10). Every jq extraction below is
# guarded with `|| var=""` instead so parse failures degrade to a safe
# default rather than aborting.
#
# DISPATCH_GATE_LOCK_DIR overrides the lock directory (default /tmp), same
# testability interface as DISPATCH_GATE_EVENTS_LOG — see dispatch-gate-
# reset.sh's header for why this matters (it globs every lock in this
# directory on a real dispatch).

THRESHOLD=5
EVENTS_LOG="${DISPATCH_GATE_EVENTS_LOG:-$HOME/.claude/dispatch-gate-events.jsonl}"
LOCK_DIR="${DISPATCH_GATE_LOCK_DIR:-/tmp}"

hook_input=$(cat)
tool_name=$(echo "$hook_input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""
cwd=$(echo "$hook_input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
agent_id=$(echo "$hook_input" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""

# #1116 Defect 2, counting half. A subagent's edits ARE the delegation, so they
# must not accrue edit debt against the orchestrator's lock.
#
# Without this the defect just moves one step later. dispatch-gate-reset.sh
# clears the lock when the Agent call is dispatched, then the subagent's own
# edits rebuild it — a 20-file subagent hands the orchestrator a lock at
# cumulative=20 the instant it returns. The orchestrator is then denied
# immediately after a legitimate delegation, which reset.sh's own header calls
# out as "the failure mode that erodes trust in the gate."
#
# Same signal and same verification as the pre-hook guard; see that script's
# comment for why agent_id and not CLAUDE_CODE_CHILD_SESSION.
[ -n "$agent_id" ] && exit 0

case "$tool_name" in
  Write|Edit) ;;
  *) exit 0 ;;
esac
[ -n "$file_path" ] || exit 0

# Allowlist — never counted, never blocked. Duplicated verbatim in
# dispatch-gate-pre.sh by design: matches test-review-gate-{pre,post}.sh's
# existing convention of not sharing this logic across the two hooks (see
# brief's Pre-Feature Refactor section for the explicit justification).
#
# Repo-name patterns (example-context, dev-reference, claude-config,
# claude-skills) use a trailing `*` after the repo name, not a literal `/`,
# because the Git Workflow worktree-naming convention is
# `<repo>-<short-description>` (e.g. `claude-config-dispatch-gate`) — a
# literal `*/claude-config/*` never matches any worktree of that repo. Found
# live: every edit to this project's own worktree (infrastructure for
# claude-config itself) was wrongly counted against the threshold for the
# whole implementation session, confirmed via a 7-day transcript replay that
# also caught the same gap for dev-reference and claude-skills worktrees.
case "$file_path" in
  */tests/*|*/e2e/*) exit 0 ;;
  *.test.*|*.spec.*) exit 0 ;;
  */tmp/*) exit 0 ;;
  */example-context*/*) exit 0 ;;
  */.claude/*|/Users/*/.claude/*) exit 0 ;;
  */memory/*) exit 0 ;;
  */dev-reference*/*) exit 0 ;;
  */claude-config*/*|*/claude-skills*/*) exit 0 ;;
  */docs/briefs/*.md|*/docs/briefs/*.txt) exit 0 ;;
  */next-steps.md|*/ROADMAP.md|*/CLAUDE.md|*/.gitignore) exit 0 ;;
esac

# Resolve to actual worktree root so parallel sessions keyed to the same
# session cwd (main checkout) don't share a lock across different worktrees.
worktree=$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null) || worktree=""
[ -n "$worktree" ] || worktree="$cwd"
[ -n "$worktree" ] || exit 0

worktree_hash=$(echo -n "$worktree" | shasum -a 256 2>/dev/null | cut -c1-8) || exit 0
[ -n "$worktree_hash" ] || exit 0

LOCK="$LOCK_DIR/dispatch-gate-pending-${worktree_hash}.lock"
LOCKDIR="${LOCK}.lockdir"
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Portable mutex: mkdir is atomic on POSIX filesystems, unlike `flock`, which
# doesn't exist on macOS (util-linux only, not available on Darwin — the
# brief originally specified flock; corrected during implementation once
# that gap surfaced empirically). Spin with a bounded retry so a crashed
# holder can't wedge the gate forever.
waited=0
while ! mkdir "$LOCKDIR" 2>/dev/null; do
  waited=$((waited + 1))
  [ "$waited" -gt 250 ] && { rmdir "$LOCKDIR" 2>/dev/null; break; }
  sleep 0.02
done
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT

  prev_cumulative=0
  first_seen="$ts"
  tmp_lines=$(mktemp) || exit 0

  if [ -f "$LOCK" ]; then
    prev_cumulative=$(grep -E '^# cumulative_edits=' "$LOCK" 2>/dev/null | head -1 | sed -E 's/.*=//')
    case "$prev_cumulative" in ''|*[!0-9]*) prev_cumulative=0 ;; esac
    prev_first_seen=$(grep -E '^# first_seen=' "$LOCK" 2>/dev/null | head -1 | sed -E 's/.*=//')
    [ -n "$prev_first_seen" ] && first_seen="$prev_first_seen"
    grep -v '^#' "$LOCK" 2>/dev/null > "$tmp_lines"
  else
    : > "$tmp_lines"
  fi

  printf '%s\t%s\t%s\n' "$file_path" "$tool_name" "$ts" >> "$tmp_lines"
  cumulative=$(grep -vc '^$' "$tmp_lines" 2>/dev/null)
  case "$cumulative" in ''|*[!0-9]*) cumulative=0 ;; esac

  {
    printf '# DISPATCH_GATE lock\n'
    printf '# cumulative_edits=%s\n' "$cumulative"
    printf '# threshold=%s\n' "$THRESHOLD"
    printf '# worktree=%s\n' "$worktree"
    printf '# first_seen=%s\n' "$first_seen"
    cat "$tmp_lines"
  } > "$LOCK" 2>/dev/null
  rm -f "$tmp_lines"

  if [ "$prev_cumulative" -lt "$THRESHOLD" ] && [ "$cumulative" -ge "$THRESHOLD" ]; then
    files_json=$(grep -v '^#' "$LOCK" 2>/dev/null | awk -F'\t' '{print $1}' | jq -R . 2>/dev/null | jq -s . 2>/dev/null)
    [ -n "$files_json" ] || files_json="[]"
    # `-c`: same log file as the reset/dispatch events — jq pretty-prints by
    # default, which puts multi-line records in a .jsonl and lets concurrent
    # appends interleave mid-record.
    event=$(jq -n -c --arg ts "$ts" --arg wt "$worktree" --argjson cum "$cumulative" --argjson files "$files_json" \
      '{timestamp: $ts, event: "trigger", worktree: $wt, cumulative: $cum, files: $files}' 2>/dev/null)
    if [ -n "$event" ]; then
      mkdir -p "$(dirname "$EVENTS_LOG")" 2>/dev/null
      echo "$event" >> "$EVENTS_LOG" 2>/dev/null
    fi
    file_count=$(grep -vc '^#' "$LOCK" 2>/dev/null)
    echo "DISPATCH_GATE_ACTIVE: $cumulative edit(s) across $file_count file(s) in this worktree with no intervening Agent dispatch. Lock: $LOCK"
  fi

exit 0
