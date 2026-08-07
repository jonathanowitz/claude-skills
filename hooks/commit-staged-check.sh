#!/bin/bash
# PreToolUse hook: Before `git commit`, show staged files and warn about
# unrelated changes. Fires on any Bash command matching `git commit`.

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // ""')
cwd=$(echo "$hook_input" | jq -r '.cwd // empty')

# Resolve the repo's own shared-init list instead of assuming example-app's
# web/*.js files. A repo that doesn't declare shared_init just skips the
# gate below — safe, since the gate is already disabled (example-app/#1201).
RESOLVER="$(dirname "${BASH_SOURCE[0]}")/resolve-product.sh"
[ -f "$RESOLVER" ] && . "$RESOLVER"

# Only fire on git commit commands
echo "$command" | grep -qE '^\s*git\s+commit' || exit 0

# Get the list of staged files
STAGED=$(cd "${cwd:-.}" && git diff --cached --name-only 2>/dev/null)

if [ -z "$STAGED" ]; then
  exit 0
fi

FILE_COUNT=$(echo "$STAGED" | wc -l | tr -d ' ')
FILE_LIST=$(echo "$STAGED" | head -20)

# Always surface the staged file list so Claude (and USER) can review
OUTPUT="COMMIT_STAGED_CHECK: $FILE_COUNT file(s) staged for commit:\n$FILE_LIST"

if [ "$FILE_COUNT" -gt 20 ]; then
  OUTPUT="$OUTPUT\n... and $((FILE_COUNT - 20)) more"
fi

# Shared init files — require full E2E suite pass before committing.
# The suite writes a timestamp to tmp/e2e-pass.txt on success.
# Evidence: 2026-04-01 #381 — auth.js async change broke 48 tests, committed without running suite.
#
# TEMPORARILY DISABLED 2026-04-10: e2e infrastructure is being overhauled
# (#547) and the full suite is too slow to gate every commit. Re-enable
# once the suite is fast + reliable. Staged-file listing and accident-
# pattern checks below remain active.
SHARED_INIT_GATE_DISABLED=true

SHARED_INIT=""
if command -v resolve_product_field >/dev/null 2>&1; then
  SHARED_INIT="$(cd "${cwd:-.}" 2>/dev/null && resolve_product_field shared_init 2>/dev/null)" || SHARED_INIT=""
fi
HAS_SHARED=false
if [ -n "$SHARED_INIT" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    echo "$STAGED" | grep -q "^$f$" && HAS_SHARED=true && break
  done <<< "$SHARED_INIT"
fi

if [ "$HAS_SHARED" = true ] && [ "$SHARED_INIT_GATE_DISABLED" != true ]; then
  PASS_FILE="${cwd:-.}/tmp/e2e-pass.txt"
  if [ ! -f "$PASS_FILE" ]; then
    jq -n --arg files "$FILE_LIST" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ("BLOCKED: Shared init file staged for commit but no E2E suite pass recorded.\nRun the full E2E suite first: PLAYWRIGHT_BASE_URL=http://localhost:8765 npx playwright test\nOn success, create tmp/e2e-pass.txt with the timestamp.\nStaged files:\n" + $files)
      }
    }'
    exit 0
  fi
  # Check staleness — pass must be within last 30 minutes
  PASS_AGE=$(( $(date +%s) - $(stat -f %m "$PASS_FILE" 2>/dev/null || echo 0) ))
  if [ "$PASS_AGE" -gt 1800 ]; then
    jq -n --arg age "$((PASS_AGE / 60))m ago" '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": ("BLOCKED: Shared init file staged but E2E pass is stale (" + $age + "). Re-run the full suite before committing.")
      }
    }'
    exit 0
  fi
fi

# Flag common accident patterns
SUSPECTS=""
echo "$STAGED" | grep -qE '\.env' && SUSPECTS="$SUSPECTS .env file!"
echo "$STAGED" | grep -qE 'package-lock\.json' && [ "$FILE_COUNT" -eq 1 ] && SUSPECTS="$SUSPECTS lone package-lock.json"
echo "$STAGED" | grep -qE 'node_modules/' && SUSPECTS="$SUSPECTS node_modules!"

if [ -n "$SUSPECTS" ]; then
  jq -n --arg reason "COMMIT_STAGED_CHECK: Suspicious staged files detected:$SUSPECTS\nStaged ($FILE_COUNT files):\n$FILE_LIST\nReview before proceeding. Unstage unrelated files with git reset HEAD <file>." '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "ask",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
fi

# No suspects — just surface the file list as info
echo -e "$OUTPUT"
exit 0
