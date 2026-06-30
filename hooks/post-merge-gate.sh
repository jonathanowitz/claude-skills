#!/bin/bash
# PreToolUse hook for Bash. Two jobs:
#   1. Hard-block `git worktree remove` if a post-merge session capture is
#      still pending (lock file left by bash-post-hook.sh after `gh pr merge`).
#   2. Soft-nag: on ANY Bash command, if a post-merge lock exists, inject a
#      system reminder telling the agent to run /session-capture. This converts
#      the one-shot POST_MERGE_HOOK signal (which can get buried in tool output)
#      into a recurring mechanical reminder that fires until the lock is cleared.
#      (Evidence: S54, 2026-05-11 — 3 PR merges, 0 /session-capture triggers,
#      because the agent didn't recognize the one-shot signal in tool output.)
#
# To clear the lock: run /session-capture, then delete the lock file.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# ─── Soft-nag: detect any pending post-merge lock for this repo ───────────────
# Find the main repo root for the current cwd; check if its lock file exists.
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  REPO_ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$REPO_ROOT" ]; then
    NAG_LOCK="/tmp/post-merge-capture-pending-$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1).lock"
    if [ -f "$NAG_LOCK" ]; then
      NAG_INFO=$(cat "$NAG_LOCK" 2>/dev/null)
      NAG_PR_RAW=$(echo "$NAG_INFO" | grep -oE '#[0-9]+' | head -1)
      NAG_PR_NUM=$(echo "$NAG_PR_RAW" | tr -d '#')

      # Auto-clear stale lock: if a recent session file already references this
      # PR, the capture already happened (possibly via manual prompt after the
      # one-shot signal was missed). Clear the lock and skip the nag.
      AUTO_CLEARED=false
      if [ -n "$NAG_PR_NUM" ]; then
        SESSION_DIR="$HOME/.claude/sessions"
        if [ -d "$SESSION_DIR" ]; then
          RECENT=$(find "$SESSION_DIR" -name 'session-*.md' -mtime -7 2>/dev/null)
          # head -1 always exits 0 even on empty input, so check the captured output.
          MATCH=$(echo "$RECENT" | xargs grep -l "#${NAG_PR_NUM}" 2>/dev/null | head -1)
          if [ -n "$MATCH" ]; then
            rm -f "$NAG_LOCK"
            AUTO_CLEARED=true
          fi
        fi
      fi

      # Don't nag if THIS command is /session-capture, a worktree remove (handled
      # below), or if we just auto-cleared the lock.
      if [ "$AUTO_CLEARED" != "true" ] && ! echo "$COMMAND" | grep -qE 'git\s+worktree\s+remove|session-capture'; then
        # Emit non-blocking system reminder. Use additionalContext via JSON.
        cat <<NAG
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"POST_MERGE_CAPTURE_PENDING: $NAG_PR_RAW appears to have been merged but /session-capture has not run yet (lock file $NAG_LOCK exists). Run /session-capture before continuing to work. This nag fires on every Bash command until the capture completes and the lock is auto-cleared. If this is a false positive (e.g., the lock is stale from a prior session), remove it manually: rm $NAG_LOCK"}}
NAG
        # fall through — don't block; this is just a reminder
      fi
    fi
  fi
fi

# ─── Hard-block: worktree removal with pending capture ────────────────────────
# Only gate worktree removal commands
if ! echo "$COMMAND" | grep -qE 'git\s+worktree\s+remove'; then
  exit 0
fi

# Extract the worktree path from the command
WORKTREE_PATH=$(echo "$COMMAND" | sed -n 's/.*git worktree remove \([^ ]*\).*/\1/p')

# Resolve relative paths
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
if [ -n "$WORKTREE_PATH" ] && [[ "$WORKTREE_PATH" != /* ]]; then
  WORKTREE_PATH="$CWD/$WORKTREE_PATH"
fi

# Check for lock file
LOCK_FILE="/tmp/post-merge-capture-pending-$(echo "$WORKTREE_PATH" | md5 -q 2>/dev/null || echo "$WORKTREE_PATH" | md5sum 2>/dev/null | cut -d' ' -f1).lock"

if [ -f "$LOCK_FILE" ]; then
  PR_INFO=$(cat "$LOCK_FILE")

  # Extract PR number from the lock file content (e.g. "PR #584 merged from ...")
  PR_NUM=$(echo "$PR_INFO" | grep -oE '#[0-9]+' | head -1 | tr -d '#')

  # Check if a session file already captured this PR (created in the last 48h)
  CAPTURE_FOUND=false
  if [ -n "$PR_NUM" ]; then
    SESSION_DIR="$HOME/.claude/sessions"
    if [ -d "$SESSION_DIR" ]; then
      # Search recent session files for the PR number
      RECENT=$(find "$SESSION_DIR" -name 'session-*.md' -mtime -2 2>/dev/null)
      if [ -n "$RECENT" ]; then
        # head -1 always exits 0 even on empty input — check captured output instead.
        MATCH=$(echo "$RECENT" | xargs grep -l "#${PR_NUM}" 2>/dev/null | head -1)
        if [ -n "$MATCH" ]; then
          CAPTURE_FOUND=true
        fi
      fi
    fi
  fi

  if [ "$CAPTURE_FOUND" = true ]; then
    # Session capture exists — auto-clear the stale lock
    rm -f "$LOCK_FILE"
    echo "Post-merge lock auto-cleared: session capture for PR #$PR_NUM already exists."
  else
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: Session capture required before worktree removal. '"$PR_INFO"'. Run /session-capture first, then remove the lock: rm '"$LOCK_FILE"'"}}'
    exit 0
  fi
fi

exit 0
