# next

Read the current project's next-steps.md and update a centralized index for quick project navigation.

## Usage

```
/next
```

## What This Does

1. Reads `next-steps.md` from the current working directory
2. Extracts key information (project name, phase, status, resume point)
3. Updates the centralized index at `~/.claude/next-steps.md`
4. Shows a summary of the current project's status

## Index Structure

The index (`~/.claude/next-steps.md`) maintains a scannable list of all projects with:
- Project name and path
- Current phase
- Last updated date
- Resume point (first priority action)
- Session link

## Process

1. Check if current directory has `next-steps.md`
2. Parse key sections:
   - Project name (from heading)
   - Current phase
   - Last updated date
   - Resume point / Immediate Next section
   - Session link
3. Update or create entry in `~/.claude/next-steps.md`
4. Display summary

## When to Use

- After completing work on a project (before switching)
- When starting a session (to check project status)
- To get quick overview of all active projects
- Before `/session-capture` to verify next-steps.md is current

## Benefits

- Quick project navigation (see all active projects in one place)
- Know which project to resume based on priority
- Track multiple projects without losing context
- Fast status check without opening each project's next-steps.md

## Example Output

After running `/next` in the Example Project:

```
Updated next-steps index.

Current project: Example Project
Phase: Groups feature prototype - local testing
Last updated: 2026-02-06
Next priority: Review completed test cases from TESTING-GROUPS-PROTOTYPE.md

Index location: C:\Users\you\.claude\next-steps.md
```

## Related

- Command: `/session-capture` (updates project next-steps.md)
- Reference: `~/.claude/references/next-steps-convention.md`
- Index: `~/.claude/next-steps.md` (created by this skill)
