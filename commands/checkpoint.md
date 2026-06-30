# Checkpoint

Capture an in-session telemetry snapshot without ending the session. Run this after any major milestone — PR created, bug fixed, direction change — or whenever compaction feels imminent.

Appends a timestamped entry to `~/.claude/checkpoints/checkpoint-YYYY-MM-DD.md` (creates file if it doesn't exist). Multiple checkpoints per session accumulate in one file. `/session-capture` picks these up automatically and merges the telemetry.

## Steps

### 1. Gather State

Run in parallel:

```bash
git status --short
git log --oneline -5
```

Also note the current branch name and the repo (from `git remote get-url origin` or cwd).

### 2. Write the Checkpoint Entry

Determine the current date and time (HH:MM). Append the following block to `~/.claude/checkpoints/checkpoint-YYYY-MM-DD.md`:

```markdown
## Checkpoint — HH:MM

**Project:** [repo name]
**Branch:** [current branch]

### In Flight

[1-2 sentences: what's being worked on right now, which issue number, where in the task]

### Telemetry Events (since last checkpoint or session start)

For each notable moment since the last checkpoint (or session start if this is the first checkpoint):

- **[type]:** [What happened] → [Lesson or protocol gap]

Types: `redirected` | `assumption` | `validation-skip` | `green-field-error` | `scope-creep` | `protocol-followed` | `efficiency-win`

Tag redirections with subdomain: `redirected:product`, `redirected:technical`, `redirected:scope`.

If nothing notable since last checkpoint: "No notable events since last checkpoint."

### Session Metrics (cumulative to this point)

- **Files modified:** [count from git status, list key ones]
- **Issues touched/created/closed:** [list]
- **Times redirected by USER:** [count]
- **Dead-end tool calls:** [count — bash failures, wrong paths, empty greps that had to be retried]
- **Retries from guessing vs reading:** [count — guessed a selector/route/column instead of grepping, and it was wrong]
- **Fix iterations:** [count — same component required multiple attempts]
- **Unnecessary operations:** [count — redundant reads, duplicate searches]

### Immediate Next Steps

- [Most urgent next action]
- [Second priority if clear]

---
```

### 3. Confirm

Tell USER: "Checkpoint saved — `~/.claude/checkpoints/checkpoint-YYYY-MM-DD.md`." One line, no extra commentary.
