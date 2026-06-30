#!/bin/bash
set -e

# PreToolUse hook: gate `gh pr merge` (and equivalent `gh api` PUT calls)
# behind explicit per-PR approval from USER.
#
# WHY THE GATE EXISTS
#   PR merges are destructive shared-state changes. Without a gate, Claude
#   could merge based on conversational ambiguity ("looks good" / "we are
#   good"). The original gate denied unconditionally, but that prevented
#   the post-merge automation chain (POST_MERGE_HOOK → /session-capture →
#   cleanup agent) from firing — USER had to merge externally and then
#   manually trigger cleanup. This version reopens that chain by allowing
#   merges with explicit, per-PR, single-use tokens.
#
# HOW TO APPROVE A MERGE
#   Type in the prompt (the `!` prefix bypasses Bash-tool hooks, so Claude
#   cannot fake an approval through this path):
#
#       ! mkdir -p ~/.claude/merge-approvals && touch ~/.claude/merge-approvals/<PR_NUMBER>
#
#   Then ask Claude to merge. Claude runs `gh pr merge <PR_NUMBER> ...`,
#   this hook checks the token, allows the merge, and DELETES the token.
#
# AUDIT TRAIL
#   ~/.claude/merge-approvals/audit.log records every consumption.
#
# COMMANDS GATED
#   gh pr merge ...                              (any flags / PR number)
#   gh api -X PUT .../pulls/<N>/merge            (REST PUT to merge endpoint)
#   gh api --method PUT .../pulls/<N>/merge
#
# COMMANDS ALLOWED
#   gh pr view, gh pr list, gh pr checks, gh pr create, gh pr comment, gh pr diff
#   gh pr merge --help / -h
#   gh api calls that aren't PUT-on-merge
#   non-`gh` commands entirely (skipped — see false-positive guard below)

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // ""')

deny() {
  jq -n --arg msg "$1" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $msg
    }
  }'
  exit 0
}

# False-positive guard: only scan commands that invoke gh as an actual command —
# at the start, OR after a shell separator (&& / ; / |). The previous `^\s*gh`
# anchor missed `cd <dir> && gh pr merge` (the command starts with `cd`), which
# silently bypassed this entire gate — 2026-06-24 incident: PR #954 merged with no
# token because of exactly this. A `git commit` whose body merely contains the
# phrase "gh pr merge" (after a quote/space, not a separator) is still skipped.
if ! echo "$command" | grep -qE '(^|[;&|])[[:space:]]*gh\b'; then
  exit 0
fi

# Allow `gh pr merge --help` / `-h` — pure documentation, no side effect.
if echo "$command" | grep -qE '\bgh +pr +merge\b.*(--help|-h)\b'; then
  exit 0
fi

# Detect a PR-merge command.
is_pr_merge=0
if echo "$command" | grep -qE '\bgh +pr +merge\b'; then
  is_pr_merge=1
fi
if echo "$command" | grep -qE '\bgh +api\b' \
  && echo "$command" | grep -qE '(-X +PUT|--method +PUT)' \
  && echo "$command" | grep -qE '/merge\b'; then
  is_pr_merge=1
fi

if [ "$is_pr_merge" -ne 1 ]; then
  exit 0
fi

# Extract the PR number.
#   `gh pr merge 741 ...`        → 741
#   `gh pr merge --squash 741`   → 741
#   `gh pr merge` (no number)    → empty (current branch — refuse, can't verify)
#   `gh api .../pulls/741/merge` → 741
pr_number=$(echo "$command" | grep -oE 'gh +pr +merge[^0-9]*([0-9]+)' | grep -oE '[0-9]+$')
if [ -z "$pr_number" ]; then
  pr_number=$(echo "$command" | sed -nE 's|.*/pulls/([0-9]+)/merge.*|\1|p')
fi

if [ -z "$pr_number" ]; then
  deny "BLOCKED: gh pr merge requires an explicit PR number for approval verification. Use 'gh pr merge <N> --squash --delete-branch'. To approve, USER should type in the prompt: ! mkdir -p ~/.claude/merge-approvals && touch ~/.claude/merge-approvals/<N>"
fi

# Check for the approval token.
approval_dir="$HOME/.claude/merge-approvals"
token="$approval_dir/$pr_number"

if [ ! -f "$token" ]; then
  deny "BLOCKED: PR #$pr_number is not approved for merge. To approve, USER must type in the prompt (the ! prefix bypasses Bash-tool hooks so Claude cannot self-approve): ! mkdir -p ~/.claude/merge-approvals && touch ~/.claude/merge-approvals/$pr_number — then ask Claude to merge. Approval is single-use; the hook deletes the token after consuming."
fi

# Token exists. Consume it (single-use), audit, allow.
mkdir -p "$approval_dir"
audit_log="$approval_dir/audit.log"
cmd_excerpt=$(echo "$command" | head -c 200 | tr '\n' ' ')
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) PR #$pr_number approved + consumed (cmd: $cmd_excerpt)" >> "$audit_log"
rm -f "$token"

exit 0
