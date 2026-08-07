#!/bin/bash
set -e

# PreToolUse hook: gate `gh pr merge` (and equivalent `gh api` PUT calls)
# behind explicit per-PR approval from USER.
#
# WHY THE GATE EXISTS
#   PR merges are destructive shared-state changes. Without a gate, Claude
#   could merge based on conversational ambiguity ("looks good" / "we are
#   good"). The original gate denied unconditionally, but that prevented
#   the post-merge automation chain (POST_MERGE_HOOK → /session-capture →
#   cleanup agent) from firing — USER had to merge externally and then
#   manually trigger cleanup. This version reopens that chain by allowing
#   merges with explicit, per-PR, single-use tokens.
#
# HOW TO APPROVE A MERGE
#   Type in the prompt (the `!` prefix bypasses Bash-tool hooks, so Claude
#   cannot fake an approval through this path):
#
#       ! mkdir -p ~/.claude/merge-approvals && touch ~/.claude/merge-approvals/<PR_NUMBER>
#
#   Then ask Claude to merge. Claude runs `gh pr merge <PR_NUMBER> ...`,
#   this hook checks the token, allows the merge, and DELETES the token.
#
# AUDIT TRAIL
#   ~/.claude/merge-approvals/audit.log records every consumption.
#
# COMMANDS GATED
#   gh pr merge ...                              (any flags / PR number)
#   gh api -X PUT .../pulls/<N>/merge            (REST PUT to merge endpoint)
#   gh api --method PUT .../pulls/<N>/merge
#
# COMMANDS ALLOWED
#   gh pr view, gh pr list, gh pr checks, gh pr create, gh pr comment, gh pr diff
#   gh pr merge --help / -h
#   gh api calls that aren't PUT-on-merge
#   non-`gh` commands entirely (skipped — see false-positive guard below)

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

