# GitHub Issue Workflow

GitHub Issues on the `example-app` repo are the **single source of truth** for task tracking. The markdown backlog files (`backlog/in-progress.md`, `ideas.md`, `completed.md`) are legacy — don't use them.

## Issue Lifecycle

```
created → triaged (labeled) → in-progress (assigned) → done (closed with reason)
```

### Creating issues
- Create an issue before starting any non-trivial work
- Use the repo's issue templates (bug, feature, task) — they enforce required fields
- Add the issue to the GitHub Project: `gh project item-add 1 --owner USER --url <issue-url>`

### Triaging
- Apply type and effort labels (see taxonomy below)
- Set dependencies: note which issues block or are blocked by this one
- If the issue needs shaping before work can start, label it `needs-shaping`

### Working
- Assign yourself + add `in-progress` label when starting work
- Reference issue numbers in commits: `Fix auth refresh, closes #35`
- One issue per scope of work — don't lump unrelated changes

### Closing
- Close with `--reason completed` for finished work
- Add a brief comment explaining what was done and how it was verified
- For issues being deferred: add `deferred` label + comment explaining why, remove `in-progress`

## Labels Taxonomy

### Type
- `bug` — Something broken
- `feature` — New functionality
- `task` — Chore, migration, or non-user-facing work
- `idea` — Unshaped concept for future consideration
- `enhancement` — Improvement to existing functionality

### Status
- `in-progress` — Actively being worked on
- `blocked` — Can't proceed until something else is resolved
- `deferred` — Intentionally postponed

### Context
- Event-specific tags (e.g., `nca-2026`) for time-bound work

### Effort
- `quick-fix` — Can be done in one session without planning
- `shaped` — Has a brief/spec, ready to build
- `needs-shaping` — Idea exists but approach isn't defined yet

## Session Integration

- Every session capture should list issue numbers touched during the session
- When closing issues during a session, note it in the session summary
- After a session, check if any `in-progress` issues should be updated or closed

## Staleness Rules

- If an issue has `in-progress` label for 3+ sessions without activity → flag for review
- If an `idea` issue has no activity for 2+ weeks → consider closing or adding `deferred`
- During session-start recon, scan for stale issues as part of the workflow
