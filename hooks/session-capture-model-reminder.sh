#!/bin/bash
# PreToolUse hook for Skill tool — fires when /session-capture is invoked.
# Reminds Claude to relay a model-cost note and signals subagent offload is active.

INPUT=$(cat)
SKILL=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')

if [ "$SKILL" = "session-capture" ]; then
  echo "SESSION_CAPTURE_HOOK: Running on current model. Only the session summary synthesis (step 1) executes here — all post-write work (next-steps, example-context, git commits, claude-config sync) will be offloaded to a spawned sonnet agent. If you haven't switched to /model sonnet and want the synthesis cheaper too, cancel now and switch first."
fi

exit 0
