# Next

Read the current project's next-steps.md and update a centralized index for quick project navigation.

## Process

1. Check if the current working directory contains a `next-steps.md` file
1b. Also check GitHub Issues for the project's repo: `gh issue list --repo <owner/repo> --state open --limit 10`
   - Determine the repo from `gh repo view --json nameWithOwner -q .nameWithOwner` (run from project directory)
   - If that fails (not a git repo or no remote), skip this step
2. If found, parse the following information:
   - Project name (from the heading, e.g., "# Next Steps - Example Project" → "Example Project")
   - Current phase (from "Current Phase:" line)
   - Last updated date (from "Last Updated:" line)
   - Session link (extract the most recent session link)
   - Resume point (extract the first 1-3 items from "Resume Point" or "Immediate Next" section)
   - Commands to run (from the "How to resume testing:" or similar command block)
3. Update the entry for this project in `~/Projects/claude-config/next-steps.md`
   - If project already exists in the index, update its entry
   - If project is new, add it to the "Active Projects" section at the top
   - Use the absolute path to the current working directory as the project path
4. Display a summary to the user showing:
   - Project name
   - Phase
   - Last updated date
   - First priority from resume point
   - Index file location

## Index Entry Format

When updating the index, use this structure:

```markdown
### [Project Name]

**Path:** [absolute path to project directory]
**Phase:** [current phase]
**Last updated:** [YYYY-MM-DD]
**Session:** [link to most recent session file]

**Resume point:**
[First 1-3 items from resume/next steps section]

**Commands:**
[Commands from next-steps.md]
```

## Error Handling

- If no `next-steps.md` exists in current directory, inform the user and suggest they may be in the wrong directory or need to create one
- If the index file doesn't exist at `~/Projects/claude-config/next-steps.md`, create it with the template structure from `~/.claude/skills/next.md`

## Output to User

After updating the index, show:

```
Updated next-steps index.

Current project: [Project Name]
Phase: [Current Phase]
Last updated: [Date]
Next priority: [First item from resume point]

Open issues: [count] (bugs: [n], tasks: [n], enhancements: [n])

Index location: ~/Projects/claude-config/next-steps.md
```

If GitHub Issues were found, append a summary grouped by label (show top 3-5 highest priority items).
