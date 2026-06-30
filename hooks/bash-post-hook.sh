#!/bin/bash
# Consolidated PostToolUse hook for Bash commands.
# Detects key workflow events and signals Claude to spawn autonomous agents.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# ─── Effective CWD Helper ────────────────────────────────────────────────────
# Commands often start with `cd /path && ...`. Extract that path as the
# effective working directory so downstream logic runs in the right repo.
EFFECTIVE_CWD="$CWD"
if echo "$COMMAND" | grep -qE '^cd\s+'; then
  PARSED_DIR=$(echo "$COMMAND" | sed -n 's/^cd \([^ &;]*\).*/\1/p')
  if [ -n "$PARSED_DIR" ]; then
    # Resolve relative paths against CWD
    if [[ "$PARSED_DIR" != /* ]]; then
      PARSED_DIR="$CWD/$PARSED_DIR"
    fi
    # Strip trailing quotes if any
    PARSED_DIR=$(echo "$PARSED_DIR" | sed 's/["\x27]//g')
    [ -d "$PARSED_DIR" ] && EFFECTIVE_CWD="$PARSED_DIR"
  fi
fi

# ─── Worktree Setup ───────────────────────────────────────────────────────────
# After `git worktree add`, copy .env + .vercel and run npm install.
if echo "$COMMAND" | grep -qE 'git\s+worktree\s+add\s+'; then
  # Extract worktree path — first non-flag arg after `add`
  WORKTREE_PATH=$(echo "$COMMAND" | sed -n 's/.*git worktree add \([^ -][^ ]*\).*/\1/p')

  # Resolve relative path
  if [ -n "$WORKTREE_PATH" ] && [[ "$WORKTREE_PATH" != /* ]]; then
    WORKTREE_PATH="$CWD/$WORKTREE_PATH"
  fi

  # Find the main repo root
  MAIN_REPO=""
  if [ -n "$CWD" ]; then
    MAIN_REPO=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null)
  fi

  if [ -d "$WORKTREE_PATH" ] && [ -n "$MAIN_REPO" ]; then
    SETUP_LOG=""

    # Copy .env
    if [ -f "$MAIN_REPO/.env" ]; then
      cp "$MAIN_REPO/.env" "$WORKTREE_PATH/.env" 2>/dev/null && SETUP_LOG="$SETUP_LOG .env copied."
    fi

    # Copy .vercel
    if [ -d "$MAIN_REPO/.vercel" ]; then
      cp -r "$MAIN_REPO/.vercel" "$WORKTREE_PATH/.vercel" 2>/dev/null && SETUP_LOG="$SETUP_LOG .vercel/ copied."
    fi

    # Install dependencies
    if [ -f "$WORKTREE_PATH/package.json" ]; then
      (cd "$WORKTREE_PATH" && npm install --silent 2>/dev/null) && SETUP_LOG="$SETUP_LOG npm install complete."
    fi

    # Kill zombie processes on dev port
    lsof -ti :8765 2>/dev/null | xargs kill -9 2>/dev/null

    echo "WORKTREE_SETUP_COMPLETE: Worktree ready at $WORKTREE_PATH.$SETUP_LOG Port 8765 cleared."
  fi
fi

# ─── Post-Merge Signal ────────────────────────────────────────────────────────
# After `gh pr merge`, create a lock file that blocks worktree removal until
# session capture is done, then signal Claude.
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge'; then
  PR_REF=$(echo "$COMMAND" | grep -oE '[0-9]+' | head -1)

  # Find the worktree path (if we're in one)
  REPO_ROOT=$(cd "$EFFECTIVE_CWD" && git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$REPO_ROOT" ]; then
    LOCK_FILE="/tmp/post-merge-capture-pending-$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1).lock"
    echo "PR #${PR_REF:-unknown} merged from $REPO_ROOT. Session capture required." > "$LOCK_FILE"
  fi

  echo "POST_MERGE_HOOK: PR #${PR_REF:-unknown} was just merged. Run /session-capture first (worktree removal is blocked until capture completes), then run post-merge cleanup as a background agent."
fi

# ─── PR Create Signal ─────────────────────────────────────────────────────────
# After `gh pr create`, run cross-model code review (Claude + Gemini) in background.
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+create'; then
  # Get PR number from the repo where the PR was created (may differ from session CWD)
  PR_NUM=$(cd "$EFFECTIVE_CWD" && gh pr view --json number -q .number 2>/dev/null)

  if [ -n "$PR_NUM" ] && [ -n "$EFFECTIVE_CWD" ]; then
    REVIEW_SCRIPT="$HOME/Projects/dev-reference/agents/run-code-review.sh"
    COVERAGE_SCRIPT="$HOME/Projects/dev-reference/agents/run-test-coverage-review.sh"

    # Code review (Claude + Gemini, runtime/structural lens)
    if [ -x "$REVIEW_SCRIPT" ]; then
      (cd "$EFFECTIVE_CWD" && "$REVIEW_SCRIPT" --pr "$PR_NUM" > /tmp/code-review-pr-${PR_NUM}.log 2>&1) &
    fi

    # Test coverage review (Claude + Gemini, unit/e2e lens)
    if [ -x "$COVERAGE_SCRIPT" ]; then
      (cd "$EFFECTIVE_CWD" && "$COVERAGE_SCRIPT" --pr "$PR_NUM" > /tmp/test-coverage-pr-${PR_NUM}.log 2>&1) &
    fi

    echo "PR_CREATE_HOOK: PR #$PR_NUM created in $(basename "$EFFECTIVE_CWD"). Code review + test coverage review running in background — results will post as PR comments."
  else
    echo "PR_CREATE_HOOK: A PR was just created but could not extract PR number. EFFECTIVE_CWD=$EFFECTIVE_CWD"
  fi
fi

exit 0
