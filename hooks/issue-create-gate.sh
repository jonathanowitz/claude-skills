#!/bin/bash
set -e

# PreToolUse hook: gate `gh issue create` behind an explicit, single-use, out-of-band
# approval token from USER.
#
# WHY THE GATE EXISTS
#   Filing GitHub issues is a shared-state change to USER's tracker (Project #1), which
#   he owns as his work sequencer. The recurring failure is NOT malice — it is Claude reading
#   a high-level intent ("defer these 4", an approved plan step, "we should track that") as a
#   per-item filing go and running `gh issue create` unilaterally. This happened repeatedly:
#   the #1154 thread (five unsequenced issues, 2026-07-20), then TWICE the same day on
#   2026-08-06 (#1318/#1319, then #1326/#1327/#1328 — "wtf why did you file 3 MORE FUCKING
#   ISSUES WITHOUT ASKING ME"). A passive memory nudge on this rule failed multiple times, so
#   it is now backed by this mechanism. See memory
#   feedback_decide_priority_together_on_issue_creation.
#
# HOW TO APPROVE A CREATE
#   Type in the prompt (the `!` prefix bypasses Bash-tool hooks, so Claude cannot self-approve
#   through this path):
#
#       ! mkdir -p ~/.claude/issue-approvals && touch ~/.claude/issue-approvals/next
#
#   Then ask Claude to file the issue. Claude runs `gh issue create ...`, this hook checks the
#   token, allows the create, and DELETES the token. The token is single-use: approving one
#   create does not approve the next. To approve N issues, touch it N times (or approve them
#   one at a time). The token is a CREDENTIAL, not a standing order — Claude must still show
#   the draft (title + label) and get an explicit yes before you approve.
#
# AUDIT TRAIL
#   ~/.claude/issue-approvals/audit.log records every consumption.
#
# COMMANDS GATED
#   gh issue create ...            (any flags — title, body, label, etc.)
#
# COMMANDS ALLOWED
#   gh issue view / list / comment / edit / close / develop / status / lock  (unaffected)
#   any command that merely MENTIONS "gh issue create" inside a quoted string
#     (e.g. git commit -m "strengthen gh issue create gate") — see detection note below
#   non-`gh issue create` commands entirely
#
# DETECTION
#   The command is tokenized once with shell quoting semantics (single quotes take no escapes,
#   double quotes do, backslash escapes one char outside quotes), then we look for the three
#   CONSECUTIVE argv tokens `gh` `issue` `create`. A quoted "gh issue create" collapses into a
#   single token and can never be three consecutive tokens, so a commit message or echo that
#   mentions the phrase is not blocked — the same argv-not-flattened-string lesson the
#   pr-merge-gate learned over four bypasses. This gate does NOT chase interpreter-evasion
#   (`bash -c "gh issue create"`): the threat model here is an innocent direct invocation, not
#   an adversary trying to slip a create past the gate.

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // ""')

deny() {
  jq -n --arg msg "$1" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $msg
    }
  }'
  exit 0
}

# Emit one VALUE per token, quote characters consumed the way the shell consumes them. A
# quoted span stays inside one token. (Trimmed from pr-merge-gate.sh's tokenizer — we only
# need the token VALUES here, not whether each was quoted.)
tokenize() {
  awk '
    function emit() { v = tok; gsub(/\n/, " ", v); printf "%s\n", v; tok = ""; has = 0 }
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
      n = length(buf); st = 0; tok = ""; has = 0
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (st == 0) {
          if (c == "\\") { i++; ch = substr(buf, i, 1); if (ch == "\n") continue
                           tok = tok ch; has = 1; continue }
          if (c == "'"'"'") { st = 1; has = 1; continue }
          if (c == "\"") { st = 2; has = 1; continue }
          if (c == " " || c == "\t" || c == "\n") { if (has) emit(); continue }
          tok = tok c; has = 1; continue
        }
        if (st == 1) { if (c == "'"'"'") { st = 0; continue } tok = tok c; continue }
        if (c == "\\") { i++; tok = tok substr(buf, i, 1); continue }
        if (c == "\"") { st = 0; continue }
        tok = tok c
      }
      if (has) emit()
    }
  '
}

# Look for consecutive `gh` `issue` `create` tokens.
is_create=0
TOK=()
while IFS= read -r line; do
  TOK+=("$line")
done < <(printf '%s' "$command" | tokenize)
n=${#TOK[@]}
for ((i = 0; i + 2 < n; i++)); do
  if [ "${TOK[i]}" = "gh" ] && [ "${TOK[i+1]}" = "issue" ] && [ "${TOK[i+2]}" = "create" ]; then
    is_create=1; break
  fi
done

[ "$is_create" = 1 ] || exit 0

approval_dir="$HOME/.claude/issue-approvals"
token="$approval_dir/next"

if [ ! -f "$token" ]; then
  deny "BLOCKED: filing a GitHub issue is not approved. Do NOT create issues unilaterally — a plan step, a 'defer these', or an approved high-level intent is NOT a per-item filing go. Show USER the draft (proposed title + label) and get an explicit yes. To approve, USER types in the prompt (the ! prefix bypasses Bash-tool hooks so Claude cannot self-approve): ! mkdir -p ~/.claude/issue-approvals && touch ~/.claude/issue-approvals/next — then ask Claude to file it. Approval is single-use; the hook deletes the token after consuming, so approving one issue does not approve the next."
fi

# Token exists. Consume it (single-use), audit, allow.
mkdir -p "$approval_dir"
audit_log="$approval_dir/audit.log"
cmd_excerpt=$(echo "$command" | head -c 200 | tr '\n' ' ')
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) issue-create approved + consumed (cmd: $cmd_excerpt)" >> "$audit_log"
rm -f "$token"

exit 0
