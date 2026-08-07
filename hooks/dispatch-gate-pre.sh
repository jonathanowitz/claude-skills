#!/bin/bash
# PreToolUse hook — Mechanical Dispatch Gate enforcer.
#
# When /tmp/dispatch-gate-pending-<worktree_hash>.lock exists AND
# cumulative_edits in that lock is >= threshold, denies:
#   • Write/Edit on non-allowlisted files
#   • Bash commands matching a common file-mutation pattern (sed -i, shell
#     redirection, tee, python -c ... open(...,'w'), perl -i) — this closes
#     the obvious bypass (deny a Write, reach for `sed -i` instead). This is
#     best-effort pattern matching, not a sandbox — freeform shell can still
#     route around it (documented limitation, not a gap to silently ignore).
#
# Lock is created/incremented by dispatch-gate-post.sh and cleared by
# dispatch-gate-reset.sh on a real Agent dispatch. Manual override: rm the
# lock file.
#
# Spec: dev-reference/briefs/mechanical-dispatch-gate.md
#
# No `set -e` — see dispatch-gate-post.sh header for why. Every jq
# extraction is guarded with `|| var=""` so malformed input degrades to a
# safe default (fail-open, B10) instead of aborting.
#
# DISPATCH_GATE_LOCK_DIR overrides the lock directory (default /tmp), same
# testability interface as DISPATCH_GATE_EVENTS_LOG. Required for tests:
# dispatch-gate-reset.sh globs every lock file in this directory on a real
# dispatch (see its header), so running any of these scripts directly
# against the real /tmp during a test run clears whatever real locks
# happen to exist there too — a live-session check during implementation
# testing showed a real, unrelated production lock vanish this way.

LOCK_DIR="${DISPATCH_GATE_LOCK_DIR:-/tmp}"

hook_input=$(cat)
tool_name=$(echo "$hook_input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
cwd=$(echo "$hook_input" | jq -r '.cwd // empty' 2>/dev/null) || cwd=""
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""
agent_id=$(echo "$hook_input" | jq -r '.agent_id // empty' 2>/dev/null) || agent_id=""

# #1116 Defect 2 — never fire inside the subagent this gate asked for.
#
# The gate exists to push implementation out to a delegated subagent. Firing
# INSIDE that subagent is unsatisfiable by construction: re-dispatching from
# within the delegation is the very thing the gate wanted, already done. The
# Slice 2b implementation agent hit this and `rm`-ed the lock twice, correctly
# reasoning that it WAS the delegation — training reflexive bypass on a hook
# whose entire value is that it is not bypassable.
#
# `agent_id` is the platform's own purpose-built signal, not a proxy. Per the
# hook-input schema in the 2.1.217 binary: "Subagent identifier. Present only
# when the hook fires from within a subagent (e.g., a tool called by an
# AgentTool worker). Absent for the main thread, even in --agent sessions.
# Use this field (not agent_type) to distinguish subagent calls from
# main-thread calls."
#
# Verified empirically on 2026-07-22 rather than taken from the docstring — a
# probe on the live PreToolUse payload logged agent_id=null for two main-thread
# Bash calls and agent_id="a19ff7bde8fc17f9b" (agent_type "general-purpose")
# for a dispatched subagent's Bash call, all three under an identical
# session_id. session_id therefore cannot distinguish the two; agent_id can.
#
# Explicitly NOT used: CLAUDE_CODE_CHILD_SESSION. It is set to 1 in the MAIN
# session (confirmed in the same check), so it does not mean "subagent" and
# would have suppressed the gate everywhere, silently disabling it.
#
# This also removes any need for a SubagentStart-sets / SubagentStop-clears
# marker file, which was the originally planned fix: a marker carries lifecycle
# risk (a stalled agent that never emits SubagentStop leaks a marker and
# disables the gate indefinitely — background-agent stalls are a documented
# failure mode) and needs staleness handling, reference counting for parallel
# agents, and a cleanup path. The payload field has none of that.
[ -n "$agent_id" ] && exit 0

case "$tool_name" in
  Write|Edit)
    [ -n "$file_path" ] || exit 0
    worktree=$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null) || worktree=""
    [ -n "$worktree" ] || worktree="$cwd"
    ;;
  Bash)
    worktree=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || worktree=""
    [ -n "$worktree" ] || worktree="$cwd"
    ;;
  *)
    exit 0
    ;;
