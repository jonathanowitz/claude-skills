---
description: Conduct a structured retrospective on a completed or paused project
argument-hint: "[project name or path]"
disable-model-invocation: true
---

# Post-Mortem

Conduct a structured retrospective on a completed or paused project.

## Usage

Argument: `$ARGUMENTS` (project name or path - optional, defaults to current project)

## Process

1. **Identify the project** - Use the argument provided, or detect from current working directory, or ask the user which project to review.

2. **Gather context** - Review relevant files **in this priority order**:
   1. `{project}/next-steps.md` - **Authoritative current state** (check this FIRST)
   2. **GitHub Issues** - `gh issue list --repo <owner/repo>` for open bugs, tasks, and ideas
   3. Most recent session file mentioning this project
   4. Project README, CLAUDE.md, shaping docs
   5. `~/.claude/project-index.md` for project status
   6. Older session files only for historical context (don't trust these for current state)

3. **Walk through each section** with the user, asking questions to draw out insights:

### What Worked
- What went smoothly?
- What would you do the same way again?
- Any tools, patterns, or approaches that proved valuable?

### What Didn't Work
- Where did you hit friction or frustration?
- What took longer than expected? Why?
- Any technical choices you'd reconsider?

### Rabbit Holes & Scope (Shape Up style)
- Did the project stay within its intended scope?
- What rabbit holes did you fall into?
- What got cut or deferred? Was that the right call?

### Technical Decisions
- Key architectural or implementation choices made
- Outcomes of those decisions (good, bad, TBD)
- Dependencies or tools added - worth keeping?

### Artifacts
- **Keep**: Files, patterns, or code worth preserving/referencing
- **Clean up**: Test scripts, temp files, abandoned approaches to delete
- **Extract**: Anything worth pulling into `~/.claude/references/` for reuse

### Lessons Forward
- What should be added to CLAUDE.md (global or project-level)?
- Patterns to adopt or avoid in future projects?
- Process changes for next time?

## Output

Save the post-mortem to **two locations**:

1. **Project folder**: `{project-root}/post-mortem-YYYY-MM-DD.md`
2. **Central archive**: `~/.claude/post-mortems/{project-name}-YYYY-MM-DD.md`

Create `~/.claude/post-mortems/` if it doesn't exist.

If the project is being closed:
- Update `~/.claude/project-index.md` to mark status as "completed" or "paused"
- Close resolved GitHub Issues: `gh issue close <number> --repo <owner/repo> --reason completed`
- Label remaining open issues as `deferred` if the project is pausing
- Clean up any artifacts identified for removal (with user confirmation)

Keep the tone constructive - the goal is learning, not blame.
