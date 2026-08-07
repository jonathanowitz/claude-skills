#!/usr/bin/env bash
# SessionStart: surface claude-config hook drift so a merged hook can't sit inert.
#
# WHY (#1231): ~/.claude/commands is a symlink into the repo, but ~/.claude/hooks/
# is a copy — merging a hook does NOT put it on the path, and nothing surfaces the
# gap. The failure mode (a hook that never fires) looks identical to a hook that
# fired and found nothing. deploy-hooks.sh already computes the drift read-only in
# check mode (exit 0 == in sync, exit 1 == drift); we run it on SessionStart and
# print ONLY when something is out of sync. Silent on a clean tree.
#
# THROTTLE: this hook runs every session, but a warning we already showed and did
# not act on is just wasted context. So a given drift state is reported at most
# once per day. Crucially the throttle keys on the drift CONTENT, not the clock and
# not the filename set alone: the signature folds each drifted file's repo-side
# content hash, so a NEW merged version of a hook ALREADY in the drift set changes
# the signature and re-fires immediately — a filename-only key would suppress that
# for 24h and silently miss the exact "merged but not deployed" case this exists
# for. Steady-state, unfixed drift resurfaces once a day as a reminder, no more.
#
# Symlinking hooks/ to remove the asymmetry is deliberately off the table: hooks
# drift both ways (guardrail scripts are edited live-authoritatively) and the copy
# is the safety gap that stops a bad merged hook from breaking every session at
# once. So surfacing the drift is the fix, not auto-deploying it.
set -uo pipefail

# CLAUDE_CONFIG_REPO, not CLAUDE_CONFIG_DIR — the latter is Claude Code's OWN var
# for the ~/.claude config dir; reusing it would silently point REPO at ~/.claude
# (no deploy-hooks.sh there) and make this hook inert — the exact failure it exists
# to catch. deploy-hooks.sh uses the same namespaced style (CLAUDE_HOOKS_DIR).
REPO="${CLAUDE_CONFIG_REPO:-$HOME/Projects/claude-config}"
DEPLOY="$REPO/deploy-hooks.sh"
STATE="${CLAUDE_DRIFT_STATE:-$HOME/.claude/.hooks-drift-check.state}"

# No repo / no script to check against — stay silent, never block a session.
[ -x "$DEPLOY" ] || exit 0

report="$("$DEPLOY" 2>/dev/null)"
status=$?
[ "$status" -eq 0 ] && exit 0   # in sync — say nothing
# Non-zero but EMPTY stdout is deploy-hooks.sh erroring (e.g. its FATAL no-hooks-dir
# path exits 1 with nothing on stdout), not drift — never print a bodyless banner.
[ -n "$report" ] || exit 0

# Once-per-day-per-drift-CONTENT throttle. The signature folds each drifted file's
# basename with a hash of its repo-side content, so both a changed set (new file
# drifts) AND a changed version of an already-listed file (a fresh merge) yield a
# new sig and re-fire regardless of the date. deploy-hooks.sh emits basenames only,
# so the content has to come from the files themselves; the last field of each
# classification line is the basename.
today=$(date +%F)
sig=$(echo "$report" | grep -E 'DRIFTED|REPO-ONLY|LIVE-ONLY' | awk '{print $NF}' | sort \
      | while IFS= read -r b; do
          printf '%s:%s\n' "$b" "$(shasum -a 256 "$REPO/hooks/$b" 2>/dev/null | cut -c1-16)"
        done | shasum -a 256 | cut -c1-16)
if [ -f "$STATE" ]; then
  read -r prev_date prev_sig < "$STATE" 2>/dev/null || true
  [ "${prev_date:-}" = "$today" ] && [ "${prev_sig:-}" = "$sig" ] && exit 0
fi

echo "⚠️  claude-config HOOK DRIFT (#1231) — repo and live ~/.claude/hooks/ disagree."
echo "$report" | sed '1d;/^$/d;/[0-9]* file(s) out of sync/d;/Nothing was changed/d'
echo "  Reconcile from $REPO:"
echo "    DRIFTED / REPO-ONLY  ->  ./deploy-hooks.sh <name>...   (put the merged hook on the path)"
echo "    LIVE-ONLY            ->  ./sync.sh && commit           (if the live copy is authoritative)"

# Stamp AFTER printing, and mkdir the state dir first: a CLAUDE_DRIFT_STATE override
# to a not-yet-existing dir would otherwise fail the write silently and disable the
# throttle, and stamping only after a successful print avoids throttling a report the
# session harness truncated before the user saw it.
mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
printf '%s %s\n' "$today" "$sig" > "$STATE" 2>/dev/null || true
exit 0