esac
[ -n "$worktree" ] || exit 0

worktree_hash=$(echo -n "$worktree" | shasum -a 256 2>/dev/null | cut -c1-8) || exit 0
[ -n "$worktree_hash" ] || exit 0
LOCK="$LOCK_DIR/dispatch-gate-pending-${worktree_hash}.lock"

[ -f "$LOCK" ] || exit 0

cumulative=$(grep -E '^# cumulative_edits=' "$LOCK" 2>/dev/null | head -1 | sed -E 's/.*=//')
threshold=$(grep -E '^# threshold=' "$LOCK" 2>/dev/null | head -1 | sed -E 's/.*=//')
case "$cumulative" in ''|*[!0-9]*) cumulative=0 ;; esac
case "$threshold" in ''|*[!0-9]*) threshold=5 ;; esac

# Gate only activates at/above threshold. Below threshold the lock is just
# telemetry — no blocking.
[ "$cumulative" -ge "$threshold" ] || exit 0

file_list=$(grep -v '^#' "$LOCK" 2>/dev/null | awk -F'\t' '{print $1}' | tr '\n' ' ')
deny_reason=$(printf 'DISPATCH_GATE active: %s direct edit(s) with no intervening Agent dispatch.\nFiles: %s\nLock: %s\n\nThe plan-then-dispatch protocol (claude-config/rules/hooks-and-agents.md) calls for delegating implementation to a Sonnet Agent instead of continuing to hand-edit. Dispatch an Agent to clear this gate, or:\nEscape hatch: rm %s (explicit skip, audit trail).' \
  "$cumulative" \
  "$file_list" \
  "$LOCK" \
  "$LOCK")

deny() {
  jq -n --arg reason "$deny_reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }' 2>/dev/null
  exit 0
}

case "$tool_name" in
  Write|Edit)
    case "$file_path" in
      # Allow-list — never blocked. Duplicated verbatim in
      # dispatch-gate-post.sh by design (see that script's header / the
      # brief's Pre-Feature Refactor section). Repo-name patterns use a
      # trailing `*` (not literal `/`) to match worktree-suffixed directory
      # names like `claude-config-dispatch-gate` — see dispatch-gate-post.sh's
      # allowlist comment for the live evidence this gap was found with.
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
      *)
        deny
        ;;
    esac
    ;;
  Bash)
    command=$(echo "$hook_input" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""
    [ -n "$command" ] || exit 0
    # Strip quoted substrings before checking the sed/perl/tee/redirect
    # patterns, so a `>` or `tee` appearing as plain text inside a quoted
    # argument doesn't false-positive (e.g. `gh pr create --body "... > ..."`,
    # `echo "sweet tee"`) — found via cross-model review (Gemini), confirmed
    # empirically: those two commands plus `gh issue comment --body "see the
    # tee pipe example"` all matched the un-stripped pattern before this fix.
    # The python -c ... open(...,'w') check runs against the UNSTRIPPED
    # command on purpose — that pattern's whole point is to look INSIDE the
    # quoted string (python -c takes its script as a quoted argument), so
    # stripping quotes first would delete the exact text it needs to see.
    # Best-effort either way (doesn't handle escaped quotes or nested command
    # substitution) — a real shell tokenizer is out of scope for a
    # PreToolUse regex gate; see header for the "not a sandbox" framing.
    stripped=$(echo "$command" | sed -E 's/"[^"]*"//g; s/'"'"'[^'"'"']*'"'"'//g' 2>/dev/null) || stripped="$command"
    if echo "$stripped" | grep -qE '(^|&&[[:space:]]*|;[[:space:]]*)(sed[[:space:]]+-i|perl[[:space:]]+-i|[^&|;]*>[[:space:]]*[^&]|[^&|;]*>>|.*\btee\b)'; then
      deny
    fi
    if echo "$command" | grep -qE '(^|&&[[:space:]]*|;[[:space:]]*)python[3]?[[:space:]]+-c.*open\(.*["'"'"']w'; then
      deny
    fi
    exit 0
    ;;
esac
