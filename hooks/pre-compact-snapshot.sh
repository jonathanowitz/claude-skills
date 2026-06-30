#!/bin/bash
# PreCompact hook — runs before Claude auto-compacts conversation context.
#
# Two outputs:
# 1. Git-state snapshot in ~/.claude/snapshots/ (legacy — useful for recovery)
# 2. Telemetry marker line in today's checkpoint file pointing at the transcript jsonl
#    so /session-capture can recover full conversation context even after compaction.
#
# The checkpoint marker is the load-bearing part — it's how we close the
# "telemetry lost on compaction" gap surfaced in maintenance-2026-05-12.md.

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "auto"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# --- Telemetry marker in today's checkpoint file ---
CHECKPOINT_DIR="$HOME/.claude/checkpoints"
CHECKPOINT_FILE="$CHECKPOINT_DIR/checkpoint-$(date +%Y-%m-%d).md"
mkdir -p "$CHECKPOINT_DIR"

# Initialize the checkpoint file with a header if it doesn't exist yet
if [ ! -f "$CHECKPOINT_FILE" ]; then
  echo "# Telemetry checkpoint — $(date +%Y-%m-%d)" > "$CHECKPOINT_FILE"
  echo "" >> "$CHECKPOINT_FILE"
fi

cat >> "$CHECKPOINT_FILE" <<MARKER

<!-- compaction $(date '+%H:%M:%S') -->
- **[compaction-event]:** $TRIGGER compaction triggered. Session: \`$SESSION_ID\`. Transcript: \`$TRANSCRIPT_PATH\`. cwd: \`$CWD\`. → /session-capture should parse the transcript jsonl for user-message redirects, tool failures (assumptions), Edit errors, and Skill invocations (protocol-followed) since this is the point where conversation context is about to be lost.
MARKER

# --- Legacy git-state snapshot (unchanged) ---
SNAPSHOT_DIR="$HOME/.claude/snapshots"
SNAPSHOT_FILE="$SNAPSHOT_DIR/pre-compact-$(date +%Y%m%d-%H%M%S).md"

mkdir -p "$SNAPSHOT_DIR"

cat > "$SNAPSHOT_FILE" << SNAPSHOT
# Pre-Compaction Snapshot — $(date '+%Y-%m-%d %H:%M:%S')

**Working Directory:** $(pwd)
**Git Branch:** $(git branch --show-current 2>/dev/null || echo "N/A")
**Session ID:** $SESSION_ID
**Transcript:** $TRANSCRIPT_PATH
**Trigger:** $TRIGGER

## Recent Git Activity
$(git log --oneline -5 2>/dev/null || echo "Not a git repo")

## Modified Files
$(git status --short 2>/dev/null || echo "N/A")

## Active Worktrees
$(git worktree list 2>/dev/null || echo "N/A")

## Night Shift State
$(cat tmp/night-shift-state.md 2>/dev/null || echo "No active night shift")

## Night Shift Notes
$(cat tmp/night-shift-notes.md 2>/dev/null || echo "No night shift notes")
SNAPSHOT

# Keep only last 10 snapshots to prevent unbounded growth
ls -t "$SNAPSHOT_DIR"/pre-compact-*.md 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null

echo "Pre-compaction snapshot saved: $SNAPSHOT_FILE"
echo "Telemetry marker appended to: $CHECKPOINT_FILE"
