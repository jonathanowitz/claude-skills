#!/bin/bash
# PreToolUse hook for Bash — blocks `gh pr create` unless a fresh
# pr-gate sentinel exists at tmp/pr-gate.green whose first line matches
# the current HEAD SHA of the effective working directory.
#
# Companion to scripts/pr-gate.sh (mechanical pre-PR checklist runner).
#
# Clear the block by running `bash scripts/pr-gate.sh` from the repo.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only gate gh pr create — anchored at command start (or after `cd … &&` / `;`)
# to avoid matching the literal string inside quoted args (e.g. `gh issue create --body "…gh pr create…"`).
if ! echo "$COMMAND" | grep -qE '(^|&&[[:space:]]*|;[[:space:]]*)gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
  exit 0
fi

# Determine effective cwd (command may start with `cd /path && ...`)
EFFECTIVE_CWD="$CWD"
if echo "$COMMAND" | grep -qE '^cd\s+'; then
  PARSED_DIR=$(echo "$COMMAND" | sed -n 's/^cd \([^ &;]*\).*/\1/p' | sed 's/["\x27]//g')
  if [ -n "$PARSED_DIR" ]; then
    [[ "$PARSED_DIR" != /* ]] && PARSED_DIR="$CWD/$PARSED_DIR"
    [ -d "$PARSED_DIR" ] && EFFECTIVE_CWD="$PARSED_DIR"
  fi
fi

REPO_ROOT=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  exit 0  # not a git repo — let it through
fi

# Only gate repos that ship a pr-gate.sh script
if [ ! -f "$REPO_ROOT/scripts/pr-gate.sh" ]; then
  exit 0
fi

block() {
  local reason="$1"
  local msg
  printf -v msg '[STATE]: pr-gate not green — %s\n  Action: Run `bash scripts/pr-gate.sh` from the branch worktree and fix the failing checks\n  Reference: scripts/pr-gate.sh' "$reason"
  jq -n --arg msg "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $msg}}'
  exit 0
}

# Build the list of candidate roots to check for a fresh sentinel:
# the effective cwd's repo root + every linked worktree. A worktree's
# sentinel is valid if its first line matches THAT worktree's HEAD —
# this way, running `gh pr create` from the main repo cwd is OK as long
# as the actual branch worktree has a fresh sentinel of its own.
CANDIDATES=$(cd "$REPO_ROOT" && git worktree list --porcelain 2>/dev/null | awk '/^worktree / { print $2 }')
[ -z "$CANDIDATES" ] && CANDIDATES="$REPO_ROOT"

LAST_REASON="No sentinel at tmp/pr-gate.green in any worktree."
for root in $CANDIDATES; do
  sentinel="$root/tmp/pr-gate.green"
  [ -f "$sentinel" ] || continue
  sentinel_sha=$(head -n 1 "$sentinel" 2>/dev/null)
  root_head=$(cd "$root" && git rev-parse HEAD 2>/dev/null)
  if [ -n "$sentinel_sha" ] && [ "$sentinel_sha" = "$root_head" ]; then
    exit 0
  fi
  LAST_REASON="Sentinel in $root/tmp/pr-gate.green ($sentinel_sha) != that worktree's HEAD ($root_head) — stale after new commits."
done

block "$LAST_REASON"