# False-positive guard. The ONLY thing this guard exists to let through is a command that
# merely mentions the merge in text — `git commit -m 'run gh pr merge after review'`. It has
# now been rewritten three times, each time by enumerating one more thing allowed to sit in
# front of `gh`, and each round shipped with a live bypass:
#   - `^gh` only                        → `cd <dir> && gh pr merge` (2026-06-24, PR #954)
#   - separators added                  → `GH_CONFIG_DIR=... gh pr merge` (2026-07-10, PR #14)
#   - assignment prefixes added         → `env VAR=... gh`, `sudo gh`, `GH_CONFIG_DIR="a b" gh`
# Enumerating permitted prefixes is unwinnable: `env`, `sudo`, `command`, `time`, `nohup`,
# `xargs` and quoted assignment values are all the same shape, and the multi-account workflow
# these prefixes serve makes `env VAR=x gh` the likeliest variant of the very command PR #14
# fixed.
#
# So the guard stops asking what may precede `gh` and asks the one question that actually
# separates the two cases: is this `gh` INSIDE a quoted string? Text lives in quotes, commands
# do not. That is the right rule, and a pair of `sed s/'[^']*'//g` passes is not a way to
# implement it — a context-free regex has no idea which quote opened the span it is closing:
#
#     git commit -m "it's ready" && gh pr merge 42 -m "doesn't need rework"
#
# The apostrophes in `it's` and `doesn't` pair with EACH OTHER, delete the `gh pr merge`
# between them, and the merge runs with no token check and no review check. Apostrophes in
# commit text are routine, so that bypass is reachable by accident — the fourth iteration of
# this guard and the fourth live bypass.
#
# So the quote-tracking is a real single-pass scanner with shell semantics: single quotes do
# not honour escapes, double quotes do, and a backslash outside quotes escapes exactly one
# character.
#
# ROUND FIVE, and the last one that should be needed, because it fixes the LEVEL rather than
# the pattern. Rounds one through four all did the same thing: answer the quoting question
# correctly, then throw the answer away and grep a flattened copy of the command. Round four
# blanked quoted spans to spaces for DETECTION and then extracted from `tr -d "\"'"` — prose
# and argv in one string — which produced three more defects at once (cross-model review of
# `bdbfa46`):
#
#     gh pr merge --squash -b "closes 1234"    → 1234 read as the PR: verified #1234's review,
#                                                consumed #1234's token, merged this branch
#     gh pr merge 42 -b "mirrors --repo o/x" …  → the MENTION won --repo when it came first
#     gh pr merge 42 --squash | tee /tmp/x-h.log → `-h` matched as a substring, skipping the
#                                                  review check, the token, and the audit log
#
# There is no fifth regex that fixes those, because the defect is not in any regex: a flattened
# string cannot distinguish an argument from a sentence, and every extraction built on one is
# guessing. So the command is TOKENIZED ONCE with shell semantics, and every question after
# that — is this a merge, which PR, which repo, is this just --help — is answered by reading
# the argv array the way `gh` itself would receive it.
#
# That is what makes the quoting rule finally load-bearing instead of decorative: a quoted span
# stays INSIDE one token, so `git commit -m 'run gh pr merge 42'` yields a single token whose
# value is the whole sentence and can never be the three consecutive tokens `gh` `pr` `merge`.
# Note the corollary — the token's VALUE is what matters, not whether it was quoted, so
# `"gh" pr merge 42` (a quoted command name, which shell executes perfectly well) is still
# caught, where a Q/U distinction would have opened bypass number five.
#
# Unknown flags are assumed to CONSUME A VALUE. That is deliberately the fail-closed guess: a
# flag wrongly treated as boolean lets its value be read as the PR number, while a flag wrongly
# treated as value-taking hides the positional, leaves the number empty, and the hook refuses.
#
# Round two of that history is also a drift story: the env-var half lived only in
# ~/.claude/hooks/ for two weeks. Drift runs both ways (#1113) — anything edited live must be
# carried back before a repo->live deploy, or the deploy reopens the bypass.
#
# Emits one line per token: `Q` or `U` (was any part of it quoted) TAB the token's VALUE, with
# quote characters consumed the way the shell consumes them. An unterminated quote emits a
# trailing `!` record — input that is not valid shell, but a scanner that silently answers "no
# invocation here" on input it could not parse would invert this file's fail-closed posture.
tokenize() {
  awk '
    function emit() {
      v = tok; gsub(/\n/, " ", v)
      printf "%s\t%s\n", (quoted ? "Q" : "U"), v
      tok = ""; has = 0; quoted = 0
    }
    { buf = buf (NR > 1 ? "\n" : "") $0 }
    END {
      n = length(buf); st = 0; tok = ""; has = 0; quoted = 0
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (st == 0) {
          # A backslash escapes the next character; a backslash-newline is a line
          # continuation and disappears entirely rather than joining two tokens.
          if (c == "\\") { i++; ch = substr(buf, i, 1); if (ch == "\n") continue
                           tok = tok ch; has = 1; continue }
          if (c == "'"'"'") { st = 1; quoted = 1; has = 1; continue }
          if (c == "\"") { st = 2; quoted = 1; has = 1; continue }
          if (c == " " || c == "\t" || c == "\n") { if (has) emit(); continue }
          tok = tok c; has = 1; continue
        }
        if (st == 1) {
          # No escapes inside single quotes: the next quote always closes.
          if (c == "'"'"'") { st = 0; continue }
          tok = tok c; continue
        }
        if (c == "\\") { i++; tok = tok substr(buf, i, 1); continue }
        if (c == "\"") { st = 0; continue }
        tok = tok c
      }
      if (has) emit()
      if (st != 0) print "!\tUNTERMINATED"
    }
  '
}

# Reads a command string as argv and sets ANALYZE_RESULT to `<pr-number> <TAB> <repo>` if it is
# a gated merge, or to the empty string if it is not. The PR number is empty when the command is
# a merge with no resolvable positional — the caller refuses in that case rather than guessing.
#
# Sets globals rather than printing, because the caller needs ANALYZE_QUOTED and UNTERMINATED
# back: `result=$(analyze …)` runs the whole function in a subshell, and both of those died with
# it, which silently disabled the interpreter recursion below.
#
# Runs on the raw command, and again on each quoted token when an interpreter is present: it is
# the same question asked of `bash -c "gh pr merge 42"`, whose quoting proves nothing because
# something is about to execute the quoted string.
analyze() {
  local cmd="$1" f v i n mi=-1 ai=-1 put=0 pr="" repo="" pos="" helped=0 apipr=""
  ANALYZE_RESULT=""
  local -a V=() Q=()
  while IFS=$'\t' read -r f v; do
    [ "$f" = "!" ] && { UNTERMINATED=1; continue; }
    Q+=("$f"); V+=("$v")
  done < <(printf '%s' "$cmd" | tokenize)
  n=${#V[@]}
  ANALYZE_QUOTED=()
  for ((i = 0; i < n; i++)); do
    [ "${Q[i]}" = "Q" ] && ANALYZE_QUOTED+=("${V[i]}")
  done

  # `--repo` / `-R` from the ARGV, so a mention in a body can never win the match regardless
  # of where it sits. First occurrence: argv order is what gh honours.
  for ((i = 0; i < n; i++)); do
    case "${V[i]}" in
      --repo=*|-R=*) repo="${V[i]#*=}"; break ;;
      --repo|-R) [ $((i + 1)) -lt "$n" ] && repo="${V[i+1]}"; break ;;
    esac
  done

  for ((i = 0; i + 2 < n; i++)); do
    if [ "${V[i]}" = "gh" ] && [ "${V[i+1]}" = "pr" ] && [ "${V[i+2]}" = "merge" ]; then
      mi=$((i + 3)); break
    fi
  done
  for ((i = 0; i + 1 < n; i++)); do
    if [ "${V[i]}" = "gh" ] && [ "${V[i+1]}" = "api" ]; then ai=$((i + 2)); break; fi
  done

  # `gh api -X PUT .../pulls/<N>/merge` — the second gated form, per this file's header.
  if [ "$ai" -ge 0 ]; then
    for ((i = 0; i < n; i++)); do
      case "${V[i]}" in
        PUT|--method=PUT|-X=PUT) put=1 ;;
      esac
      case "${V[i]}" in
        */pulls/*/merge*) apipr=$(printf '%s' "${V[i]}" \
                                  | sed -nE 's|.*/pulls/([0-9]+)/merge.*|\1|p') ;;
      esac
    done
    if [ "$put" = 1 ] && [ -n "$apipr" ]; then
      ANALYZE_RESULT="$apipr	$repo"
      return 0
    fi
  fi

  [ "$mi" -ge 0 ] || return 0

  # Walk argv after `merge` for the first POSITIONAL. Booleans are enumerated; everything else
  # beginning with `-` is assumed to take a value, which fails closed (see the header).
  i=$mi
  while [ "$i" -lt "$n" ]; do
    case "${V[i]}" in
      --help|-h) helped=1; i=$((i + 1)) ;;
      --*=*) i=$((i + 1)) ;;
      --squash|--merge|--rebase|--admin|--auto|--delete-branch|--disable-auto|-s|-m|-r|-d)
        i=$((i + 1)) ;;
      -*) i=$((i + 2)) ;;
      *) pos="${V[i]}"; break ;;
    esac
  done

  case "$pos" in
    "") ;;
    *[!0-9]*) pr=$(printf '%s' "$pos" | sed -nE 's|.*/pull/([0-9]+).*|\1|p') ;;
    *) pr="$pos" ;;
  esac

  # `--help` as its OWN token, and only when no PR was named. Round four matched `(-h)\b`
  # against flattened text, so `| tee /tmp/merge-h.log` and `--body-file /tmp/notes-h` both
  # skipped the entire gate — that exit precedes the review check, the token, and the audit log.
  if [ "$helped" = 1 ] && [ -z "$pr" ]; then
    return 0
  fi

  # Always contains the separator when this IS a merge, so a merge with an unresolvable PR
  # number is still distinguishable from "not a merge at all" by the caller's -n test.
  ANALYZE_RESULT="$pr	$repo"
}

