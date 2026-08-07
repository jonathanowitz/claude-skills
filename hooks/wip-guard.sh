#!/usr/bin/env bash
# PreToolUse(Write|Edit) hook — advisory warn when editing a file another active
# session's WIP claim lists under "Owns" (the affirmative "I'm editing this" claim;
# NOT "Do NOT touch", which is a self-directed stay-off note that attributes ownership
# backwards). Decision B = warn (NON-blocking):
# surfaces a note, never denies the edit. Keys off session_id to skip this session's
# own session-<id>.md claim. Coarse basename match scoped to the "Do NOT touch"
# section — advisory, so occasional false positives are acceptable and cheap to
# dismiss. See example-app/wip/README.md. #1007 phase 3.
WIP_DIR="${HOME}/.claude/wip"
[ -d "$WIP_DIR" ] || exit 0
input=""
[ -t 0 ] || input="$(cat 2>/dev/null)"   # read piped payload only; never block on a TTY
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$fp" ] || exit 0
base="$(basename "$fp")"
[ -n "$base" ] || exit 0
own="session-$sid.md"

hits=""
shopt -s nullglob
for f in "$WIP_DIR"/*.md; do
  bn="$(basename "$f")"
  [ "$bn" = "README.md" ] && continue
  [ -n "$sid" ] && [ "$bn" = "$own" ] && continue
  # Extract the "Owns:" section: from that label to the next top-level "Field:" line.
  section="$(awk '/^Owns:/{grab=1;next} grab && /^[A-Za-z].*:/{exit} grab{print}' "$f")"
  [ -z "$section" ] && continue
  if printf '%s\n' "$section" | grep -qF -- "$base"; then
    title="$(grep -m1 '^# ' "$f" | sed 's/^#\{1,\} *//')"
    hits="${hits}"$'\n'"  • ${title:-$bn}"
  fi
done

[ -n "$hits" ] || exit 0

msg="WIP GUARD (advisory, not blocking): \"$base\" is in another active session's \"Owns\" list:${hits}"$'\n'"Confirm it isn't being edited by a concurrent session before you write it."
jq -cn --arg m "$msg" '{systemMessage:$m, hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}'
exit 0
