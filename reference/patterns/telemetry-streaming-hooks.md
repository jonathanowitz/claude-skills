# Telemetry Streaming Hooks

Two hooks that close the "telemetry lost on context compaction / forgotten mid-session" gap that maintenance-2026-05-12 surfaced (only ~6% of sessions actually wrote checkpoint events; the rest relied on the agent self-triggering an advisory rule and almost never did).

## Hook 1: PreCompact telemetry marker

**File:** `~/.claude/hooks/pre-compact-snapshot.sh`
**Event:** `PreCompact` (fires before Claude auto-compacts conversation context)

On compaction, appends a marker line to today's checkpoint file:

```
<!-- compaction HH:MM:SS -->
- **[compaction-event]:** auto compaction triggered. Session: `<id>`. Transcript: `<jsonl path>`. cwd: `<cwd>`. → /session-capture should parse the transcript jsonl for ...
```

The transcript jsonl at `~/.claude/projects/<project-hash>/<session-uuid>.jsonl` contains every user message, every tool call, every response. The marker is a *pointer* — `/session-capture` reads it during the existing "Merge Checkpoint Telemetry" step and can reconstruct any events the agent never wrote down.

**Lossless safety net.** Zero data loss on compaction; runs automatically without agent involvement.

## Hook 2: UserPromptSubmit redirect nudge

**File:** `~/.claude/hooks/redirect-nudge.sh`
**Event:** `UserPromptSubmit` (fires on every user message)

Scans the user's message for corrective phrases. On match, emits a one-line `additionalContext` system reminder telling the agent to append a `redirected:` event to today's checkpoint file before its next substantive action.

**What it catches:**
- Start-of-message correctives: `^no[,.!]`, `^wait[,.!]`, `^stop[,.!]`, `^Actually[,.!]`, `^don't `, `^Hold on`
- Mid-message correctives: "I thought you", "we already (did|fixed|shipped|...)", "didn't I", "you forgot/already", "not what I (meant|wanted|asked)", "let me clarify", "to be clear", "we figured this out"
- All-caps emphatic: `\bNO\b`, `\bSTOP\b`, `\bWAIT\b`

**What it skips:**
- Slash commands (`^/maintenance`, etc.)
- Benign uses of trigger words ("no problem", "I'll wait until", "stop the dev server")

**False-positive cost:** harmless — agent sees a one-line nudge it can ignore.
**False-negative cost:** current state — event lost.

The patterns are conservative; tighten further by editing the `PATTERNS` array in the hook.

## How they compose with `/session-capture`

`/session-capture` already has a "Merge Checkpoint Telemetry" step (command line 76) that reads `~/.claude/checkpoints/checkpoint-$(date +%Y-%m-%d).md`, merges its events into the session summary's Reflections section, and deletes the file. Both hooks write to this same file format, so no changes to `/session-capture` are needed.

## Disable temporarily

Comment out the relevant block in `~/.claude/settings.json` under `"hooks"` and reload Claude Code. Or `chmod -x` the specific hook file.

## Phase 3 (deferred)

A `Stop` hook that parses the transcript jsonl and auto-extracts events with zero agent involvement. The infrastructure is in place — transcript path is available to every hook, jsonl format is parseable. Deferred until Phase 1+2 prove insufficient.

## Evidence

- maintenance-2026-05-12.md § New Gap #2: 6% session compliance on the "Write events to disk immediately" CLAUDE.md instruction. The instruction is itself an advisory rule.
- The pattern of mechanical-100% vs advisory-55% applies again. Hook = mechanical.