UNTERMINATED=0
ANALYZE_QUOTED=()
ANALYZE_RESULT=""
analyze "$command"
result="$ANALYZE_RESULT"

# Something is about to EXECUTE a quoted string, so the quoting proves nothing about it. Ask
# the same question of each quoted token. Pipe-into-a-shell and `python -c` are here for the
# same reason `bash -c` is; the previous list named only the forms that take `-c` as a flag.
if [ -z "$result" ] && printf '%s' "$command" | grep -qE '\bgh\b'; then
  if printf '%s' "$command" | grep -qE '(\b(ba|z|da)?sh\b[^|;&]*-c\b|\bpython[0-9.]*\b[^|;&]*-c\b|\beval\b|\bxargs\b|\|[[:space:]]*(ba|z|da)?sh\b)'; then
    # The list is expanded once here, so the inner analyze() overwriting ANALYZE_QUOTED
    # mid-loop cannot change what is still to be examined.
    for q in "${ANALYZE_QUOTED[@]}"; do
      analyze "$q"
      if [ -n "$ANALYZE_RESULT" ]; then result="$ANALYZE_RESULT"; break; fi
    done
  fi
fi

# Could not parse, and the text mentions the command. Refuse rather than allow: this file's
# whole history is bypasses that looked like "no invocation found".
if [ -z "$result" ] && [ "$UNTERMINATED" = 1 ] \
   && printf '%s' "$command" | grep -qE '\bgh\b' \
   && printf '%s' "$command" | grep -qE '\bmerge\b'; then
  deny "BLOCKED: this command has an unterminated quote, so it cannot be parsed to tell whether it merges a PR. Rephrase it with balanced quotes."
