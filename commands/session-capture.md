---
description: Save a session summary checkpoint — records work done, decisions made, and next steps
---

# Session Capture

Save a checkpoint of the current session without ending it.

Create a session summary file in `~/.claude/sessions/` with the naming convention `session-YYYY-MM-DD-HH-MM.md` (use current date/time).

The summary should include:

1. **What was worked on** - Projects, files, features discussed or modified
2. **Key decisions made** - Technical choices, design decisions, rationale
3. **Current state** - Where things stand right now
4. **Open questions or blockers** - Anything unresolved
5. **Next steps** (regret-filtered) - Apply the regret test: "If I skip this, will it create real friction next session?" Only list items that pass. Keep to 1-3 genuinely urgent actions, not a brain dump.
6. **Relevant file paths** - Key files for easy reference

## Reflections (Self-Assessment)

**This section is not optional.** After writing the factual summary above, honestly assess how the session went. This is a learning tool, not a performance review.

### Learning Events

For each notable moment, log a structured entry:

```markdown
### Reflection 1
- **Type:** redirected | assumption | validation-skip | green-field-error | scope-creep | protocol-followed | efficiency-win
- **What happened:** [specific description of the moment]
- **Root cause:** [why it happened — not "I made a mistake" but the actual mechanism]
- **Protocol gap:** [which reference doc should have prevented this, or needs updating — or "none, protocols worked"]
```

Include at minimum:
- Every time USER redirected or corrected you (type: `redirected`). Tag the domain: `redirected:product` for product/UX decisions (copy, what to show/hide, user-facing behavior), `redirected:technical` for implementation approach, `redirected:scope` for what's in/out. Product corrections are especially valuable — they reveal design instincts that accumulate into conventions.
- Every assumption you made that turned out wrong (type: `assumption`)
- Every time you skipped self-validation (type: `validation-skip`)
- Every time you assumed green field when prior art existed (type: `green-field-error`)
- Also capture wins — times protocols worked and prevented mistakes (type: `protocol-followed`, `efficiency-win`)

If the session was clean with no redirections, state that explicitly: "No redirections this session. Protocols followed."

### Recurring Patterns

Cross-reference with the most recent 2-3 session files. Ask:
- Did any of the same reflection types appear in prior sessions?
- Am I repeating a mistake that was already logged?
- Is there a pattern forming that needs a new CLAUDE.md rule or reference update?

If a pattern recurs across 2+ sessions, flag it explicitly:
```markdown
**Recurring pattern detected:** [type] appeared in sessions [date1], [date2], and this session. Proposed mitigation: [specific action].
```

### Session Metrics

Quick telemetry to track over time:
- **Files modified:** [count]
- **Issues touched/created/closed:** [numbers]
- **Times redirected by USER:** [count]
- **Plan changed mid-session:** yes/no — if yes, why?
- **Self-validation protocol followed:** yes/no — if no, which steps were skipped?

### Tool Telemetry

Track tool-level errors to make dead-end patterns visible over time. Review your tool calls from this session and count honestly.

