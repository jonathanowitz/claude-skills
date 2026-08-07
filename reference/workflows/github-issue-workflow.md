# GitHub Issue Workflow

GitHub Issues on the current project's **issue tracker** are the **single source of truth** for task tracking. Resolve the tracker via `resolve_product_field issue_tracker` (see `references/product-json.md`) — the orbit rule: `example-app`, `example-context`, `dev-reference`, and `claude-config` all resolve to `USER/example-app`; every other repo tracks its own tasks in its own repo (its own `gh_slug`). The markdown backlog files (`backlog/in-progress.md`, `ideas.md`, `completed.md`) are legacy — don't use them.

## Issue Lifecycle

```
created → triaged (labeled) → in-progress (assigned) → done (closed with reason)
```

### Creating issues
- Create an issue before starting any non-trivial work
- Use the repo's issue templates (bug, feature, task) — they enforce required fields
- Add the issue to the resolved tracker's board, if it has one — example-app orbit repos use Project #1: `gh project item-add 1 --owner USER --url <issue-url>`. A repo with its own `issue_tracker` uses its own board/workflow, if any (see `workflows/work-state-tracker.md`).
- **Apply a scheduling label at creation (see Scheduling below). The default for a session follow-up is `someday`** — a follow-up gets `now` or `next` ONLY if it blocks the current or immediate-next slice, or is a live production bug hurting users. This is the inflow valve: without a deliberate default, every session's follow-ups land as undifferentiated "act on me now," and the backlog grows ~1.4 issues for every 1 closed (measured 2026-07-06: +32 net over 5 weeks). Most follow-ups are real-but-not-urgent → `someday`.
- Before filing, apply the bar: *"will I act on this, or do I just not want to forget it?"* The latter is often a one-line note, not an issue. Issues have a triage cost; notes don't.

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

### Scheduling (queue position — the sort the tracker carries)
Every open issue should carry exactly one of these. This is what lets the resume/handoff prompt shrink to a *pointer* ("next up: #1016") instead of re-enumerating and re-ranking the backlog in prose every session. Priority lives in the tracker, not the handoff.
- `now` — blocks the current or immediate-next slice, OR a live production bug hurting users right now. Keep this set SMALL (single digits). If everything is `now`, nothing is.
- `next` — clearly wanted in the next handful of sessions; scoped enough to pick up soon.
- `someday` — real and worth keeping, but fine to sit for months; not scheduled. Most of the tail lives here. `someday` subsumes the old reflexive `deferred` for un-shaped wants (keep `deferred` only for work explicitly pulled out of an active slice).
- (`priority:high` is retired in favor of `now` — migrate any stragglers.)

## Session Integration

- Every session capture should list issue numbers touched during the session
- When closing issues during a session, note it in the session summary
- After a session, check if any `in-progress` issues should be updated or closed
- **The resume/handoff prompt points at labels, it does not re-derive priority.** Report "next up per the tracker: `now`/`next` set" and let GitHub carry the ranking. A handoff that re-enumerates and re-ranks open follow-ups in prose is a symptom that the sort didn't land in the tracker — fix the labels, not the prose.

## Backlog Discipline — the tracker needs a DRAIN, not just a capture

Issues-as-source-of-truth was meant to stop follow-ups dying in chat. It succeeded at capture. But capture with no drain is a landfill, not a source of truth — the value of a tracker is the *sort*, not the pile. Reverse pressure is a standing responsibility, not a someday-someone job.
- **Periodic triage sweep** (roughly monthly, or whenever open count feels shapeless): close done/duplicate/mooted, dedupe, and confirm every survivor has a current scheduling label. Propose closures for owner approval — never auto-close.
- **Close is a normal outcome, not a failure.** "Not now, reopen if it recurs" is a legitimate close for a stale idea. An idea sitting open for months without a scheduling home is a close candidate.
- Pre-cutover caveat during the rebuild: a shipped-stack bug is NOT moot just because the rebuild will redo that surface — the shipped app is live in production until cutover. Don't close old-stack bugs as "superseded" without evidence the surface is gone or the bug is fixed.

## Staleness Rules

- If an issue has `in-progress` label for 3+ sessions without activity → flag for review
- If an `idea`/`someday` issue has no activity for 8+ weeks → close candidate ("reopen if it recurs")
- During session-start recon, scan for stale issues as part of the workflow
