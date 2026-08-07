---
description: Process all queued session captures — update shared docs, commit repos, and clear the queue
---

# Drain Captures

Process all queued session captures — update shared docs, commit repos, and clear the queue.

Called automatically by `/session-capture` when no drain is already running. Can also be invoked manually from any terminal.

## What This Does

Reads all pending entries from `~/.claude/capture-queue.jsonl`, processes them in one batch (one next-steps update, one example-context sweep across all sessions, one commit per repo), then clears the queue. Runs as a sonnet agent to keep cost low.

## Process

### Step 1 — Acquire lock

The subagent sandbox blocks Bash redirects. Use the Write tool to write the current process identifier (or any non-empty string) to `~/.claude/drain.lock`. If a lock already exists with a live PID, exit immediately — another drain is running and will pick up any queued entries.

### Step 2 — Claim queue entries

The subagent sandbox blocks `mv`. Read `~/.claude/capture-queue.jsonl` directly, then use the Write tool to copy its content to `~/.claude/capture-queue-processing.jsonl`, and then immediately clear `~/.claude/capture-queue.jsonl` (Write with empty string) so new captures append to a fresh queue without conflict.

If `capture-queue.jsonl` doesn't exist or is empty, release lock and exit — nothing to do.

### Step 3 — Read all entries

Parse each line of `~/.claude/capture-queue-processing.jsonl` as JSON. For each entry, read the session file at `session_file` path and extract:
- What project was worked on (example-app, other)
- What changed (features shipped, files modified, issues discovered)
- Resume prompt (if present in "How to Resume" section)
- GitHub issues to create (if any bugs/tasks discovered)

### Step 3a — Merge checkpoint telemetry into session files

Checkpoint files are **shared across all Claude Code sessions running on the same date**. A single `checkpoint-YYYY-MM-DD.md` may contain `## Checkpoint — HH:MM` blocks written by multiple unrelated sessions. Do not assume all blocks belong to the session being drained.

For each session file in the batch:

1. Determine the session date (YYYY-MM-DD) from the session filename.
2. Determine the session's capture time from `queued_at` in the queue entry (ISO8601).
3. Read `~/.claude/checkpoints/checkpoint-{date}.md` if it exists.
4. **Assign blocks to sessions by timestamp:** a block at `HH:MM` belongs to the session whose `queued_at` is the earliest time on that date that is ≥ `HH:MM`. If the batch includes multiple sessions from the same date, each block goes to exactly one session — no double-counting.
5. If only one session is being drained for that date, all blocks are assigned to it — but note that concurrent Claude Code sessions may have written some of those blocks. Add a caveat in the session file: `_Checkpoint blocks matched by timestamp. This file is shared across all Claude Code sessions on this date — blocks from concurrent sessions may be included if timestamps overlap._`
6. For each matched block:
   - Append its Telemetry Events entries to the session file's Reflections list, prefixed with `[checkpoint · HH:MM]`
   - Add the block's counts to the session file's Tool Telemetry totals
7. Replace the `_pending drain merge_` placeholder in Tool Telemetry with a note: `_Checkpoint telemetry merged from N block(s): HH:MM, HH:MM, ..._`
8. **Delete the checkpoint file only after all sessions for that date in the batch are fully processed.** If sessions from that date remain unprocessed in the current batch, do not delete yet.
9. **NEVER delete the checkpoint file for TODAY'S date — merge from it and leave it in place.** Today's file is the live append target for every session still running, including the one that spawned this drain. Deleting it destroys telemetry events written after your read, and the writing session gets no error: `cat >> <deleted-path>` silently recreates the file, so the events land in a new inode nobody will ever drain. The whole point of appending events to disk immediately is surviving compaction — a drain that deletes the file defeats exactly that. Only delete checkpoint files whose date is strictly BEFORE today; today's is cleaned up by a later drain, on a later day, when nothing is writing to it. (Evidence: 2026-07-29 — a drain deleted `checkpoint-2026-07-29.md` mid-session; the parent session's two subsequent redirect events vanished, and the next drain reported the file as never having existed. Recovered only because the same events had been written independently into the session file's Reflections.)

