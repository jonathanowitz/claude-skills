# Cache Report

Decompose Claude Code cache-read cost: what's filling the context window, which sessions are heaviest, and how much of the every-turn fixed prefix is yours to trim. Use this when a weekly limit burns fast and you want to know *why* — cache reads dominate cost-weighted usage (the whole context is re-read on every turn at $0.50/Mtok for Opus), so the levers are session length, prefix size, and what accumulates in-session.

Read-only. Parses `~/.claude/projects/**/*.jsonl` locally — no network, no writes.

## Steps

### 1. Run the analyzer

```bash
python3 ~/Projects/claude-config/tools/cache-telemetry.py --days 14
```

Optional args: `--days N` (default 14), `--top N` heaviest sessions to list (default 12), `--agg N` sessions to aggregate the "what fills the context" breakdown over (default 20). For a weekly-limit investigation, `--days 7` matches the limit window.

### 2. Interpret the output for USER

Report in plain language, leading with the answer, not the mechanics:

- **Is it turn-count or context-size?** Peak context is capped by `autoCompactWindow` (~266k). If peaks sit at the cap, the cost driver is *turn count × sustained context*, not a runaway window. Cost ≈ turns × avg-context, so a 1,800-turn session is ~4× a 450-turn one at the same floor.
- **What fills the context** — read the dwell-weighted ("%cache-read cost") column, not volume. Typical split: file-reads + assistant tool-call args (Write/Edit content) + bash-output ≈ 80% of conversation content. Subagent output being tiny (~2%) confirms search-via-subagent keeps file-dumps out of the main context — a good pattern, not a problem.
- **Fixed prefix** — the system prompt + tool schemas + CLAUDE.md/MEMORY re-read every turn. Report its % of total cost AND the split between the trimmable instruction corpus (global CLAUDE.md + rules + project CLAUDE.md + MEMORY.md) and the immovable harness residual. Be honest about magnitude: only the instruction corpus (~⅕–¼ of the prefix) is USER's to cut.

### 3. Name the levers, ranked by real magnitude

1. **Fewer turns per session** (`/clear` at task boundaries) — the multiplier on everything; the dominant lever.
2. **Trim the instruction corpus** — every 1k cut off the prefix saves 1k × (turns) per session. Point at the biggest files from the output (usually global CLAUDE.md and MEMORY.md). Modest (~8% of total) but free.
3. **In-session hygiene** — targeted Reads over whole-file reads; small Edits over full-file Writes (Write drops the whole file into context as tool args, where it dwells); keep bash output lean.

Do not recommend disabling autocompact — it's already holding the ceiling. Do not conflate cost-weighted local estimate with Anthropic's server-side weekly-limit %.
