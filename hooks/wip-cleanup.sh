#!/usr/bin/env bash
# SessionEnd hook — remove THIS session's WIP claim (example-app/wip/session-<id>.md).
# Decision A: hook-managed claims are named session-<id>.md, so cleanup keys on the
# session_id from stdin. Descriptively-named / manual claims are human-owned and NOT
# touched here. Safe degradation: if SessionEnd doesn't fire, the stale file is caught
# by the SessionStart staleness note. See example-app/wip/README.md. #1007 phase 2.
WIP_DIR="${HOME}/.claude/wip"
input=""
[ -t 0 ] || input="$(cat 2>/dev/null)"   # read piped payload only; never block on a TTY
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
[ -n "$sid" ] || exit 0
f="$WIP_DIR/session-$sid.md"
[ -f "$f" ] && rm -f "$f"
exit 0