- **Dead-end tool calls:** [count] — bash failures, wrong file paths, empty grep/glob results, commands that had to be immediately retried with different arguments
- **Retries from guessing vs reading:** [count] — times you guessed an identifier (DOM selector, route name, DB column, localStorage key, file path) from memory or naming conventions instead of reading the source, and it was wrong
- **Fix iterations:** [count] attempts on [component] — when a fix required multiple cycles before being correct (e.g., "3 attempts on cursor bug before correct diagnosis")
- **Agent rework:** [count] — sub-agent results that were wrong, incomplete, or required manual redo to get the actual answer
- **Unnecessary operations:** [count] — tool calls that produced correct results but were pointless (reading files you didn't need, searching for things already in context, re-reading files already read)

**Target trajectory:** These numbers should trend down session over session. If any metric stays flat or increases across 3+ sessions, flag it as a recurring pattern and propose a concrete mitigation.

- **Checkpoint + subagent telemetry:** _pending drain merge_

### Telemetry Note

Do NOT read checkpoint files or subagent reports here. Both are merged by the drain after the session file is written. This keeps their potentially large contents out of an already-large context window — Opus sessions in particular can exceed Sonnet's total context, making in-session reads doubly expensive (tokens consumed + no offload possible).

Write reflections and tool telemetry counts from what you know within the current conversation only. The drain will replace the `_pending drain merge_` placeholder with actual merged counts and learning events.

## "How to Resume" Section

Evaluate whether work is ongoing (multi-session project, incomplete tasks, clear next steps). If so, include a **How to Resume** section with:

**Include when:**
- Project spans multiple sessions
- Tasks are partially complete
- Clear continuation point exists
- Build slices or phases remain

**Skip when:**
- Work reached a natural stopping point
- Session was exploratory/research only
- No specific continuation needed

**Format when included:**
```markdown
## How to Resume

**Start with this prompt:**
```
[Copy-paste prompt that provides context and directs next actions]
```

**Commands to run:**
```bash
[Relevant shell commands for testing, running, or verifying state]
```
```

Keep it concise but complete enough to resume context later.

## Review Pending Memories

Check if `~/.claude/pending-memories.md` exists and has entries. If so, present each entry to USER for a decision:

1. Read `~/.claude/pending-memories.md`
2. For each entry, show:
   - The memory type (feedback, project, reference, user)
   - The content
   - Where it would be saved
3. USER decides for each: **commit** (write to memory), **edit** (modify then write), or **discard**
4. For committed entries, write the file to the target path and update `MEMORY.md`
5. After all entries are resolved, clear `pending-memories.md` back to just the header

This step is not optional when pending memories exist. Memories that sit in staging go stale.

## Queue for Batch Processing + Trigger Drain

After the session file is written and pending memories are resolved, append this session to the capture queue and trigger the drain.

### Step 1 — Append to queue

Append a single JSON line to `~/.claude/capture-queue.jsonl`:

```bash
echo '{"session_file":"<absolute_session_file_path>","cwd":"<cwd>","queued_at":"<ISO8601_timestamp>"}' >> ~/.claude/capture-queue.jsonl
```

Use real values. This is an atomic append — safe even if multiple terminals write simultaneously.

### Step 2 — Trigger drain

Check if a drain is already running:

```bash
cat ~/.claude/drain.lock 2>/dev/null
```

- **If the lock file exists and its PID is still running** (`kill -0 <pid> 2>/dev/null`): tell USER "Session queued. Drain already running — this entry will be picked up automatically." Done.
- **If no lock or stale lock**: spawn `/drain-captures` as a **background sonnet agent** (`run_in_background: true`, `model: "sonnet"`) to process the queue. Tell USER: "Session queued. Drain started in background."

The drain handles all shared-state work: next-steps.md, example-context docs, GitHub issues, git commits, claude-config sync. Multiple simultaneous captures are safe — each just appends to the queue and the drain processes everything it finds.

### Step 3 — Print the resume prompt (ALWAYS — the parent session's final output)

**This fires on EVERY capture, unconditionally. It is the LAST thing you say to USER — and it is the PARENT's job, never the drain's** (the drain runs in the background and cannot print to this conversation). Do not let the "sections below are for the drain agent" divider trick you into skipping it — printing the resume prompt is a parent step, listed here on purpose.

- If you wrote a "How to Resume" section, print its resume prompt **verbatim**.
- If you did NOT write one (genuine natural stopping point), write a one-line minimal resume prompt now and print that — **never skip the print entirely**.

Format it as a fenced code block with a label so it's copy-pasteable straight after `/clear`:

````
**Resume prompt (copy-paste after /clear):**
```
[the resume prompt from the session file]
```
````

**(Evidence: 2026-06-15 — skipped this print on two consecutive captures in one session; USER had to ask for it both times. Root cause: the instruction lived only BELOW the drain-only divider, so it read as the drain's job. Now it is an explicit numbered parent step.)**

---

*The sections below are reference for the drain agent (`/drain-captures`), not additional steps for the parent session.*

## Create GitHub Issues for Discovered Items

Check the session file for any bugs, tasks, or ideas discovered this session that haven't been tracked yet. If so, create GitHub issues:

1. Determine the correct repo from the project's git remote (e.g., `gh repo view --json nameWithOwner -q .nameWithOwner`)
2. For each untracked item, run `gh issue create --repo <owner/repo> --title "<title>" --label "<label>" --body "<description>"`
3. Use appropriate labels: `bug`, `task`, `enhancement`, `idea`, `planning`, `deferred`
4. Reference the session file in the issue body if context is helpful
5. Mention the created issue numbers in the session summary under a "## Issues Created" section

This replaces writing items to markdown backlog files. GitHub Issues is the single source of truth for bugs, tasks, and ideas.

## Update Project Next Steps

**CRITICAL:** After creating the session file, if work was done on a project during this session, you MUST update that project's `next-steps.md` file.

**Canonical location:** Each project has ONE canonical `next-steps.md` file. For example-app, the canonical path is `~/Projects/example-context/next-steps.md` — `example-app/next-steps.md` is a symlink to it, so editing either path writes to the same file. Worktrees inherit the symlink and also write to the canonical file. **Never create a sibling next-steps.md inside a worktree directory** — it will silently diverge from the canonical copy.

**Steps:**
1. Check if current working directory has a `next-steps.md` file (it may be a symlink — that's fine, follow it)
2. If yes, update it following `~/Projects/dev-reference/conventions/next-steps-convention.md`:
   - Update **Last Updated** date and link to the new session file
   - Update **Immediate Next** section with what was completed and next priorities
   - Update **Commands to Run** if needed
   - Add the session to **Done** section documenting completed work
3. If no `next-steps.md` exists but this is clearly a project directory, offer to create one — for example-app, create it in `example-context/` and symlink from `example-app/`, never as a standalone file in a worktree
4. If multiple `next-steps.md` files exist for the same project (e.g., one in the worktree and one in the main checkout that aren't symlinked), STOP and flag the drift to USER — the canonical location needs to be re-established before continuing

**This is not optional** - every session capture MUST update the project's next-steps.md if applicable.

## Sweep example-context (example-app sessions only)

**Trigger:** Session touched the `example-app` repo (any worktree).

The architecture/context docs in `~/Projects/example-context/` describe the *current* state of the system. Updating them at merge time (per `post-merge-checklist.md`) catches what shipped — but mid-session work bakes assumptions into the next session unless they're recorded while context is fresh. This step moves the *thinking* earlier so the work isn't lost in context decay; the post-merge checklist will re-verify on merge.

**Walk through this list. For each item, ask "did this session change something that warrants updating it?" — if yes, edit inline now and bump the `**Last Updated:**` date at EOF of the file you touched.**

| File | Update when... |
|---|---|
| `architecture/app-behavior-map.md` | New or changed user-facing behavior. Tag new entries `[untested]` if no tests yet. |
| `architecture/codebase-map.md` | New files, moved files, new `web/lib/` modules, new components, changed script load order. |
| `architecture/api-design.md` | New or modified API endpoints, request/response shapes, new admin routes. |
| `architecture/database-schema.md` | New migration applied (committed to `supabase/migrations/`). Note tables, columns, RLS, indexes. |
| `architecture/system-overview.md` | Infra changes, new services, deployment config, auth changes, new GitHub Actions, new env vars. |
| `architecture/posthog-events-spec.md` | New analytics events added, or P1/P2 events implemented. |
| `architecture/Design Guide.md` | Design token changes, new theme variants, new UI patterns. |
| `context/product-changelog.md` | User-visible feature shipped this session (not internal refactors). |
| `context/business-overview.md` | Pricing changes, strategy shifts, user count milestones. Rare. |
| `context/feature-tiers.md` | Tier gating logic, paywall behavior, or pricing changed. Rare and deliberate. |
| `briefs/` | Brief fully shipped → move it to `briefs/archive/`. Brief partially shipped → update with "done vs remaining" notes. |
| `reference/*` | New parsing format, new code mapping, or new external integration that warrants a reference doc. |

**Skip the sweep entirely when:** the session was purely exploratory, debugging without code changes, or non-example-app work.

**One-line reality check:** if you can't name a specific file from the table above that needs editing, the sweep is done — don't manufacture work. If you can name one, edit it now while the change is in your head.

## Consider Updating Roadmap

After updating next-steps.md, consider whether the roadmap needs updating:

**Update `ROADMAP.md` when:**
- Feature completed or status changed (prototype → shipped, shaped → building)
- Feature priority changed
- New feature identified or deferred feature activated
- Strategic decisions affect future work (e.g., "build this before that")
- Appetite changed based on actual implementation time

**Skip updating when:**
- Work was purely bugfixes or polish (no roadmap impact)
- No features completed or reprioritized
- Session was exploratory/research only

**What to update:**
- Move completed features from "Upcoming" to "Completed" section
- Update feature status ("Shaped, ready to build" → "Building" → "Shipped")
- Update "Current Focus" section
- Adjust priorities if blocking relationships discovered
- Update "Last Updated" date

## Print Resume Prompt

**Moved into the parent flow — see "Queue for Batch Processing + Trigger Drain → Step 3" above.** Printing the resume prompt is a PARENT-session action (it must appear in this conversation, which the background drain cannot do), so it no longer lives below the drain-only divider where it kept getting skipped. The parent prints it unconditionally as its final output, every capture.

## Commit and Push Supporting Repos

After all doc updates are done, commit and push changes to `example-context` and `dev-reference` if they were modified during this session. These repos track architecture docs, briefs, conventions, and workflows — changes that aren't committed drift silently across sessions.

```bash
# Check each repo for changes
git -C ~/Projects/example-context status --short
git -C ~/Projects/dev-reference status --short
```

For each repo with changes:

1. Stage only files modified in this session (not accumulated untracked files from prior sessions — flag those to USER)
2. Commit with a message referencing the issue number: `"Update <files> for <feature> (#NNN)"`
3. Push to remote

**Do not skip this.** Architecture docs and workflow files that aren't pushed are invisible to the next session and to USER when he reads them on GitHub. This is the same class of problem as forgetting to push a branch.

## Copy Session File to claude-config

After writing the session file to `~/.claude/sessions/`, copy it into `~/Projects/claude-config/sessions/` so it gets version-controlled:

```bash
cp ~/.claude/sessions/<session-filename>.md ~/Projects/claude-config/sessions/
```

This step is required — `~/.claude/sessions/` is not inside the git repo, so without the copy the session file is never committed.

## Sync Claude Config to GitHub

After all other steps are complete, check if `~/Projects/claude-config` has uncommitted changes:

```bash
git -C ~/Projects/claude-config status --short
```

If there are changes (new/modified commands, skills, settings, etc., including the newly copied session file):

1. Stage all changes: `git -C ~/Projects/claude-config add -A`
2. Commit with message: `"Sync claude config — session YYYY-MM-DD-HH-MM"`
3. Push to remote: `git -C ~/Projects/claude-config push`

This keeps the versioned config repo in sync with the live `~/.claude/` symlinks. Do not skip this step — config drift is invisible until it causes problems.

After completing all files, confirm the save locations to the user.
