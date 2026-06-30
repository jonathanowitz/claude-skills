# Bug Squash

Fetch all open bugs from the Example Project app repo, analyze them, and produce a prioritized plan for fixing them.

## Step 1: Fetch Open Bugs

Run:
```bash
export PATH="$PATH:/c/Program Files/GitHub CLI"
gh issue list --repo USER/example-app --state open --label bug --json number,title,body,createdAt,labels,assignees,comments --limit 100
```

If the command fails, troubleshoot the `gh` CLI auth/path and report the error.

## Step 2: Analyze Each Bug

For each open bug, extract:

- **Issue number and title**
- **Symptoms** — What the user sees (from body/comments)
- **Suspected area** — Which part of the codebase is likely affected (UI, API, auth, database, scheduling logic, etc.)
- **Severity** — Classify based on impact:
  - **Critical** — App crashes, data loss, auth broken, users can't complete core flows
  - **High** — Major feature broken or degraded, bad data displayed, significant UX failure
  - **Medium** — Feature works but has noticeable issues, cosmetic bugs in key flows
  - **Low** — Minor cosmetic issues, edge cases, nice-to-fix
- **Complexity estimate** — Quick guess at fix difficulty:
  - **Quick fix** — Likely a one-file change, clear root cause
  - **Moderate** — May touch 2-3 files, needs some investigation
  - **Deep dive** — Unclear root cause, may require significant debugging or architectural change

## Step 3: Prioritize

Sort bugs into a priority order using this matrix:

1. Critical severity, any complexity (fix first)
2. High severity + Quick fix (high bang-for-buck)
3. High severity + Moderate complexity
4. Medium severity + Quick fix
5. Everything else

Within each tier, order by age (oldest first).

## Step 4: Produce the Plan

Output a markdown report with:

### Summary
- Total open bugs: [count]
- Breakdown by severity: Critical: N, High: N, Medium: N, Low: N
- Estimated quick wins: N bugs that could be fixed in a single session

### Priority Queue

For each bug in priority order, show:

```
### #[number]: [title]
**Severity:** [Critical/High/Medium/Low] | **Complexity:** [Quick fix/Moderate/Deep dive]
**Area:** [suspected codebase area]
**Summary:** [1-2 sentence description of the bug]
**Suggested approach:** [Brief note on how to investigate/fix]
```

### Recommended Session Plan

Group the bugs into suggested work sessions:

- **Session 1 (Quick Wins):** List the quick-fix bugs that can be knocked out fast
- **Session 2+ (Deeper Work):** Group remaining bugs by codebase area so related bugs can be fixed together

## Output

Display the full report directly to the user. Do not save to a file unless asked.
