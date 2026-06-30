# session-capture

Create a concise session summary (50-line format) for quick resume.

## Usage

```
/session-capture
```

## What This Does

Creates a session summary file in `~/.claude/sessions/` following the short format:
- **What:** 1-2 sentences
- **Key decisions:** 3-5 bullets
- **Current state:** Blockers only
- **Next steps:** 1-3 actions
- **Resume:** Command to run

## Process

1. Analyzes recent conversation
2. Extracts key decisions (not implementation details)
3. Identifies blockers and open questions
4. Generates resume prompt and command
5. If operating in the Example Project directories, saves sessions to "C:\Users\you\OneDrive\Documents\Claude\example-context\sessions" for syncing to github
6. All other sessions save to `~/.claude/sessions/session-YYYY-MM-DD-HH-MM-<descriptive title>.md`
7. Updates `ProjectName/next-steps.md` if in a project directory
8. **Example Project only:** After saving the session file, update `example-context` docs to reflect session progress (see Example Project Context Sync below)

## Example Output

```markdown
# Session — 2026-02-06 15:43

**Project:** Example Project
**Branch:** beta

---

## What

Fixed OAuth bugs and mobile layout issues for Acme signup.

## Key Decisions

- SessionStorage bridge (30s TTL) prevents premium flicker on redirect
- Composite keys (gym|team) for team uniqueness
- Mobile: stack team names, hide email in header, compact buttons

## Current State

**Completed:** All OAuth and mobile bugs fixed, deployed to beta

**Blockers:** None

**Open questions:** None

## Next Steps

1. Monitor user feedback on beta deployment
2. Merge beta → main when testing complete

## Resume

**Start with this prompt:**
```
Beta testing complete for OAuth and mobile fixes. Ready to merge beta → main. Should I create PR or direct merge?
```

**Command to run:**
```bash
cd ~/example && git status && git log beta --oneline -5
```
```

## Configuration

**Customize via prompts:**
- Include specific files: "Include paths to files changed"
- Add git commits: "List commits from this session"
- Custom resume command: "Resume command should run tests"

## When to Use

- End of work session (before closing)
- After completing major milestone
- Before context switch to another project
- When prompted: "Would you like me to save a session summary?"

## Benefits

- Fast resume (<2 min to understand state)
- No redundant detail (git log has technical changes)
- Focus on decisions and blockers (what matters)
- Single command to continue work

## Example Project Context Sync

When working from `example-app`, `example-context`, or any Example Project project directory, after saving the session file, review and update these files in `C:\Users\you\OneDrive\Documents\Claude\example-context\`:

### Always check:

**`backlog/in-progress.md`**
- If something completed this session → remove from Active Work (or strike through), add ✓
- If a blocker was resolved → update/remove from Blockers section
- If a new blocker emerged → add to Blockers section
- If a feature's status changed (started shaping, unblocked, re-prioritized) → update its entry
- Update "Last Updated" date

**`backlog/completed.md`**
- If a feature or significant milestone shipped → add entry at top of current quarter
- Include: what was built, key decisions made, notable implementation detail
- Update "Last Updated" date

### Check if changed:

**`architecture/system-overview.md`** — Update if:
- Repo structure changed, new files created, key files renamed
- Data flows changed (new API paths, client behavior changed)
- Tech stack changed (new service added, constraint resolved)
- Current data sizes updated (gyms, teams, entries counts)

**`architecture/api-design.md`** — Update if:
- New endpoints added or existing endpoints changed
- Request/response format changed
- Build phase status changed (Phase A/B/C/D)
- `competition_id` or other param types confirmed/changed

**`architecture/database-schema.md`** — Update if:
- New tables or columns added
- RLS policies changed
- Migration ran

**`briefs/*.md`** — Update if:
- Brief status changed (shaped → in progress → complete)
- New decisions made that resolve open questions
- New rabbit holes or risks identified
- Phase completion status changed

### After updating context files:
- Update `example-context/next-steps.md` with immediate next actions
- Commit the example-context repo: `git add -A && git commit -m "Session sync: <date> — <topic>"`

---

## Related

- Reference: `~/.claude/references/session-summary-template.md`
- Reference: `~/.claude/references/next-steps-convention.md`
- Command: `/clear` (use after session capture to reset context)