If no checkpoint file exists for a session's date, replace the placeholder with: `_No checkpoint file for this date._`

### Step 3b — Merge subagent telemetry into session files

Subagent reports accumulate in `~/.claude/subagent-reports/` across all sessions and are never auto-cleared. **Do not glob by modification time alone** — a report from a prior session may have been read (not written) more recently, refreshing its mtime without belonging to the current session.

For each session file in the batch:

1. **Determine the time window:**
   - Upper bound: this session's `queued_at`
   - Lower bound: the immediately preceding session's `queued_at` in the batch (sort all sessions chronologically, take the prior one), or `queued_at - 6h` as fallback if this is the oldest session in the batch
2. Find all reports in `~/.claude/subagent-reports/` whose mtime falls within `[lower, upper]`.
3. Also check legacy locations (backward compat with pre-2026-04-30 worktree reports):
   ```bash
   find $HOME/Projects -maxdepth 2 -path "*/tmp/subagent-report-*.md" 2>/dev/null
   ```
   Apply the same time window filter.
4. **Cross-session awareness:** if multiple sessions in the batch have overlapping windows (concurrent sessions), a report may match more than one. Attribute it to the first session whose window it falls in and mark it: `[ambiguous — concurrent sessions, attributed to earliest match]`. Do not duplicate it across multiple session files.
5. For each matched report:
   - Read its `## Telemetry` section. If missing (legacy), note `[legacy report — no Telemetry section]`. Do NOT invent values.
   - Append its `### Learning events` to the session file's Reflections, prefixed with `[<agent-phase> · <model>]`
   - Sum its tool-telemetry counts into the session file's Tool Telemetry totals
   - List any "Validation steps skipped" verbatim under Tool Telemetry
6. Append provenance note (replacing or supplementing the checkpoint note): `_Subagent telemetry merged from: <list of phase names>. Window: <lower> – <upper>._`

If no reports match, note: `_No subagent reports in window <lower> – <upper>._`

### Step 3c — Merge pre-compaction telemetry extracts into session files

