#!/bin/bash
# PreToolUse hook — memory capture-then-disposition gate.
#
# Enforces the flow USER restored on 2026-06-26 (claude-config f47a236):
# memory candidates are STAGED, not committed live. The human disposition step
# is the gate against junk memories — NOT a blanket file-permission deny (the
# 2026-06-22 hard-deny 5fac05e was reverted because it killed the capture step
# and silently lost candidates).
#
# Behavior — on Write/Edit whose file_path is under an auto-memory dir
# (~/.claude/projects/*/memory/*  — the per-project MEMORY.md index AND the
# individual memory files):
#   • DENY, with a message telling the model to append the candidate to
#     ~/.claude/pending-memories.md instead. USER dispositions it at
#     /session-capture.
#   • EXCEPTION: if the fresh disposition flag ~/.claude/memory-disposition.active
#     exists (mtime < 60 min), ALLOW. The two USER-invoked curation flows
#     that legitimately commit approved memories — /session-capture disposition
#     and /maintenance Phase 5 — set this flag around their writes. Freshness is
#     required so a crashed flow that leaves the flag behind cannot silently
#     disable the gate forever (it self-heals after 60 min).
#
# ~/.claude/pending-memories.md is the staging target; it lives OUTSIDE any
# memory/ dir, so it is never matched here — staging is always allowed.
#
# Escape hatch (audit trail): touch ~/.claude/memory-disposition.active before a
# deliberate approved commit, rm it after.

hook_input=$(cat)
tool_name=$(echo "$hook_input" | jq -r '.tool_name // ""')
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // ""')

# Only Write/Edit are gated.
case "$tool_name" in
  Write|Edit) ;;
  *) exit 0 ;;
esac
[ -n "$file_path" ] || exit 0

# Only auto-memory dirs are gated. Scoped to the actual memory home
# (.claude/projects/<project>/memory/) rather than a bare */memory/* so an
# unrelated project directory named "memory" is not swept in.
case "$file_path" in
  */.claude/projects/*/memory/*) ;;
  *) exit 0 ;;
esac

# Fresh disposition flag → approved commit in progress → allow.
FLAG="$HOME/.claude/memory-disposition.active"
if [ -f "$FLAG" ]; then
  now=$(date +%s)
  mtime=$(stat -f %m "$FLAG" 2>/dev/null || stat -c %Y "$FLAG" 2>/dev/null || echo 0)
  if [ $(( now - mtime )) -lt 3600 ]; then
    exit 0
  fi
fi

reason=$(printf 'MEMORY GATE: memory candidates are STAGED, not committed live.\n\nDirect Write/Edit to a memory dir is blocked:\n  %s\n\nThe human disposition step is the gate against junk memories (USER 2026-06-26: disposition, not a permission deny). Instead of writing this now:\n\n  -> Append the candidate to ~/.claude/pending-memories.md — its target file path, memory type (user|feedback|project|reference), and content. USER dispositions it (commit / edit / discard) at /session-capture.\n\nIf you ARE running an approved commit — /session-capture disposition or /maintenance Phase 5 — set the exemption flag around the writes:\n  touch ~/.claude/memory-disposition.active   # honored for 60 min\n  ...write the memory file(s) + MEMORY.md...\n  rm ~/.claude/memory-disposition.active' \
  "$file_path")

jq -n --arg reason "$reason" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": $reason
  }
}'
exit 0
