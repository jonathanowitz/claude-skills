#!/bin/bash
# UserPromptSubmit hook — detects likely "redirected by user" telemetry events
# from corrective phrases in the user's message and nudges the agent to append
# a checkpoint event before continuing.
#
# Design notes (from maintenance-2026-05-12.md New Gap #2):
#   - Streaming-protocol compliance is ~6% based on session evidence.
#   - The CLAUDE.md "Write events to disk immediately" instruction is itself
#     an advisory rule subject to the same compliance gap.
#   - Mechanical mechanisms (hooks, gates) hit ~100% compliance; advisory ~55%.
#   - This hook turns the most common telemetry event (redirected) into a
#     mechanical nudge that fires when the user message looks like a correction.
#
# False-positive cost: harmless one-line nudge the agent ignores.
# False-negative cost: current state (event lost on compaction).

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // .message // empty' 2>/dev/null)

# Bail out cleanly if no prompt
[ -z "$PROMPT" ] && exit 0

# Skip slash-command-only messages — those are explicit invocations, not redirects.
# Match: starts with `/` followed by a command name and optional whitespace/args
if echo "$PROMPT" | head -c 200 | grep -qE '^/[a-z][a-z0-9_-]*(\s|$)'; then
  exit 0
fi

# Corrective phrases — kept conservative to limit false positives.
# Anchored: phrases that mean "you misread what I wanted."
PATTERNS=(
  # Start-of-message correctives (with required punctuation/space to avoid "no problem")
  '^[Nn]o[,.!]'
  '^[Nn]o[[:space:]]+(that|don|wait|stop|not|the|you|I)'
  '^[Nn]o\.'
  '^[Ww]ait[,.!]'
  '^[Ww]ait[[:space:]]+(a|stop|that|don|hold|no|why|what|but)'
  '^[Ss]top[,.!]'
  '^[Ss]top[[:space:]]+(doing|that|right)'
  '^[Aa]ctually[,.!]'
  "^[Dd]on'?t[[:space:]]"
  '^[Hh]old[[:space:]]+on'

  # Mid-message correctives — substring match
  '[Ii] thought you'
  '[Ww]e (already|just) (did|fixed|shipped|covered|handled|figured)'
  "[Dd]idn'?t (I|we|you)"
  '[Yy]ou (forgot|already|just)'
  '[Yy]ou(.)?re misreading'
  "[Tt]hat'?s not what (I|we)"
  "[Nn]ot what (I|we) (meant|wanted|asked|said)"
  '[Ll]et me clarify'
  '[Tt]o be clear'
  '[Ww]e figured (this|that|it) out'

  # All-caps emphatic
  '\bNO\b'
  '\bSTOP\b'
  '\bWAIT\b'
)

MATCH=""
for pat in "${PATTERNS[@]}"; do
  if echo "$PROMPT" | grep -qE "$pat"; then
    MATCH="$pat"
    break
  fi
done

[ -z "$MATCH" ] && exit 0

CHECKPOINT_FILE="$HOME/.claude/checkpoints/checkpoint-$(date +%Y-%m-%d).md"

# Emit nudge as additionalContext via JSON output (UserPromptSubmit convention).
# This becomes a system-reminder the agent sees before its next action.
cat <<NUDGE
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"REDIRECT_NUDGE: User message matched corrective-phrase pattern \`$MATCH\`. Before your next substantive action, append a one-line redirected: event to $CHECKPOINT_FILE describing what direction you were going and how the user redirected you. Format: '- **[redirected:<subtype>]:** <what happened> → <lesson>'. Subtypes: product, technical, scope, protocol. Skip the nudge only if this is clearly not a redirect (e.g., user is quoting code, asking a clarifying question, or the match is a false positive)."}}
NUDGE

exit 0
