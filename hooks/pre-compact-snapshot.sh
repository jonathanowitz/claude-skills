#!/bin/bash
# PreCompact hook — runs before Claude compacts conversation context (auto or manual).
#
# THREE outputs:
# 1. Structured telemetry EXTRACT in ~/.claude/precompact-captures/ (load-bearing).
#    Mechanically pulls metrics, tool tally, files touched, bash commands, verbatim
#    user prompts, and any tagged reflection events OUT of the transcript jsonl NOW,
#    so downstream (/session-capture, /maintenance) no longer has to rely on the raw
#    transcript surviving. This closes the "telemetry lost on compaction" gap while
#    removing the raw-transcript dependency (hardening asked for 2026-07-07).
# 2. Telemetry marker line in today's checkpoint file pointing at the extract.
# 3. Git-state snapshot in ~/.claude/snapshots/ (legacy — useful for recovery).
#
# SAFETY: PreCompact can BLOCK compaction on exit code 2. This hook must NEVER do that.
# Everything is defensive; the script always ends with `exit 0`. No `set -e`.

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRIGGER=$(echo "$INPUT" | jq -r '.trigger // "auto"' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

STAMP=$(date '+%Y-%m-%d-%H%M%S')
SESSION_SHORT=$(echo "${SESSION_ID:-unknown}" | cut -c1-8)

# --- 1. Structured telemetry extract (the hardening) ---
CAP_DIR="$HOME/.claude/precompact-captures"
mkdir -p "$CAP_DIR"
EXTRACT_FILE="$CAP_DIR/telemetry-$STAMP-$SESSION_SHORT.md"

TAGS="redirected|assumption|validation-skip|green-field-error|scope-creep|protocol-followed|efficiency-win"

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  T="$TRANSCRIPT_PATH"

  ASSISTANT_TURNS=$(jq -rc 'select(.type=="assistant")' "$T" 2>/dev/null | wc -l | tr -d ' ')
  USER_TURNS=$(jq -rc 'select(.type=="user") | select(.message.content|type=="string")' "$T" 2>/dev/null | wc -l | tr -d ' ')
  TOOL_CALLS=$(jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")' "$T" 2>/dev/null | wc -l | tr -d ' ')
  FIRST_TS=$(jq -rc 'select(.timestamp) | .timestamp' "$T" 2>/dev/null | head -1)
  LAST_TS=$(jq -rc 'select(.timestamp) | .timestamp' "$T" 2>/dev/null | tail -1)

  TOOL_TALLY=$(jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' "$T" 2>/dev/null | sort | uniq -c | sort -rn)
  FILES_TOUCHED=$(jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | select(.name=="Edit" or .name=="Write" or .name=="NotebookEdit") | .input.file_path // empty' "$T" 2>/dev/null | sort -u)
  BASH_CMDS=$(jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | select(.name=="Bash") | .input.command // empty' "$T" 2>/dev/null | cut -c1-160 | head -80)
  USER_PROMPTS=$(jq -rc 'select(.type=="user") | select(.message.content|type=="string") | .message.content' "$T" 2>/dev/null | cut -c1-320 | head -50)
  # Tagged events land in today's checkpoint file (written via printf during the
  # session), NOT in assistant text — so grep BOTH the checkpoint and transcript text.
  CHECKPOINT_TODAY="$HOME/.claude/checkpoints/checkpoint-$(date +%Y-%m-%d).md"
  TAG_EVENTS=$( { cat "$CHECKPOINT_TODAY" 2>/dev/null; jq -rc 'select(.type=="assistant") | .message.content[]? | (.thinking // .text // empty)' "$T" 2>/dev/null; } | grep -oaE "\*\*\[?(${TAGS})[^*]*:\*\*.{0,240}" 2>/dev/null | sort -u | head -50)

  cat > "$EXTRACT_FILE" <<EXTRACT
# Pre-Compaction Telemetry Extract — $(date '+%Y-%m-%d %H:%M:%S')

- **Session:** \`$SESSION_ID\`
- **Trigger:** $TRIGGER
- **cwd:** $CWD
- **Branch:** $(git -C "${CWD:-.}" branch --show-current 2>/dev/null || echo "N/A")
- **Transcript (source):** \`$TRANSCRIPT_PATH\`

## Session Metrics
- Assistant entries (content blocks): ${ASSISTANT_TURNS:-0}
- User prompts: ${USER_TURNS:-0}
- Tool calls: ${TOOL_CALLS:-0}
- Span: ${FIRST_TS:-?} → ${LAST_TS:-?}

## Tool Telemetry (tally by tool)
\`\`\`
${TOOL_TALLY:-none}
\`\`\`

## Files Touched (Edit/Write/NotebookEdit)
${FILES_TOUCHED:-none}

## Tagged Reflection Events (checkpoint + transcript)
> Grepped from today's checkpoint file and assistant text. NOT a substitute for a
> /session-capture pass — it only catches events already written as tag lines.
${TAG_EVENTS:-none found — distil from prompts + tool telemetry below at /session-capture}

## User Prompts (verbatim, truncated — redirect / scope-change signal)
${USER_PROMPTS:-none}

## Bash Commands Run (truncated)
\`\`\`
${BASH_CMDS:-none}
\`\`\`
EXTRACT

  EXTRACT_STATUS="written"
else
  # No transcript to parse — record why, don't fail.
  cat > "$EXTRACT_FILE" <<EXTRACT
# Pre-Compaction Telemetry Extract — $(date '+%Y-%m-%d %H:%M:%S')

- **Session:** \`$SESSION_ID\`
- **Trigger:** $TRIGGER
- **NOTE:** transcript_path missing or unreadable (\`$TRANSCRIPT_PATH\`) — no extract possible.
EXTRACT
  EXTRACT_STATUS="no-transcript"
fi

# Retention: keep last 30 extracts
ls -t "$CAP_DIR"/telemetry-*.md 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null

# --- 2. Telemetry marker in today's checkpoint file (points at the extract now) ---
CHECKPOINT_DIR="$HOME/.claude/checkpoints"
CHECKPOINT_FILE="$CHECKPOINT_DIR/checkpoint-$(date +%Y-%m-%d).md"
mkdir -p "$CHECKPOINT_DIR"

if [ ! -f "$CHECKPOINT_FILE" ]; then
  echo "# Telemetry checkpoint — $(date +%Y-%m-%d)" > "$CHECKPOINT_FILE"
  echo "" >> "$CHECKPOINT_FILE"
fi

cat >> "$CHECKPOINT_FILE" <<MARKER

<!-- compaction $(date '+%H:%M:%S') -->
- **[compaction-event]:** $TRIGGER compaction. Session \`$SESSION_ID\`. Structured telemetry extract ($EXTRACT_STATUS): \`$EXTRACT_FILE\`. → /session-capture: read the extract (metrics, tool tally, files, prompts, tag events) — the raw transcript is no longer required, but remains at \`$TRANSCRIPT_PATH\` as fallback.
MARKER

# --- 3. Legacy git-state snapshot (unchanged) ---
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

# Keep only last 10 git snapshots
ls -t "$SNAPSHOT_DIR"/pre-compact-*.md 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null

echo "Telemetry extract saved: $EXTRACT_FILE ($EXTRACT_STATUS)"
echo "Checkpoint marker appended: $CHECKPOINT_FILE"
echo "Git snapshot saved: $SNAPSHOT_FILE"
exit 0
