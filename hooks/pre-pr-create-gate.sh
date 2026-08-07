#!/bin/bash
# PreToolUse hook for Bash — blocks `gh pr create` unless a fresh
# pr-gate sentinel exists at tmp/pr-gate.green whose first line matches
# the current HEAD SHA of the effective working directory.
#
# Companion to scripts/pr-gate.sh (mechanical pre-PR checklist runner).
#
# Clear the block by running `bash scripts/pr-gate.sh` from the repo.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Only gate gh pr create — anchored at command start (or after `cd … &&` / `;`)
# to avoid matching the literal string inside quoted args (e.g. `gh issue create --body "…gh pr create…"`).
if ! echo "$COMMAND" | grep -qE '(^|&&[[:space:]]*|;[[:space:]]*)gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
  exit 0
fi

block() {
  local reason="$1"
  local msg
  printf -v msg '[STATE]: pr-gate not green — %s\n  Action: Run `bash scripts/pr-gate.sh` from the branch worktree and fix the failing checks\n  Reference: scripts/pr-gate.sh' "$reason"
  jq -n --arg msg "$msg" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $msg}}'
  exit 0
}

# Determine effective cwd (command may start with `cd /path && ...`)
EFFECTIVE_CWD="$CWD"
if echo "$COMMAND" | grep -qE '^cd\s+'; then
  # Strip surrounding quotes with two explicit substitutions. This was one
  # bracket expression, `sed 's/["\x27]//g'`, intending `\x27` as an escape for
  # a single quote. BSD sed has no such escape — inside a bracket expression it
  # reads as the literal characters x, 2, 7 — so the class was ["x27] and this
  # deleted every ", x, 2 and 7 IN THE PATH ITSELF. A worktree at
  # .../dev-reference-review-base-fix parsed to .../dev-reference-review-base-fi,
  # failed `[ -d ]`, and fell through to the session cwd below, gating a
  # dev-reference PR against an unrelated example-app worktree (#1191). `fix/…`
  # is one of our two standard worktree prefixes, so this hit constantly.
  # It also never stripped single quotes at all, which was the original intent.
  PARSED_DIR=$(echo "$COMMAND" | sed -n 's/^cd \([^ &;]*\).*/\1/p' | sed -e 's/"//g' -e "s/'//g")
  if [ -n "$PARSED_DIR" ]; then
    [[ "$PARSED_DIR" != /* ]] && PARSED_DIR="$CWD/$PARSED_DIR"
    if [ -d "$PARSED_DIR" ]; then
      EFFECTIVE_CWD="$PARSED_DIR"
    else
      # A leading `cd` we cannot resolve means we do not know which repo this
      # PR targets — so DON'T GATE. Exit 0 and let it through.
      #
      # Two wrong answers were tried here first, both worse:
      #   1. Fall back to the session cwd (the original #1191 bug) — evaluates
      #      a DIFFERENT repo and denies with a confident, specific, irrelevant
      #      message naming another session's worktree.
      #   2. Deny on parse failure (the first pass at fixing #1191) — turned a
      #      silent wrong answer into a hard, unclearable block. Line 41 does
      #      pure TEXT extraction with no shell expansion, so `cd ~/Projects/x`,
      #      `cd "$WORKTREE"` and paths containing spaces all fail to resolve
      #      and were denied — including in repos that ship no scripts/pr-gate.sh
      #      and that this gate explicitly promises not to touch. The deny text
      #      told you to run a script that does not exist there, and re-running
      #      the identical command looped forever. Caught by the cross-model
      #      review on PR #13 (B1/B2) and confirmed against the live hook.
      #
      # This gate is a behavioral nudge, not a security boundary, so failing
      # OPEN on "I can't tell" is correct. It does mean an unresolvable `cd`
      # slips the gate; that is the deliberate trade and it self-heals on the
      # next PR from a resolvable path. The loud signal for a mangled path
      # lives in bash-post-hook.sh's CWD_PARSE_WARNING, which can afford to be
      # noisy because PostToolUse cannot block anything.
      exit 0
    fi
  fi
fi

REPO_ROOT=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  exit 0  # not a git repo — let it through
fi

# Cross-repo target. `gh pr create --repo X` names the repo the PR lands in, which
# may not be the effective cwd's repo. The cwd's worktree/sentinel state says nothing
# about X's readiness, so gating the cwd repo here is simply wrong — it blocked a
# legitimate dev-reference PR against a stale example-app sentinel because the command
# ran `--repo dev-reference` from an example-app session cwd (#1198 / #1201 Tier 1).
# This gate is a behavioral nudge, not a security boundary, so when --repo names a
# DIFFERENT repo than the cwd, stand down. The `cd <worktree> && gh pr create` idiom
# (parsed above) remains the supported way to make the gate apply to a worktree.
TARGET_SLUG=$(echo "$COMMAND" | grep -oE -- '--repo[ =]+[^ ]+' | head -1 | sed -E 's/^--repo[ =]+//')
if [ -n "$TARGET_SLUG" ]; then
  TARGET_NAME=$(basename "$TARGET_SLUG" | sed 's/\.git$//')
  # Compare on repo name resolved from the remote — worktree dir names carry a
  # -<desc> suffix, so the path basename would spuriously differ. Fall back to the
  # path basename when there's no remote (e.g. test fixtures).
  CWD_REPO_NAME=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git remote get-url origin 2>/dev/null | sed -E 's#.*/##; s#\.git$##')
  [ -z "$CWD_REPO_NAME" ] && CWD_REPO_NAME=$(basename "$REPO_ROOT")
  if [ -n "$TARGET_NAME" ] && [ "$TARGET_NAME" != "$CWD_REPO_NAME" ]; then
    exit 0
  fi
fi

# Only gate repos that ship a pr-gate.sh script
if [ ! -f "$REPO_ROOT/scripts/pr-gate.sh" ]; then
  exit 0
fi

# Gate the worktree of the branch actually being PR'd. `gh pr create` pushes the
# current branch of the effective cwd; find the worktree holding that branch and
# check ITS sentinel. Running from the main checkout is fine as long as the branch's
# own worktree has a fresh sentinel.
#
# The old version scanned EVERY worktree and (a) allowed the PR if ANY of them had a
# fresh sentinel — so an unrelated session's green sentinel passed this branch — and
# (b) built the denial from whichever worktree it happened to scan LAST, so a PR from
# a fresh sentinel-less worktree got a message naming another session's stale sentinel
# in a repo the user wasn't touching (#1198 defect 2). Scoping to the branch's own
# worktree fixes both the decision and the message.
TARGET_BRANCH=$(cd "$EFFECTIVE_CWD" 2>/dev/null && git branch --show-current 2>/dev/null)
TARGET_WT="$REPO_ROOT"
if [ -n "$TARGET_BRANCH" ]; then
  wt=$(cd "$REPO_ROOT" && git worktree list --porcelain 2>/dev/null \
        | awk -v b="refs/heads/$TARGET_BRANCH" '/^worktree /{w=$2} $0=="branch "b{print w}')
  [ -n "$wt" ] && TARGET_WT="$wt"
fi

sentinel="$TARGET_WT/tmp/pr-gate.green"
head_sha=$(cd "$TARGET_WT" && git rev-parse HEAD 2>/dev/null)
if [ -f "$sentinel" ]; then
  sentinel_sha=$(head -n 1 "$sentinel" 2>/dev/null)
  if [ -n "$sentinel_sha" ] && [ "$sentinel_sha" = "$head_sha" ]; then
    exit 0
  fi
  block "Sentinel in $sentinel ($sentinel_sha) != branch ${TARGET_BRANCH:-?} HEAD ($head_sha) — stale after new commits. Re-run from $TARGET_WT."
else
  block "No pr-gate sentinel for branch ${TARGET_BRANCH:-?} — its worktree $TARGET_WT has no tmp/pr-gate.green."
fi
