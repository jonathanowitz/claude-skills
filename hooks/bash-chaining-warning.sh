#!/bin/bash
# PreToolUse hook for Bash. In every repo, blocks a Bash command that CHAINS
# multiple commands with && or ; ONLY when the chain carries a gated or
# destructive command. Benign inspection chains are allowed.
#
# History:
#   2026-05-15  Promoted from advisory warning to a hard block on ALL chains after
#               self-correction failed (5 violations/session). Mechanical
#               enforcement was the only reliable lever.
#   2026-06-24  Removed the cd-prefix exception — `cd X && gh pr merge` had bypassed
#               the pr-merge gate (PR #954).
#   2026-07-20  NARROWED: allow benign chains; block only chains containing a gated
#               verb. Rationale from mining 3015 real blocks: 97.4% (2937) were
#               benign inspection chains (ls/cat/grep/cd/test … && echo) with zero
#               gate relevance, and the blanket rule never once caught a genuine
#               hidden mutation (all 3 "mutation" hits were grep-for-text false
#               positives). The original driver — chains always cost a manual
#               approval even under accept-edits — is moot under auto mode. What
#               survives is gate integrity: a chain must not hide rm / a DB mutation
#               / gh pr merge / git commit|push from the other safety gates.
#
# Scope: applies in every repo (example-app/#1201 — see the removed-allowlist
# note below). A bare `cd X` with no chain operator passes naturally; `cd X &&
# <gated cmd>` is still blocked.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Bail if no command or cwd
[ -z "$COMMAND" ] && exit 0
[ -z "$CWD" ] && exit 0

# Applies in EVERY repo (example-app/#1201). The prior opt-in case fired only in
# example-app + dcc-knowledge-graph, leaving decidr / example-b / consulting /
# example-c with no protection against a chained rm / db push / gh pr merge /
# git push. The 2026-07-20 narrowing made universal application safe: only chains
# carrying a gated/destructive verb are blocked; benign inspection chains pass.

# NO cd-prefix exception. `cd X && cmd` is a chain and IS blocked below; a bare
# `cd X` (no operator) passes the detection naturally. The prior cd-skip delegated
# to a settings.local.json rule that never existed, leaving every `cd … && <gated
# cmd>` unguarded — that bypassed the pr-merge gate (2026-06-24, PR #954).

# Strip heredoc bodies first — anything between `<<EOF` (or `<<'EOF'`, etc.)
# and the closing `EOF` on its own line is data, not shell commands.
# Conservative: if a heredoc is present, just strip from `<<` onward — false
# negatives on commands chained AFTER a heredoc are acceptable; false positives
# on `&&` in commit messages are not.
if echo "$COMMAND" | grep -q '<<'; then
  # Collapse to one line first so sed strips through subsequent heredoc body lines.
  STRIPPED=$(echo "$COMMAND" | tr '\n' ' ' | sed 's/<<.*//')
else
  STRIPPED="$COMMAND"
fi

# Strip quoted strings (single + double) so operators inside them don't trigger.
# Conservative: doesn't handle nested or escaped quotes. False negatives OK.
STRIPPED=$(echo "$STRIPPED" | sed "s/'[^']*'//g" | sed 's/"[^"]*"//g')

# Strip find's \; argument terminator
STRIPPED=$(echo "$STRIPPED" | sed 's/\\;//g')

# Skip shell control flow that legitimately uses ; inside its syntax
case "$STRIPPED" in
  for[[:space:]]*|while[[:space:]]*|until[[:space:]]*|if[[:space:]]*|case[[:space:]]*) exit 0 ;;
  *)
    # Also skip if the command opens a block via `{ ... ; }` or `(... ; ...)`
    if echo "$STRIPPED" | grep -qE '^\s*[\{(]'; then exit 0; fi
    ;;
esac

# Now check for chaining operators. && is two chars; ; is one char.
# Skip ;; (case statement separator) and || (logical or — different class).
# Also skip lines where the chain operator is the very last char (heredoc-ish).
CHAINED=""

# Look for && (not preceded by |)
if echo "$STRIPPED" | grep -qE '[^&|]&&[^&|]|[^&|]&&$'; then
  CHAINED="&&"
fi

# Look for ; that isn't part of ;; case-separator
if [ -z "$CHAINED" ] && echo "$STRIPPED" | grep -qE '[^;];[^;]|[^;];$'; then
  CHAINED=";"
fi

[ -z "$CHAINED" ] && exit 0

# --- Narrowing gate (2026-07-20) --------------------------------------------
# A chain is present. Allow it UNLESS it carries a gated/destructive command.
# Detection runs on $STRIPPED (heredoc + quoted strings already removed above), so
# `grep "DELETE FROM"` / `grep ".insert("` do NOT false-positive — that text lives
# inside quotes and is gone. Real mutations are caught by command name
# (psql/supabase/mysql), which sits OUTSIDE quotes, plus a residual inline-SQL net.
# SEG = a segment boundary (start-of-string or after ; & |) followed by optional
# `sudo ` and/or leading `VAR=val ` env prefixes. Anchoring the executable match to
# SEG means we catch `; rm …` / `&& psql …` (command position) but NOT `which psql`
# or `ls /opt/homebrew/bin/psql` (the tool name is a mere argument there).
SEG='(^|[;&|])[[:space:]]*(sudo[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*'
DANGER="${SEG}(rm|psql|supabase|mysql|mongosh|mongo|dropdb)([[:space:]]|\$)"
DANGER="$DANGER|${SEG}gh[[:space:]]+(pr[[:space:]]+merge|api[[:space:]].*merge)"
DANGER="$DANGER|${SEG}git[[:space:]]+(push|commit|merge|rebase|reset|clean)([[:space:]]|\$)"
# Unquoted inline SQL mutation (backup for the CLI name-match above). NOT a JS
# `.insert(`/`.update(` net — that matched Python list.insert()/dict.update() far
# more than any real DB write (0 genuine catches in 3015 blocks); db-mutation-check
# already greps every call for those patterns.
DANGER="$DANGER|(delete[[:space:]]+from|insert[[:space:]]+into|update[[:space:]]+[^;&|]+[[:space:]]+set)"

if ! printf '%s' "$STRIPPED" | grep -qiE "$DANGER"; then
  exit 0   # benign inspection chain — nothing a gate cares about; allow it
fi
# Falls through: the chain carries a gated/destructive command → block it so each
# command is individually visible to the merge / db-mutation / commit gates.

# Hard block — split the chain into separate Bash calls (or parallel calls for independent commands).
jq -n --arg op "$CHAINED" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ("BASH_CHAINING BLOCKED: this `" + $op + "` chain carries a gated or destructive command (rm / DB mutation / gh pr merge / git commit|push|reset|clean), so it must be split — each command has to be individually visible to the safety gates. Split into separate Bash calls (or parallel calls if independent). Benign inspection chains like `ls && echo` are allowed. Escape for a genuine single-construct (trap, heredoc, shell function body): move it to a shell script file and call that.")
  }
}'
exit 0
