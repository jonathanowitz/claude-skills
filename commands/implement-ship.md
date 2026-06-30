---
description: Stage, commit, push, and create PR (Ship phase of /implement)
argument-hint: [called by /implement — no direct args needed]
allowed-tools: [Read, Grep, Glob, Bash]
user-invocable: false
---

# Implement Ship (Ship Phase)

Final phase: commit all work and create a pull request.

## Step 1: Final Test Suite Run

```bash
npm test -- --run
```

Confirm all tests pass. If any fail, stop — do not ship broken tests.

## Step 2: Review the Diff

Run `git diff --stat` and `git status`. Verify:
- No unintended files (temp files, `.env`, debug scripts)
- No `console.log` debug statements in production code (`grep -r "console.log" web/ --include="*.js" | grep -v node_modules`)
- No commented-out code blocks
- Files match what the plan specified

## Step 2.5: Generate Manual Validation Checklist (mandatory)

Every `/implement` run MUST produce a dedicated markdown validation file before Stage. This is the artifact USER works from when the slice hits a preview URL — not the plan file, not the PR body.

Write to `tmp/validate-slice-<N>-<short-name>.md` in the worktree. Derive the content from the plan file's Behavior Map (both E2E-testable and manual-validation entries). Structure:

```markdown
# Slice <N> — Manual Validation Checklist

- [ ] Done

**PR:** #NNN (branch ..., HEAD ...)
**Plan:** tmp/implement-plan-slice-N.md
**Run against:** preview URL OR local vercel dev

## Setup
- <environment, DevTools state, PostHog spy setup>

## <ID-1> — <one-line title>
- [ ] <step-by-step assertions a human can tick>

## Regression spot-checks (prior slices still work)
- [ ] <a few key paths from the last 1-2 slices>

## If anything fails
- <where to post, what to check>
```

Rationale: USER prefers working from standalone markdown validation files over scrolling inside a plan file or PR body. Prior slices produced these (`tmp/validate-slice-1-affiliate-tools.md`, `tmp/validate-slice-2-visual-pass.md`) — the pattern was already there; the skill just wasn't enforcing it.

**Do NOT skip this** even when the slice has no manual steps (e.g. a pure refactor). In that case, write a file that says "Validation: `npm test` green + `docker compose run --rm test` green — no manual steps required for this slice" so the artifact still exists and future USER can see at a glance that nothing was missed.

**Note:** `tmp/` is gitignored per the project's CLAUDE.md — do NOT stage this file. Link to its path in the PR body's "Test plan" section so reviewers know where to find it in the worktree.

## Step 3: Stage Files

Stage specific files — do NOT use `git add .` or `git add -A`. List every file explicitly.

Group by category:
1. Migration files
2. New handler files
3. New component files
4. Modified source files
5. New test files
6. Modified test files
7. New E2E spec files

## Step 4: Commit

Write a descriptive commit message following the project's style:
- First line: feature summary + issue reference
- Body: organized by area (Backend, Frontend, Bug fixes, Tests)
- Include Co-Authored-By line

Use HEREDOC format for the message.

## Step 5: Push

```bash
git push -u origin <branch-name>
```

## Step 5.5: Pre-PR Wiring Check (mandatory, blocking)

Before `gh pr create`, dispatch a sonnet subagent to run the wiring check per `~/.claude/rules/hooks-and-agents.md` § Pre-PR Validation Agent § Wiring check.

The agent MUST:
- Run `git diff main...HEAD` against the worktree
- Grep for newly-added interactive elements (`<button`, `onclick=`, `addEventListener('click'`, `data-action=`, `data-download`, etc.)
- Verify each new element has a matching click handler
- Write report to `tmp/wiring-check-report.md` (use the Subagent Dispatch Protocol — require explicit output persistence)
- Return only: verdict (PASS / FAIL / PASS-WITH-CONCERNS) + top-3 findings + report path, in under 150 words

**If FAIL:** fix before creating PR. Do not ship a rendered-but-inert interactive element — this has been the recurring USER-flagged failure mode (see `feedback_wire_interactive_elements.md`).
**If PASS-WITH-CONCERNS:** fix or explicitly defer in the PR body with rationale.
**If PASS:** proceed to Step 6.

Model: `sonnet` per `~/.claude/rules/hooks-and-agents.md` § Model Policy.

## Step 6: Create PR

Write the PR body to a temp file first (avoids heredoc issues), then use `--body-file`:

The PR should include:
- **Summary** — 3-4 bullet points covering what shipped
- **Changes table** — area, files, what changed
- **Test coverage** — new test counts by type
- **Test plan** — manual verification steps for USER

Reference the brief path and issue number.

## Step 6.5: Background PR Review (mandatory)

Immediately after `gh pr create` succeeds, dispatch a sonnet subagent in the BACKGROUND (`run_in_background: true`) to review the PR per `~/.claude/rules/hooks-and-agents.md` § PR_CREATE_HOOK signal.

This is normally auto-triggered by the PR_CREATE_HOOK, but the hook can miss — especially when `gh pr create` runs from a non-worktree cwd. ALWAYS dispatch explicitly as a safety net; duplicate-review cost is low, missed-review cost is high.

The agent MUST:
- Review full diff for security (XSS, exposed secrets, auth gaps), SQL changes (FK deps, transactions, cascade risks), test coverage, debug artifacts (console.log, TODO, hardcoded values), architectural concerns
- Write detailed findings to `tmp/pr-review-report.md` (use the Subagent Dispatch Protocol — require explicit output persistence)
- Post a condensed comment on the PR via `gh pr comment <number> --body "$(cat <<'EOF' ... EOF)"`, starting with one-line verdict (PASS / CONCERNS / BLOCK)
- Return only: PR comment URL + verdict + report path in chat

Model: `sonnet`.

## Step 7: Report

Tell the orchestrator (or USER):
- PR URL + PR comment URL (from the background review agent, when available)
- Test counts (baseline → final)
- Files changed
- Any deviations from the plan
- What needs manual testing
- What post-merge tasks remain (migration application, architecture doc updates, behavior map)
- Paths to all subagent reports written during this run (`tmp/subagent-report-*.md`, `tmp/wiring-check-report.md`, `tmp/pr-review-report.md`)
