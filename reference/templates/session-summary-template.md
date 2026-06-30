# Session Summary Template

**Target length:** 50 lines (max 100)
**Purpose:** Quick resume point, not exhaustive documentation

For examples and anti-patterns, see `session-summary-examples.md` in this directory.

## Format

```markdown
# Session — YYYY-MM-DD HH:MM

**Project:** [Project Name]
**Branch:** [git branch if applicable]

---

## What

[1-2 sentences summarizing the work done]

## Key Decisions

- [Decision 1: What was decided and why]
- [Decision 2: What was decided and why]
- [Decision 3: What was decided and why]

## Current State

**Completed:**
- [Feature/file completed]

**Blockers:**
- [What's blocked and why]

**Open questions:**
- [Questions that need answering]

## Next Steps

1. [Specific action with file/command]
2. [Specific action with file/command]
3. [Specific action with file/command]

## Resume

**Start with this prompt:**
```
[One paragraph describing current state and what to do next]
```

**Command to run:**
```bash
cd /path/to/project
[command that shows current state or starts work]
```

**Post to GitHub issue:** If work is tied to a tracked issue, also post the resume prompt as a comment on that issue so it's discoverable outside the session file. Include uncommitted file list and blockers.

## Reflections

### Learning Events
For each notable moment, tag with a type and describe what happened:
- `redirected` — USER corrected scope, approach, or sequence
- `assumption` — Acted on unverified belief; what was assumed vs reality
- `validation-skip` — Skipped a self-validation step; what was missed
- `green-field-error` — Assumed green field when prior work existed
- `scope-creep` — Work expanded beyond agreed scope
- `protocol-followed` — A protocol prevented an error or saved time
- `efficiency-win` — A tool choice, pattern, or approach that worked well

Format: `- **[type]:** [What happened] → [Lesson or protocol gap]`

### Recurring Patterns
Note if any reflection echoes a pattern from prior sessions. Reference the session date. If a pattern hits 3+ occurrences, flag as chronic.

### Session Metrics
- **Files modified:** N
- **Issues touched/created/closed:** list
- **Times redirected by USER:** N
- **Plan changed mid-session:** Yes/No
- **Self-validation protocol followed:** Yes/Partially/No

### Tool Telemetry
- **Dead-end tool calls:** N — [brief description of what failed]
- **Retries from guessing vs reading:** N — [what was guessed instead of grepped]
- **Fix iterations:** N — [what required multiple attempts]
- **Agent rework:** N — [agent specs that needed revision]
- **Unnecessary operations:** N — [redundant reads, duplicate searches]

> Telemetry feeds the `/maintenance` routine. Consistent tracking enables trend analysis across sessions. Even "0" values are useful — they confirm the metric was checked.
```

## Quick Rules

- **Write for future you** — What do you need to resume in 3 days?
- **Assume git access** — Don't duplicate what `git log` shows
- **Link, don't copy** — Point to files/docs instead of copying content
- **Decisions over details** — WHY matters more than WHAT
- **Blockers are critical** — Highlight what prevents progress
- **Next steps are concrete** — Specific files/commands, not vague goals
- **Resume prompts go on the issue too** — Post as a comment so it's findable from GitHub, not just the session file
