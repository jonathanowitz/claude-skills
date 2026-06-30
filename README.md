# Claude Skills

My personal library of slash commands, skills, hooks, and reference docs for [Claude Code](https://claude.com/claude-code). Shared publicly so others can study, copy, or adapt the workflow.

**Not a framework.** This is one person's actual working setup, scrubbed for public sharing. Treat it as a reference implementation, not a prescription.

## What's here

```
commands/     Slash commands (~/.claude/commands/*.md)
skills/       Skills (~/.claude/skills/*)
hooks/        Example hook scripts — reference only, not auto-installed
reference/    Workflows, conventions, templates, patterns pulled from my
              dev-reference library. These are what the commands link to.
sync.sh       Rebuild this repo from my private sources (maintainers only)
install.sh    Symlink commands + skills into your ~/.claude/
```

## The workflow

The commands are designed to compose into a pipeline:

1. **`/frame`** — Capture a rough problem as a one-page brief. No solutions yet.
2. **`/shape-project`** — Turn the brief into a shaped plan with a breadboard sketch and independent review. This is the "think before you build" gate.
3. **`/pre-mortem`** — 7 expert personas independently identify failure modes before implementation.
4. **`/implement-plan`** — Decompose the shaped brief into vertical slices with test plans.
5. **`/implement`** → `/implement-stubs` → `/implement-slice` → `/implement-wire` → `/implement-ship` — Execute slice by slice, test-first, with a RED-GREEN gate.
6. **`/checkpoint`** — Mid-session telemetry snapshot without ending the session. Run after major milestones; `/session-capture` picks these up and merges them automatically.
7. **`/session-capture`** — End-of-session telemetry + reflections, feeds into the next session.
8. **`/maintenance`** — Periodically analyze captured sessions for drift patterns, update rules.

Supporting commands: `/check`, `/validate`, `/test-coverage-review`, `/second-opinion`, `/review-tests`, `/bug-squash`, `/tidy`, `/next`, `/issue`, `/log-post`, `/scan`, `/learn`, `/project`, `/post-mortem`, `/night-shift`, `/interactive-debug`, `/slack-copy`, `/voice-diff`, `/recommend-model`, `/checkpoint`.

Skills (auto-invoked): `doc-consolidate`, `file-cleanup`, `memory-transfer`, `session-capture`, `next`.

## Install

Requires Claude Code already installed.

```bash
git clone https://github.com/<your-username>/claude-skills.git
cd claude-skills
./install.sh
```

This symlinks `commands/` and `skills/` into your `~/.claude/`. Existing files are backed up first. `git pull` keeps your install in sync.

Hooks and `reference/` are NOT auto-installed — hooks are environment-specific, and reference docs assume a particular directory layout. See "Adapting" below.

## Adapting to your setup

The commands reference paths like `~/Projects/dev-reference/workflows/...`. For the commands to work, you need that directory tree. Two options:

**Option A — Use the reference/ tree here.** Copy or symlink `reference/` to `~/Projects/dev-reference/`:
```bash
ln -s "$(pwd)/reference" ~/Projects/dev-reference
```

**Option B — Fork your own reference library.** The files in `reference/` are opinionated (vertical slice methodology, specific test conventions, etc.). Fork this repo, edit `reference/` to match how you work, and re-run `install.sh`.

### CLAUDE.md

The commands assume a global `~/.claude/CLAUDE.md` with certain conventions. My scrubbed version is in [`CLAUDE.example.md`](CLAUDE.example.md) — copy it to `~/.claude/CLAUDE.md` and edit the placeholders.

### Hooks

Hooks in `hooks/` are examples. Read them, decide which ones match your workflow, then register them in `~/.claude/settings.json`. They reference paths and tools (e.g., Gemini CLI) that you may not have.

## Maintenance

This repo is derived. Source of truth is my private `claude-config` + `dev-reference` repos. I run `./sync.sh` periodically to rebuild the public tree (scrubs identifiers, respects an exclusion list). The scrub rules and exclusion list name the private terms/files they operate on, so they live in **gitignored** files (`scrub.sh`, `.syncignore`) that the public repo doesn't carry — `sync.sh` is maintainers-only. Don't edit files in `commands/`, `skills/`, `hooks/`, or `reference/` directly — edits get wiped on next sync. If you want to contribute back, open an issue.

## Credits

Workflow influences: Shape Up (Basecamp), vertical slice methodology, test-driven development. Many commands were shaped in dialogue with Claude over many sessions.

## License

MIT.
