#!/bin/bash
# PreToolUse hook — /review-tests mechanical gate enforcer.
#
# When /tmp/review-tests-pending-<worktree_hash>.lock exists AND cumulative_tests
# in that lock is >= threshold, blocks:
#   • Write/Edit on implementation source files (anything not in the allow list)
#   • Bash commands that run the test suite (vitest / npm test / playwright /
#     docker compose ... test)
#
# Allow-list for Write/Edit (never blocked):
#   • Test files (*/tests/*, */e2e/*)
#   • Tmp / briefs / memory / .claude / dev-reference / claude-config /
#     claude-skills — everything the reviewer legitimately needs to edit
#
# Lock is created by test-review-gate-post.sh and cleared by /review-tests
# Stage 5 on verdict=PASS. Manual override: rm the lock file.

set -e

hook_input=$(cat)
tool_name=$(echo "$hook_input" | jq -r '.tool_name // ""')
cwd=$(echo "$hook_input" | jq -r '.cwd // ""')
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // ""')

# Resolve the worktree for this operation so each worktree has its own lock.
# Parallel sessions all share the same session cwd (main checkout), so keying
# by cwd produces one shared lock; keying by worktree root isolates them.
case "$tool_name" in
  Write|Edit)
    [ -n "$file_path" ] || exit 0
    worktree=$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
    ;;
  Bash)
    worktree=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
    ;;
  *)
    exit 0
    ;;
esac

worktree_hash=$(echo -n "$worktree" | shasum -a 256 | cut -c1-8)
LOCK="/tmp/review-tests-pending-${worktree_hash}.lock"

[ -f "$LOCK" ] || exit 0

cumulative=$(grep -E '^# cumulative_tests=' "$LOCK" | head -1 | sed -E 's/.*=//')
threshold=$(grep -E '^# threshold=' "$LOCK" | head -1 | sed -E 's/.*=//')
cumulative=${cumulative:-0}
threshold=${threshold:-5}

# Gate only activates at/above threshold. Below threshold the lock is just
# telemetry — no blocking.
[ "$cumulative" -ge "$threshold" ] || exit 0

file_list=$(grep -v '^#' "$LOCK" | awk -F'\t' '{print $1}' | tr '\n' ' ')
deny_reason=$(printf 'REVIEW_TESTS gate active: %s tests across %s file(s) need /review-tests.\nFiles: %s\nLock: %s\n\nRun /review-tests before writing implementation code or running the suite.\nEscape hatch: rm %s (explicit skip, audit trail).' \
  "$cumulative" \
  "$(grep -vc '^#' "$LOCK")" \
  "$file_list" \
  "$LOCK" \
  "$LOCK")

deny() {
  jq -n --arg reason "$deny_reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
  exit 0
}

case "$tool_name" in
  Write|Edit)
    case "$file_path" in
      # Allow-list — never blocked
      */tests/*|*/e2e/*) exit 0 ;;
      */tmp/*) exit 0 ;;
      */example-context/*) exit 0 ;;
      */.claude/*|/Users/*/.claude/*) exit 0 ;;
      */memory/*) exit 0 ;;
      */dev-reference/*) exit 0 ;;
      */claude-config/*|*/claude-skills/*) exit 0 ;;
      "") exit 0 ;;
      # Everything else is an implementation-code path — deny.
      *)
        deny
        ;;
    esac
    ;;
  Bash)
    command=$(echo "$hook_input" | jq -r '.tool_input.command // ""')
    # Patterns that run tests (unit or e2e).
    # Anchored to command start / after && / after ; to avoid matching these
    # strings inside quoted --body args (e.g. `gh pr create --body "... npm test ..."`).
    if echo "$command" | grep -qE '(^|&&[[:space:]]*|;[[:space:]]*)(npx vitest|npm test|npm run test(:|[[:space:]]|$)|playwright test|docker compose run.*test)'; then
      deny
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
