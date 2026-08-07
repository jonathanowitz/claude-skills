# Post-Merge Checklist

> Run through this checklist after every PR merge. Keeps reference docs, tracking, and artifacts in sync with shipped code.

**Scope note:** The checkout path, board name ("Project Tracker"), and `example-context/` doc set below are example-app's — substitute the merged PR's own repo's checkout path, its own tracker/board (see `references/product-json.md` — orbit repos resolve to the example-app board, every other repo tracks its own), and its own context sibling if it declares one. A repo with no context sibling has no step-3 doc set to update — skip that section rather than forcing it.

## 0. Capture Before You Forget (mechanical reminder)

`bash-post-hook.sh` creates a lock file (`/tmp/post-merge-capture-pending-*.lock`) after every `gh pr merge`. `post-merge-gate.sh` checks for that lock on every subsequent Bash command and injects a `POST_MERGE_CAPTURE_PENDING` system reminder until `/session-capture` runs (which deletes the lock via auto-clear once a session file referencing the PR exists).

**This means:** the trigger for `/session-capture` is now mechanical, not the one-shot text signal in tool output. The one-shot signal is still emitted by `bash-post-hook.sh`, but the gate is the safety net for when that signal gets buried.

(Evidence: 2026-05-11 S54 — 3 PR merges, 0 `/session-capture` triggers; the one-shot `POST_MERGE_HOOK` signal was either buried in tool output or not recognized. Soft-nag gate added 2026-05-12.)

If you ever see a `POST_MERGE_CAPTURE_PENDING` reminder, run `/session-capture` before anything else. If it's a false positive (stale lock from a prior session that already captured), the reminder itself shows the `rm` command to clear it manually.

## 1. Close the Issue

- Verify `fixes #NN` or `closes #NN` auto-closed the GitHub issue
- If not auto-closed, close manually with a comment noting the merged PR
- Confirm the issue moved to "Done" on the repo's tracker board (example-app orbit repos → GitHub Project "Project Tracker"; every other repo's own board)
  - If not: `gh project item-edit` to move it

## 2. Clean Up the Worktree

Sessions run from the main checkout of the repo the merged PR belongs to (e.g. example-app's main checkout for an example-app PR), with read/write across all worktrees via absolute paths. Worktree removal happens immediately in the post-merge cleanup agent — no deferral needed.

- **First, drain the slice's known-scratch `tmp/` files** so the non-force removal succeeds and `--force` (which triggers the curated-rescue → orphan-accumulation path) is never reached for a pure-scratch worktree. Use the exact-name ALLOWLIST in `claude-config/rules/hooks-and-agents.md` § POST_MERGE_HOOK (`pr-gate.green`, `e2e-results.json`, `e2e-pass.txt`, `walk-*.md`, `test-review-*.md`, `validate-*.md`, `seed-*.mjs`, `verify-*.mjs`, `gemini-*.md`, `pr-body-*.md`, `squash-body-*.md`) — never `tmp/*.json`/`tmp/*.md` wholesale, so curated artifacts stay protected.
- Run from anywhere (always target the repo's main checkout by absolute path):
  - `git -C <repo-root> worktree remove <worktree-path>` (e.g. `git -C $HOME/Projects/example-app worktree remove ...`)
  - `git -C <repo-root> branch -D <branch-name>`
- Only worktree leftovers expected: `.claude/settings.local.json` diffs + any untracked files already copied to main. If those are the only uncommitted items, use `--force`. If anything else is uncommitted, stop and surface it before removing.
- Verify the branch was deleted on remote (GitHub's auto-delete should handle this). If branch persists: `git push origin --delete <branch-name>`
- `git worktree prune` cleans any stale refs if the directory was removed out-of-band

## 3. Update Reference Docs (context sibling, if the repo has one)

Skip this whole section if the repo has no context sibling (`resolve_product_field context_repo` returns nothing) — most repos don't, and that's normal. For example-app, this resolves to `example-context`. For each doc below, check whether the merged changes affect it. If yes, update the content **and bump the `Last Updated` date** at the bottom of the file. Stale architecture docs cause downstream planning errors — treat this step as mandatory, not optional, whenever the repo has a context sibling.

### Architecture docs (`architecture/`)

| File | Update when... | Last check |
|------|---------------|------------|
| **codebase-map.md** | New files, handlers, components, scripts, or load order changes | Check date at EOF |
| **api-design.md** | New or modified API endpoints, request/response shapes, new admin routes | Check date at EOF |
| **database-schema.md** | New tables, columns, migrations, RLS policies, indexes | Check date at EOF |
| **system-overview.md** | Infrastructure changes, new services, deployment config, auth changes, new GitHub Actions | Check date at EOF |
| **posthog-events-spec.md** | New analytics events added or P1/P2 events implemented | Check date at EOF |
| **Design Guide.md** | Design token changes, new theme variants, new UI patterns | Check date at EOF |
| **app-behavior-map.md** | Any new or changed user-facing behavior | (updated in pre-PR step 6) |

**Quick check:** If the PR touched `api/`, update api-design + codebase-map. If it touched `web/components/`, update codebase-map. If it added migrations, update database-schema. If it changed `design-tokens.css`, update Design Guide.

### Context docs (`context/`)

| File | Update when... |
|------|---------------|
| **product-changelog.md** | User-facing changes (features, fixes visible to end users) |
| **business-overview.md** | Pricing changes, strategy shifts, user count updates |

### Briefs (`briefs/`)

- If the feature is **fully shipped**, move the brief to `briefs/archive/`
- If **partially shipped**, update the brief with what's done vs. remaining

## 4. Verify Behavior Map (moved to pre-PR)

> Behavior map updates now happen **before merge** as step 6 of the pre-PR checklist.
> Post-merge: just verify the behavior map entries from the PR are correct and nothing was missed.

## 5. Update Project Tracking

- Update `next-steps.md` — remove completed items, add new resume points
- Update `ROADMAP.md` if priorities changed
- Delete or archive fully-executed plan files

## 7. Clean Up Artifacts

- Delete temp validation scripts (`tmp/validate-*.js`, `tmp/validate-*.md`)
- Delete stale test data files
- Run `git status` in the repo's context sibling if it has one (example-app → `example-context`) — commit updates, delete orphans

## Shortcut: Trivial Changes

For single-line fixes, typo corrections, or dependency bumps, only steps 1, 2, and 7 are required.

---

*Last Updated: 2026-05-12*
