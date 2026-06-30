#!/bin/bash
# PreToolUse hook for Bash. Blocks when a Bash command chains multiple commands
# with && or ; in the projects listed in the scope guard below.
#
# Rule: "One command per Bash call — never chain with &&, ;, or & + another
# command." Promoted from advisory warning to hard block 2026-05-15 after 5
# violations in one session (including 3 post-logging). Self-correction failed;
# mechanical enforcement is the only reliable lever. Matches post-merge-gate.sh /
# red-checkpoint-gate.sh precedent.
#
# Scope: opt-in per project via the case statement below. Currently example-app
# and dcc-knowledge-graph (added 2026-06-11 at USER's request). Other projects
# unaffected. cd-prefixed chains (`cd X && cmd`) ARE blocked (no exception); a bare
# `cd X` with no chain operator passes the detection naturally.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Bail if no command or cwd
[ -z "$COMMAND" ] && exit 0
[ -z "$CWD" ] && exit 0

# Project-scoped: only fire in the opted-in projects
case "$CWD" in
  $HOME/Projects/example-app*) ;;
  $HOME/Projects/dcc-knowledge-graph*) ;;
  *) exit 0 ;;
esac

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

# Hard block — split the chain into separate Bash calls (or parallel calls for independent commands).
jq -n --arg op "$CHAINED" '{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": ("BASH_CHAINING BLOCKED: command chains with `" + $op + "`. This project requires one command per Bash call. Split into separate calls or use parallel Bash calls for independent commands. Escape: if this chain is a genuine single-construct (trap, heredoc, shell function body), move it to a shell script file and call that instead.")
  }
}'
exit 0
