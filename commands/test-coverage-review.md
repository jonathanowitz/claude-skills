---
description: Review recent commits for test coverage gaps (unit tests + Playwright e2e)
argument-hint: [number of commits or "since #issue" or "since YYYY-MM-DD"]
allowed-tools: [Bash, Read, Glob, Grep]
---

# Test Coverage Review

Audit recent commits for missing test coverage — both unit tests (`tests/`) and Playwright e2e tests (`e2e/`).

## Step 1: Determine Scope

Parse `$ARGUMENTS` to figure out which commits to review:

- **Number** (e.g. `10`) → last N commits on the default branch
- **`since #NN`** → commits since the one that closes/references issue #NN
- **`since YYYY-MM-DD`** → commits since that date
- **Empty** → check for a marker file at `.claude/.last-test-coverage-review`. If it exists, read the stored commit SHA and review everything since then. If not, default to the last 20 commits.

Identify the repo:
```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```
If this is a docs-only repo in the example-app issue-tracker orbit (`example-context`, `dev-reference`, `claude-config` — see `references/product-json.md`'s orbit rule), target `USER/example-app` and operate from `~/Projects/example-app`. Every other repo reviews itself.

## Step 2: Collect Commits and Changed Files

```bash
git log <range> --oneline --no-merges
```

For each commit, get the list of changed files:
```bash
git diff-tree --no-commit-id --name-only -r <sha>
```

Group changes into categories derived from the current repo's actual top-level dirs (`ls` the repo root) rather than an assumed fixed set — example-app's own dirs are a worked example, not a universal shape:
- **API routes** — files under an API dir (example-app: `api/`)
- **App/UI** — files under a frontend dir (example-app: `web/` — JS, HTML, CSS)
- **Parsers/tools** — files under a scripts/tools dir (example-app: `tools/`)
- **Config/infra** — `.github/`, `vercel.json`, `package.json`, etc.
- **Tests** — files under the repo's test dirs (example-app: `tests/` or `e2e/`) (these ARE test files, not coverage gaps)

## Step 3: Map Existing Test Coverage

Scan the test directories to understand what's already covered:

```bash
ls tests/**/*.test.* tests/**/*.spec.*
ls e2e/*.spec.*
```

Build a map of which source files/features have corresponding tests.

## Step 4: Analyze Each Non-Test Change

For each changed source file, check:

### Unit test coverage (`tests/`)
- Does a corresponding test file exist? (e.g. `api/v1/[...path].js` → `tests/api/`)
- If the commit added a new function or endpoint, is there a test for it?
- If the commit fixed a bug, is there a regression test?

### E2E coverage (`e2e/`)
- If the change affects user-visible behavior (UI, navigation, auth flow, data display), is there a Playwright spec that exercises it?
- If the change affects an API endpoint that the UI calls, is there an e2e test that covers the round-trip?

### Exempt from test coverage (don't flag these):
- Pure CSS/styling changes
- Documentation and markdown files
- Config files (`vercel.json`, `.github/workflows/`, `package.json` version bumps)
- Analytics-only changes (PostHog events, Sentry config)
- Static assets (images, fonts, vendor scripts)

## Step 5: Generate Report

Present findings in this format:

```
# Test Coverage Review
Repo: <repo>
Range: <commit range description>
Commits reviewed: N
Files changed: N (excluding test files)

## Gaps Found

### Missing Unit Tests
| Commit | File | What Changed | Suggested Test |
|--------|------|-------------|----------------|
| abc1234 | api/v1/handler.js | New endpoint /foo | Test request/response + auth |

### Missing E2E Tests
| Commit | File | User-Facing Change | Suggested Spec |
|--------|------|--------------------|----------------|
| def5678 | web/app.js | New filter UI | e2e/filters.spec.js — test filter apply + persist |

### Adequately Covered
[List commits/files that DO have matching tests — brief, one line each]

### Exempt (No Tests Needed)
[List with reason — CSS, docs, config, etc.]

## Summary
- Commits with test gaps: N / N total
- Unit test gaps: N
- E2E gaps: N
- Coverage rate: N% of testable changes have tests
```

## Step 6: Save Bookmark

Write the SHA of the most recent reviewed commit to `.claude/.last-test-coverage-review` (in the repo root, not the user home directory) so the next run picks up where this one left off:

```bash
echo "<latest-sha>" > .claude/.last-test-coverage-review
```

Make sure `.claude/.last-test-coverage-review` is in `.gitignore` so it doesn't get committed.

## Guidelines

- **Read-only for source code** — Don't modify any source files. Only write the bookmark file.
- **Be specific about suggested tests** — Don't just say "add a test." Say what the test should verify.
- **Don't flag test-on-test** — If a commit only touches files in `tests/` or `e2e/`, skip it.
- **Severity signal** — Prioritize gaps in API routes and auth flows over UI tweaks.
- **No false positives** — If a change is genuinely trivial (typo fix, comment update), don't flag it. Only flag changes that alter behavior.