fi

[ -n "$result" ] || exit 0
pr_number=$(printf '%s' "$result" | cut -f1)
repo_flag=$(printf '%s' "$result" | cut -f2)

# No resolvable positional. `gh pr merge --squash` with no number merges the CURRENT BRANCH,
# which this gate cannot verify either a review or an approval for, so it asks for the explicit
# form rather than adopting a number found somewhere in the text — which is exactly how
# `-b "closes 1234"` came to satisfy the review requirement with an unrelated PR.
if [ -z "$pr_number" ]; then
  deny "BLOCKED: gh pr merge requires an explicit PR number for approval verification. Use 'gh pr merge <N> --squash --delete-branch'. To approve, USER should type in the prompt: ! mkdir -p ~/.claude/merge-approvals && touch ~/.claude/merge-approvals/<N>"
fi

approval_dir="$HOME/.claude/merge-approvals"

# ── Conflict pre-check ────────────────────────────────────────────────────────
# Checked BEFORE the approval token, so a refused merge never burns USER's
# single-use token and he is not told to approve something that cannot merge yet.
#
# NOTE (2026-07-30): the review-freshness gate that used to live here — require a code-review
# marker for the PR's CURRENT HEAD (#1201, claude-config f03bbc1, 2026-07-29) — was removed. It
# forced a fresh, paid cross-model review before every merge of any branch that got a commit
# after PR-create, turning normal iteration into an unbounded re-review loop. The create-time
# review still runs (bash-post-hook.sh on `gh pr create`); merging no longer blocks on it.

# `$repo_flag` comes from analyze()'s argv walk, not from a grep over flattened text — a body
# that quotes the flag (`-b "mirrors --repo owner/other"`) is one token and cannot win it.
# TIMED OUT where a timeout is available: this runs inside a PreToolUse hook, so a hung network
# call would block the Bash tool with no output; macOS ships no `timeout`, hence the guard. A
# failed or empty lookup leaves mergeable="" and simply skips the conflict pre-check below.
if command -v timeout >/dev/null 2>&1; then
  pr_json=$(timeout 15 gh pr view "$pr_number" ${repo_flag:+--repo "$repo_flag"} \
            --json mergeable 2>/dev/null) || pr_json=""
else
  pr_json=$(gh pr view "$pr_number" ${repo_flag:+--repo "$repo_flag"} \
            --json mergeable 2>/dev/null) || pr_json=""
fi

# Refuse a merge git cannot perform, BEFORE touching the token. The token is consumed on
# allow, not on success, so a merge that gh then rejects for conflicts spends an approval on
# nothing and costs USER a second `! touch`. That happened on PR #18 (2026-07-29).
# CONFLICTING only — `mergeable` is UNKNOWN while GitHub is still computing the merge commit,
# and denying on that would be a fresh false block on a perfectly mergeable PR.
mergeable=$(printf '%s' "$pr_json" | jq -r '.mergeable // ""' 2>/dev/null || true)
if [ "$mergeable" = "CONFLICTING" ]; then
  deny "BLOCKED: PR #$pr_number has merge conflicts with its base, so gh would reject the merge and the approval token would be spent on a merge that never happened. Rebase the branch onto its base, force-push, re-review the new HEAD, then merge. Your token for #$pr_number is untouched."
fi

# Check for the approval token.
token="$approval_dir/$pr_number"

if [ ! -f "$token" ]; then
  deny "BLOCKED: PR #$pr_number is not approved for merge. To approve, USER must type in the prompt (the ! prefix bypasses Bash-tool hooks so Claude cannot self-approve): ! mkdir -p ~/.claude/merge-approvals && touch ~/.claude/merge-approvals/$pr_number — then ask Claude to merge. Approval is single-use; the hook deletes the token after consuming."
fi

# Token exists. Consume it (single-use), audit, allow.
mkdir -p "$approval_dir"
audit_log="$approval_dir/audit.log"
cmd_excerpt=$(echo "$command" | head -c 200 | tr '\n' ' ')
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) PR #$pr_number approved + consumed (cmd: $cmd_excerpt)" >> "$audit_log"
rm -f "$token"

exit 0