The PreCompact hook (`pre-compact-snapshot.sh`) writes a MECHANICAL telemetry extract to `~/.claude/precompact-captures/telemetry-{date}-{HHMMSS}-{session8}.md` every time a session compacts (auto or manual). Each extract carries transcript-derived telemetry captured at compaction time — exact tool tally, session metrics, files touched, verbatim user prompts, bash commands run, and tagged reflection events — independent of what the model remembered to self-report. A long session may compact several times, producing several extracts; short sessions that never compact have none (expected — the model's own counts suffice there).

For each session file in the batch:

1. Use the SAME `[lower, upper]` time window as Step 3b.
2. Find all extracts in `~/.claude/precompact-captures/` whose filename timestamp (`{date}-{HHMMSS}`) falls within the window. If sessions overlap, disambiguate using the `**Session:**` UUID line inside each extract; attribute each extract to exactly one session.
3. For each matched extract:
   - **Tool Telemetry and Session Metrics are mechanical — treat them as authoritative.** Where they conflict with the model's from-memory counts already in the session file, REPLACE the estimate with the extract's number and mark it `[mechanical — precompact extract]`. Exact counts beating recalled ones is the whole point of the extract.
   - Merge **Files Touched** into the session's "Files modified" list.
   - Fold **Tagged Reflection Events** into Reflections, but DEDUPE against events already merged from the checkpoint in Step 3a (the extract also greps the checkpoint, so overlap is expected). Prefix genuinely new ones `[precompact · HHMMSS]`.
   - Scan the **User Prompts** and **Bash Commands** sections for redirect / validation-skip signals the model did not self-report, and add any found as Reflections.
4. Provenance note (supplementing 3a/3b): `_Pre-compaction telemetry merged from N extract(s): HHMMSS, ..._`
5. Do NOT delete extracts — like subagent reports (3b) they are matched by window, and the hook rotates them at 30 files. Window non-overlap prevents double-merge across drains.

If no extracts match, note: `_No pre-compaction extracts in window <lower> – <upper>._`

### Step 4 — Create GitHub issues

For each session that discovered untracked bugs, tasks, or ideas:
```bash
gh issue create --repo <owner/repo> --title "<title>" --label "<label>" --body "<body>"
```
Labels: `bug`, `task`, `enhancement`, `idea`, `planning`, `deferred`. Skip if nothing new across all sessions.

### Step 5 — Update next-steps.md

If any session touched example-app, update `~/Projects/example-context/next-steps.md` **once**, incorporating all sessions:
- Bump **Last Updated** to the most recent session timestamp, linking the most recent session file
- Update **Immediate Next** based on the aggregate of all sessions
- Add all sessions to **Done** section in chronological order

Follow `~/Projects/dev-reference/conventions/next-steps-convention.md`.

### Step 6 — Sweep example-context

If any session touched example-app, walk `~/Projects/example-context/architecture/` and `~/Projects/example-context/context/`. For each file, ask: "did any of the queued sessions change something that warrants updating it?"

Files to check:
- `app-behavior-map.md` — new or changed user-facing behavior
- `codebase-map.md` — new files, moved files, new components
- `api-design.md` — new or modified API endpoints
- `database-schema.md` — new migration applied
- `system-overview.md` — infra changes, new services, new workflows
- `posthog-events-spec.md` — new analytics events
- `product-changelog.md` — user-visible features shipped
- `Design Guide.md` — design token or UI pattern changes

Bump `**Last Updated:**` on anything touched. Skip files that didn't change.

### Step 7 — Update ROADMAP

If any session touched a project and completed a feature or changed priorities in it, update that project's own `ROADMAP.md` (e.g. a session that touched example-app updates `~/Projects/example-app/ROADMAP.md`). Skip a project with no roadmap impact, and skip entirely if no session in the batch had roadmap impact.

### Step 8 — Commit example-context and dev-reference

```bash
git -C ~/Projects/example-context status --short
git -C ~/Projects/dev-reference status --short
```

For each repo with changes: stage only files modified in this drain, commit with a message like `"Batch session sync: <date> — <N> sessions"`, push.

### Step 9 — Copy session files to claude-config

```bash
for entry in <all session_file paths>; do
  cp "$entry" ~/Projects/claude-config/sessions/
done
```

### Step 10 — Sync claude-config

```bash
git -C ~/Projects/claude-config status --short
git -C ~/Projects/claude-config add -A
git -C ~/Projects/claude-config commit -m "Sync claude config — batch drain <YYYY-MM-DD-HH-MM> (<N> sessions)"
git -C ~/Projects/claude-config push
```

### Step 11 — Clean up

The subagent sandbox blocks both `rm` and redirect-truncate (`> file`). Use the Write tool with empty content instead:

- Write empty string to `~/.claude/capture-queue-processing.jsonl`
- Write empty string to `~/.claude/drain.lock`

Do NOT use `rm` or `> file` — both are blocked.

### Step 12 — Check for new queue entries

After releasing the lock, check if new entries arrived while the drain was running:

```bash
wc -l < ~/.claude/capture-queue.jsonl 2>/dev/null || echo 0
```

If new entries exist (other sessions queued while drain was running), report the count so the user can run `/drain-captures` again or wait for the next session-capture to trigger it.

### Step 13 — Report and print resume prompts

Report back:
- How many sessions were drained
- What was updated (which files, which repos)
- Any GitHub issues created
- Resume prompts for each session that had a "How to Resume" section, in order

## Manual invocation

Run `/drain-captures` from any terminal at any time to force-process the queue. Useful when you want to drain immediately without waiting for the next session-capture to trigger it.

## Error handling

If any step fails (e.g., git push conflict), continue processing remaining steps and report the failure at the end. Do not delete the queue working file on error — report the path so entries can be recovered.
