#!/bin/bash
# WorktreeCreate hook — fires when Claude creates worktrees internally
# (e.g., isolation: "worktree" for sub-agents, EnterWorktree tool).
# Copies environment files and installs dependencies.

INPUT=$(cat)
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$WORKTREE_PATH" ]; then
  echo "WORKTREE_SETUP_COMPLETE: no path provided, skipping"
  exit 0
fi

if [ ! -d "$WORKTREE_PATH" ]; then
  echo "WORKTREE_SETUP_COMPLETE: path $WORKTREE_PATH does not exist yet, skipping"
  exit 0
fi

# Find the main repo root
MAIN_REPO=""
if [ -n "$CWD" ]; then
  MAIN_REPO=$(cd "$CWD" && git rev-parse --show-toplevel 2>/dev/null)
fi

if [ -n "$MAIN_REPO" ]; then
  # 1Password-migrated repos commit a `.env.tpl` and resolve secrets via `op run` at
  # runtime. For those, copying `.env` is HARMFUL: a local `.env` file SHADOWS the
  # op-injected process env (verified precedence: file > process > cloud), so a stale
  # copied `.env` silently overrides 1Password. Skip the copy when `.env.tpl` exists —
  # the template arrives via git instead. Non-migrated repos keep the old copy behavior.
  if [ -f "$MAIN_REPO/.env.tpl" ]; then
    echo "WORKTREE_SETUP: $MAIN_REPO uses 1Password (.env.tpl present) — skipping .env copy; run via 'op run' / 'npm run dev'."
  else
    [ -f "$MAIN_REPO/.env" ] && cp "$MAIN_REPO/.env" "$WORKTREE_PATH/.env" 2>/dev/null
  fi
  [ -d "$MAIN_REPO/.vercel" ] && cp -r "$MAIN_REPO/.vercel" "$WORKTREE_PATH/.vercel" 2>/dev/null
fi

if [ -f "$WORKTREE_PATH/package.json" ]; then
  (cd "$WORKTREE_PATH" && npm install --silent 2>/dev/null)
fi

echo "WORKTREE_SETUP_COMPLETE: Environment bootstrapped at $WORKTREE_PATH"
exit 0
