#!/usr/bin/env bash
# SessionStart hook — auto-register THIS session + surface OTHER sessions' WIP claims.
# Self-managing, no manual files to clean up:
#   register: auto-create example-app/wip/session-<id>.md (a skeleton the agent fills
#             with Owns / Do NOT touch); wip-cleanup.sh removes it at SessionEnd.
#   reap:     sweep session-*.md older than 3 days (orphans from abnormal exits).
#   read:     list every OTHER active claim's header so the session sees what's owned.
# See example-app/wip/README.md. Tracked in example-app#1007. bash 3.2-safe.

WIP_DIR="${HOME}/.claude/wip"
mkdir -p "$WIP_DIR" 2>/dev/null
[ -d "$WIP_DIR" ] || exit 0
input=""
[ -t 0 ] || input="$(cat 2>/dev/null)"   # read piped payload only; never block on a TTY
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"

# Reap orphaned auto-registrations from sessions that ended without SessionEnd firing.
find "$WIP_DIR" -maxdepth 1 -name 'session-*.md' -mtime +3 -delete 2>/dev/null

# Auto-register this session (skeleton the agent fills; removed at SessionEnd).
if [ -n "$sid" ]; then
  self="$WIP_DIR/session-$sid.md"
  if [ ! -f "$self" ]; then
    {
      printf '# WIP: session %s — (fill in: #issue — title)\n' "$sid"
      printf 'Session: %s (auto-registered)\n' "$sid"
      printf 'Status: 🟢 active\n'
      printf 'Owns:\n  - (fill in the files / surfaces you are editing)\n'
      printf 'Do NOT touch:\n  - (fill in other sessions'"'"' territory)\n'
      printf 'Depends on:\n  - none\n'
      printf 'Updated: %s\n' "$(date +%Y-%m-%d 2>/dev/null)"
    } > "$self" 2>/dev/null
  fi
  printf 'WIP: you are auto-registered as %s — fill in its Owns / Do NOT touch as you start work (auto-removed at session end).\n\n' "$self"
fi

# List OTHER sessions' active claims (skip this session's own file + the README).
shopt -s nullglob
active=()
for f in "$WIP_DIR"/*.md; do
  bn="$(basename "$f")"
  [ "$bn" = "README.md" ] && continue
  [ -n "$sid" ] && [ "$bn" = "session-$sid.md" ] && continue
  active+=("$f")
done

if [ "${#active[@]}" -eq 0 ]; then
  printf 'No other active WIP claims.\n'
  exit 0
fi

printf 'CONCURRENT-SESSION WIP CLAIMS (%s) — %d active. Read before editing shared files; honor each "Owns". Check each "Updated:" for staleness.\n\n' "$WIP_DIR" "${#active[@]}"
for f in "${active[@]}"; do
  printf '=== %s ===\n' "$(basename "$f")"
  cat "$f"
  printf '\n'
done
exit 0
