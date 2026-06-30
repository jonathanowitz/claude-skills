# Next Steps Convention

**Purpose:** Ensure consistent, actionable continuation points for each project after session capture.

**Location:** ONE canonical `next-steps.md` per project. Worktrees, branches, and parallel checkouts must all read/write the same file — no sibling copies.

**Canonical paths:**
- **example-app:** `~/Projects/example-context/next-steps.md` (lives in the context repo). `~/Projects/example-app/next-steps.md` is a committed symlink to it, so worktrees and the main checkout all resolve to the same file. **Never create a standalone `next-steps.md` inside an example-app worktree** — it will silently diverge from the canonical copy and cause stale state.
- **Other projects:** `ProjectName/next-steps.md` at the project root (single repo, no worktrees in active use).

**Why the symlink for example-app:** This project has multiple long-lived worktrees and a sibling context repo. Without a single source of truth, every session that ran in a different directory wrote to a different copy, and the file drifted across 4+ locations within a few weeks. The symlink ensures every editor — Claude, USER, hooks, agents — writes to the same file regardless of which worktree they're in.

**If multiple `next-steps.md` files exist for the same project and aren't all symlinked together:** STOP. Audit them, pick one as canonical (newest content wins), overwrite the canonical location, then replace the others with symlinks. Flag the drift to USER.

**Update Trigger:** After `/session-capture`, if work was done on that project during the session

**Format:**

```markdown
# Next Steps - [ProjectName]

**Last Updated:** YYYY-MM-DD (link to session file)
**Current Phase:** [Brief phase name, e.g., "Shaping", "Slice 1 - CRUD", "Testing"]

## Immediate Next (Highest Priority)
1. [Specific action - be concrete]
2. [Specific action - be concrete]
3. [Specific action - be concrete]

## Why This Matters
[1-2 sentences on context/blocker/milestone this unblocks]

## Commands to Run
\`\`\`bash
# Copy-pasteable commands to resume work
cd [path]
[relevant command]
\`\`\`

## Files to Review/Edit
- `path/to/file.md` - What to review/edit and why
- `path/to/file.js` - What to focus on

## Blockers or Open Questions
- [ ] Blocker 1 - what needs to happen
- [ ] Blocker 2 - what needs to happen
(Use checkboxes if there are multiple)

## Context from Last Session
[Link to session summary, e.g., `~/.claude/sessions/session-2026-01-28-03-01.md`]
- Key decision made
- Technical choice adopted
```

## Rules

1. **Be specific:** "Implement Slice 1 - Dimension CRUD" not "build stuff"
2. **Include commands:** Make it 1-click to resume (path, command to run, file to open)
3. **Track blockers:** Flag anything that needs resolving before proceeding
4. **Link sessions:** Reference the session file that created these next steps
5. **Keep it current:** Update every session if you worked on that project
6. **One file per project:** All next steps in one place, easy to find
7. **Max 300 lines:** When the file exceeds 300 lines, prune completed and stale sections. Archive old content to the most recent session file rather than keeping it inline. The file must stay useful as a fast resume point — not become a changelog

## Example

```markdown
# Next Steps - ExampleApp

**Last Updated:** 2026-01-29 (session-2026-01-29-14-00.md)
**Current Phase:** Slice 1 Implementation - Dimension CRUD

## Immediate Next (Highest Priority)
1. Create React component structure for Dimensions Tab (P1)
2. Implement addDimension function (C1)
3. Build dimension list display with delete button (U6, U8)

## Why This Matters
Dimensions are the foundational data model. Getting CRUD working enables Slice 2 (Options) and the evaluation grid in Slice 3.

## Commands to Run
\`\`\`bash
cd "C:\Users\you\OneDrive\Documents\Claude\ExampleApp"
npm run dev
\`\`\`

## Files to Review/Edit
- `src/components/DimensionsTab.svelte` - Create this component
- `src/store.js` - Add dimension management functions
- `breadboard-exampleapp.md` - Reference wiring table for U1→U8 mappings

## Blockers or Open Questions
- [ ] Confirm Svelte project structure (TypeScript or plain JS?)
- [ ] Decide on form validation (required fields only or more?)

## Context from Last Session
[~/.claude/sessions/session-2026-01-29-14-00.md](~/.claude/sessions/session-2026-01-29-14-00.md)
- Tech stack: Svelte chosen
- Vertical slices identified and ordered
- Breadboard complete with full wiring
```

---

## Implementation Notes

**When updating after a session:**
1. Update **Last Updated** date and link to session file
2. Replace **Immediate Next** with what was just decided
3. Update **Commands to Run** if paths/setup changed
4. Update **Files to Review** based on what was worked on
5. Check **Blockers** - remove resolved ones, add new ones
6. Update **Context from Last Session** with link to new session

**When resuming work:**
1. Open `ProjectName/next-steps.md` first
2. Run the commands listed
3. Review the files listed
4. Follow the immediate next steps in order
5. After session is complete, update this file
