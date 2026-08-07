#!/bin/bash
# Consolidated PostToolUse hook for Bash commands.
# Detects key workflow events and signals Claude to spawn autonomous agents.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# Resolve per-repo product facts (Supabase e2e ref, dev port) instead of
# assuming example-app. A missing resolver degrades to "skip the example-app-
# specific setup", never to the old hardcoded behavior (example-app/#1201).
RESOLVER="$(dirname "${BASH_SOURCE[0]}")/resolve-product.sh"
[ -f "$RESOLVER" ] && . "$RESOLVER"

# ─── Effective CWD Helper ────────────────────────────────────────────────────
# Commands often start with `cd /path && ...`. Extract that path as the
# effective working directory so downstream logic runs in the right repo.
EFFECTIVE_CWD="$CWD"
if echo "$COMMAND" | grep -qE '^cd\s+'; then
  PARSED_DIR=$(echo "$COMMAND" | sed -n 's/^cd \([^ &;]*\).*/\1/p')
  if [ -n "$PARSED_DIR" ]; then
    # Strip surrounding quotes. This was `sed 's/["\x27]//g'`, intending `\x27`
    # as an escape for a single quote — BSD sed has no such escape, so inside a
    # bracket expression it read as the literal characters x, 2, 7 and the class
    # became ["x27], deleting every ", x, 2 and 7 FROM THE PATH (#1191). The
    # same line was in pre-pr-create-gate.sh; both are fixed together.
    #
    # The consequence here was worse than in the gate, because it is silent:
    # a mangled path fails `[ -d ]`, EFFECTIVE_CWD stays the SESSION's cwd, and
    # every downstream step — PR lookup, head-branch resolution, REVIEW_CWD —
    # runs against the wrong repo. Both reviews then diff a checkout whose HEAD
    # already matches its base, print "No diff found. Nothing to review.", and
    # exit 0. The PR gets NO review and nothing anywhere reports a failure.
    # Observed live on dev-reference#3 and claude-config#13, both opened from
    # worktrees whose names end in `-fix`.
    PARSED_DIR=$(echo "$PARSED_DIR" | sed -e 's/"//g' -e "s/'//g")

    # Resolve relative paths against CWD — AFTER unquoting, not before. The
    # original order tested `$PARSED_DIR != /*` while the leading quote was
    # still attached, so a quoted ABSOLUTE path (`cd "/Users/…"`) never looked
    # absolute and got rewritten to `$CWD//Users/…`. Independent of the x/2/7
    # bug and it survived the first pass of that fix; the test caught it.
    if [[ "$PARSED_DIR" != /* ]]; then
      PARSED_DIR="$CWD/$PARSED_DIR"
    fi

    if [ -d "$PARSED_DIR" ]; then
      EFFECTIVE_CWD="$PARSED_DIR"
    else
      # PostToolUse cannot block, but it must not fail silently either — a
      # silent fallback here is indistinguishable from a review that ran and
      # found nothing.
      #
      # Scoped to commands that actually CONSUME EFFECTIVE_CWD. This helper
      # runs for every Bash command matching `^cd\s+`, ahead of every branch
      # guard, so an unscoped warning fired on `cd "$WT" && git status` and
      # asserted that a review was evaluating the wrong repo when no review
      # ran at all. PostToolUse stdout is injected into context, so that reads
      # as a recurring review failure. (PR #13 cross-model review, W1.)
      case "$COMMAND" in
        *"gh pr create"*|*"gh pr merge"*|*"vercel deploy"*)
          echo "CWD_PARSE_WARNING: this command cd's into [$PARSED_DIR], which does not resolve. Falling back to the session cwd ($CWD) — the PR review / gate below is evaluating THAT repo, not the one you targeted. If a review reports 'No diff found', this is why." ;;
      esac
    fi
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

    # Copy .env and .env.test
    if [ -f "$MAIN_REPO/.env" ]; then
      cp "$MAIN_REPO/.env" "$WORKTREE_PATH/.env" 2>/dev/null && SETUP_LOG="$SETUP_LOG .env copied."
    fi
    if [ -f "$MAIN_REPO/.env.test" ]; then
      cp "$MAIN_REPO/.env.test" "$WORKTREE_PATH/.env.test" 2>/dev/null && SETUP_LOG="$SETUP_LOG .env.test copied."
    fi

    # Copy .vercel
    if [ -d "$MAIN_REPO/.vercel" ]; then
      cp -r "$MAIN_REPO/.vercel" "$WORKTREE_PATH/.vercel" 2>/dev/null && SETUP_LOG="$SETUP_LOG .vercel/ copied."
    fi

    # Install dependencies — pnpm for repos with a pnpm-workspace.yaml (AS-9 rebuild
    # stack), npm otherwise. Conditional so npm and pnpm worktrees coexist correctly.
    if [ -f "$WORKTREE_PATH/package.json" ]; then
      if [ -f "$WORKTREE_PATH/pnpm-workspace.yaml" ]; then
        (cd "$WORKTREE_PATH" && pnpm install --silent 2>/dev/null) && SETUP_LOG="$SETUP_LOG pnpm install complete."
      else
        (cd "$WORKTREE_PATH" && npm install --silent 2>/dev/null) && SETUP_LOG="$SETUP_LOG npm install complete."
      fi
    fi

    # Link Supabase CLI to the worktree's declared e2e branch. Only a repo that
    # declares supabase_e2e_ref is linked — a foreign worktree (no declaration)
    # is skipped instead of being linked to example-app's e2e DB (example-app/#1201).
    E2E_REF=""
    if command -v resolve_product_field >/dev/null 2>&1; then
      E2E_REF=$(cd "$WORKTREE_PATH" 2>/dev/null && resolve_product_field supabase_e2e_ref 2>/dev/null) || E2E_REF=""
    fi
    if [ -n "$E2E_REF" ] && [ -d "$WORKTREE_PATH/supabase/migrations" ]; then
      supabase link --project-ref "$E2E_REF" --workdir "$WORKTREE_PATH" > /dev/null 2>&1 \
        && SETUP_LOG="$SETUP_LOG Supabase linked to e2e branch."
    fi

    # Clear the worktree's declared dev port. Only a repo that declares dev_port
    # gets a port freed — no longer kills example-app's 8765 on every worktree-add
    # regardless of repo (example-app/#1201).
    PORT_MSG=""
    DEV_PORT=""
    if command -v resolve_product_field >/dev/null 2>&1; then
      DEV_PORT=$(cd "$WORKTREE_PATH" 2>/dev/null && resolve_product_field dev_port 2>/dev/null) || DEV_PORT=""
    fi
    if [ -n "$DEV_PORT" ]; then
      lsof -ti :"$DEV_PORT" 2>/dev/null | xargs kill -9 2>/dev/null
      PORT_MSG=" Port $DEV_PORT cleared."
    fi

    echo "WORKTREE_SETUP_COMPLETE: Worktree ready at $WORKTREE_PATH.$SETUP_LOG$PORT_MSG"
  fi
fi

# ─── Post-Merge Signal ────────────────────────────────────────────────────────
# After `gh pr merge`, create a lock file that blocks worktree removal until
# session capture is done, then signal Claude.
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge'; then
  PR_REF=$(echo "$COMMAND" | grep -oE '[0-9]+' | head -1)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

  # Find the worktree path (if we're in one)
  REPO_ROOT=$(cd "$EFFECTIVE_CWD" && git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$REPO_ROOT" ]; then
    LOCK_FILE="/tmp/post-merge-capture-pending-$(echo "$REPO_ROOT" | md5 -q 2>/dev/null || echo "$REPO_ROOT" | md5sum 2>/dev/null | cut -d' ' -f1).lock"
    # Stamp the merging session's id into the lock. The recurring soft-nag in
    # post-merge-gate.sh fires ONLY for a Bash command from this same session,
    # so a concurrent session sharing $REPO_ROOT is never interrupted. The
    # worktree-removal hard-block below stays session-agnostic (data-safety
    # guard, already path-scoped). (evidence: concurrent sessions in the main
    # checkout all got nagged after one merged — 2026-08-06.)
    echo "PR #${PR_REF:-unknown} merged from $REPO_ROOT. Session capture required. session:${SESSION_ID}" > "$LOCK_FILE"
  fi

  echo "POST_MERGE_HOOK: PR #${PR_REF:-unknown} was just merged. Run /session-capture first (worktree removal is blocked until capture completes), then run post-merge cleanup as a background agent."
fi

# ─── PR Create Signal ─────────────────────────────────────────────────────────
# After `gh pr create`, run cross-model code review (Claude + Gemini) in background.
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+create'; then
  # The created PR's URL is in this command's OWN stdout, e.g.
  # https://github.com/owner/repo/pull/1070. It is cwd-independent AND it carries the
  # owner/repo — keep BOTH. The old code kept only the number and resolved everything
  # else against EFFECTIVE_CWD, so `gh pr create --repo other/repo` from this session's
  # cwd reviewed the WRONG repo: gh pr view <n> ran against the session repo, found no
  # such PR, REVIEW_CWD stayed the session checkout, and both review scripts hit their
  # "No diff found" early return — a silent no-op indistinguishable from a review still
  # in flight (#1198 defect 1).
  TOOL_STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // ""')
  PR_URL=$(echo "$TOOL_STDOUT" | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)
  PR_NUM=$(echo "$PR_URL" | grep -oE '[0-9]+$')
  PR_REPO=$(echo "$PR_URL" | sed -nE 's|https://github\.com/([^/]+/[^/]+)/pull/[0-9]+|\1|p')
  if [ -z "$PR_NUM" ]; then
    # No URL (rare). Fall back to `gh pr view` against EFFECTIVE_CWD's current branch —
    # by construction that targets EFFECTIVE_CWD's OWN repo, so PR_REPO stays empty and
    # resolution below uses the session checkout, which is correct for that path (#1071).
    PR_NUM=$(cd "$EFFECTIVE_CWD" && gh pr view --json number -q .number 2>/dev/null)
  fi

  # Override seams for tests (same convention as BASH_POST_HOOK / GH_REPO): point the
  # repo-checkout base and the review commands at fixtures so the resolution logic can
  # be exercised without launching real reviews.
  PROJECTS_DIR="${POST_HOOK_PROJECTS_DIR:-$HOME/Projects}"
  REVIEW_SCRIPT="${POST_HOOK_REVIEW_SCRIPT:-$HOME/Projects/dev-reference/agents/run-code-review.sh}"
  COVERAGE_SCRIPT="${POST_HOOK_COVERAGE_SCRIPT:-$HOME/Projects/dev-reference/agents/run-test-coverage-review.sh}"

  if [ -z "$PR_NUM" ]; then
    echo "PR_CREATE_HOOK: A PR was just created but could not extract PR number. EFFECTIVE_CWD=$EFFECTIVE_CWD. Recovery: cd to the branch's worktree and run dev-reference/agents/run-code-review.sh --pr <N> and run-test-coverage-review.sh --pr <N> manually."
  else
    # Resolve the checkout for the PR's OWN repo. Our repos live at <PROJECTS_DIR>/<name>.
    # When PR_REPO is empty (the gh pr view fallback) the PR is in EFFECTIVE_CWD's repo.
    BASE_CHECKOUT=""
    if [ -n "$PR_REPO" ]; then
      cand="$PROJECTS_DIR/$(basename "$PR_REPO")"
      if [ -e "$cand/.git" ]; then
        BASE_CHECKOUT="$cand"
      else
        # Known repo, no local checkout — do NOT silently review the session repo's
        # (empty) diff and report success. Say so loudly (#1198 defect 1).
        echo "PR_CREATE_HOOK: PR #$PR_NUM created in $PR_REPO, but no local checkout at $cand — no review run. Recovery: from a worktree on the PR's head branch, run dev-reference/agents/run-code-review.sh --pr $PR_NUM and run-test-coverage-review.sh --pr $PR_NUM."
      fi
    else
      BASE_CHECKOUT=$(cd "$EFFECTIVE_CWD" && git rev-parse --show-toplevel 2>/dev/null)
    fi

    if [ -n "$BASE_CHECKOUT" ]; then
      # The review scripts diff origin/<default>...HEAD against their cwd, so cwd must be
      # a checkout whose HEAD IS the PR's head branch. Find the worktree holding it within
      # the target repo; fall back to the base checkout otherwise.
      REVIEW_CWD="$BASE_CHECKOUT"
      HEAD_BRANCH=$(cd "$EFFECTIVE_CWD" 2>/dev/null && gh pr view "$PR_NUM" ${PR_REPO:+--repo "$PR_REPO"} --json headRefName -q .headRefName 2>/dev/null)
      if [ -n "$HEAD_BRANCH" ]; then
        WT=$(cd "$BASE_CHECKOUT" && git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$HEAD_BRANCH" '/^worktree /{wt=$2} $0=="branch "b{print wt}')
        [ -n "$WT" ] && REVIEW_CWD="$WT"
      fi

      # Code review (Claude + Gemini, runtime/structural lens)
      if [ -x "$REVIEW_SCRIPT" ]; then
        (cd "$REVIEW_CWD" && "$REVIEW_SCRIPT" --pr "$PR_NUM" > /tmp/code-review-pr-${PR_NUM}.log 2>&1) &
      fi

      # Test coverage review (Claude + Gemini, unit/e2e lens)
      if [ -x "$COVERAGE_SCRIPT" ]; then
        (cd "$REVIEW_CWD" && "$COVERAGE_SCRIPT" --pr "$PR_NUM" > /tmp/test-coverage-pr-${PR_NUM}.log 2>&1) &
      fi

      echo "PR_CREATE_HOOK: PR #$PR_NUM created${PR_REPO:+ in $PR_REPO}. Reviewing from $(basename "$REVIEW_CWD"). Code review + test coverage review running in background — results will post as PR comments."
    fi
  fi
fi

# ─── Post-Test-Failure Instrument-First Reminder ──────────────────────────────
# When a test runner exits with failures, inject a reminder to instrument first
# (add console.log / diagnostics) before theorizing or editing code.
# Target: lift instrument-first compliance from ~30% to 100% (memory telemetry).
if echo "$COMMAND" | grep -qE '(npm\s+(test|run\s+test)|npx\s+(playwright|vitest)|^vitest|^playwright)'; then
  TOOL_STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // ""')
  TOOL_STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // ""')
  TOOL_OUTPUT="$TOOL_STDOUT"$'\n'"$TOOL_STDERR"

  # Failure indicators: non-zero failure count, vitest FAIL marker, playwright fail glyph
  if echo "$TOOL_OUTPUT" | grep -qE '([1-9][0-9]* failed|^FAIL |✘|Test Failed|Tests:.*failed)'; then
    echo "INSTRUMENT_FIRST_REMINDER: A test just failed. Before editing code or theorizing about the cause, capture diagnostic output — inject console.log / page.evaluate / curl / SELECT count / inspect the actual state. Read the output, then form a hypothesis from evidence. (Memory telemetry: instrument-first is the #1 compliance violation — 30% baseline, target 100%. Two-cycle rule: if you've already tried 2 hypotheses on this same problem, stop and run /second-opinion instead of guessing a third.)"
  fi
fi

# ─── Walk Preflight Gate (backstop) ───────────────────────────────────────────
# After a preview `vercel deploy` NOT routed through scripts/deploy-walk.mjs (which
# gates itself), route-smoke the deploy: every routed api/_src handler must be
# REGISTERED (non-404) on the preview before it's handed to USER. Born of #1036 —
# an M1 walk was handed over with six 404ing endpoints because their api/**/*.js
# registration stubs were never committed; the human caught it at Leg 1 (backwards).
# The wrapper is the primary guard; this catches a bare `vercel deploy` done any other
# way. Only fires for a FOREGROUND deploy (URL present in the tool output) — background
# deploys are covered by the wrapper.
if echo "$COMMAND" | grep -qE 'vercel\s+deploy' && ! echo "$COMMAND" | grep -qE 'deploy-walk|--prod'; then
  DEPLOY_OUT="$(echo "$INPUT" | jq -r '.tool_response.stdout // ""')"$'\n'"$(echo "$INPUT" | jq -r '.tool_response.stderr // ""')"
  PREVIEW_URL=$(echo "$DEPLOY_OUT" | grep -oE 'https://[a-z0-9-]+\.vercel\.app' | tail -1)
  REPO_ROOT=$(cd "$EFFECTIVE_CWD" && git rev-parse --show-toplevel 2>/dev/null)
  PF="$REPO_ROOT/scripts/walk-preflight.mjs"
  if [ -n "$PREVIEW_URL" ] && [ -f "$PF" ]; then
    PF_OUT=$(node "$PF" "$PREVIEW_URL" 2>&1)
    if [ $? -ne 0 ]; then
      DEAD=$(echo "$PF_OUT" | grep -E 'DEAD' | awk '{print $NF}' | tr '\n' ' ')
      echo "WALK_PREFLIGHT_GATE active: $PREVIEW_URL has DEAD route(s): $DEAD — NOT walk-ready. Do NOT hand this preview to USER. Fix the dead route(s) (usually a missing committed api/**/*.js registration stub — run scripts/build-api-rebuild.mjs and commit the new stub), redeploy, re-check. (#1036)"
    else
      echo "WALK_PREFLIGHT_OK: $PREVIEW_URL — all routes registered, walk-ready."
    fi
  fi
fi

exit 0
