# Never symlink `~/.claude/settings.json` (Claude Code drops symlinked config)

**Rule:** `~/.claude/settings.json` (and project `.claude/settings.json`) must be a **regular file**. Do NOT replace it with a symlink to a versioned copy.

**Why:** Claude Code re-reads `settings.json` when it changes and does **not honor a symlinked settings file** — it silently drops the config it would have loaded. The visible symptom is partial: e.g. a custom `statusLine` stops running, so a context-window progress bar / usage stats rendered by `statusline.sh` vanish while a default statusline remains. The JSON content can be byte-for-byte identical to before; the breakage is purely the file *type* (regular → symlink).

**Evidence:** 2026-06-22 (#934) — symlinked `~/.claude/settings.json` → `~/Projects/claude-config/settings.json` to make live config git-tracked ("can't silently vanish"). Statusline's context bar + usage stats disappeared immediately. Reverting symlink → regular file (identical content) restored it on the next render.

**Diagnosis lesson (separate from the fix):** when a user reports breakage tightly correlated in time with a change you made, weight the **timing correlation** over a "but the content is unchanged" alibi. The content diff was clean here, which nearly led to dismissing the real cause. The variable that changed was the file type, not the content.

**If you want live config git-tracked anyway:** keep the live file a regular file and **copy-on-commit** (a one-time or hook-driven `cp ~/.claude/settings.json <repo>/settings.json` before committing the repo copy). The repo copy is a snapshot/backup; the live file is never a symlink. Same applies to any tool whose config loader may not follow symlinks — verify loader behavior before symlinking config.
