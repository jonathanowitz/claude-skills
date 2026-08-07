---
description: Clean up completed temp files and flag stale briefs/ideas
allowed-tools: [Read, Glob, Grep, Bash, Edit, AskUserQuestion]
---

# Tidy Up

Scan for completed temp files to delete and stale briefs/ideas to review.

## Instructions

### Phase 1: Scan temp files for cleanup

**Do not classify these files by reading them yourself.** Classification lives in `~/.claude/hooks/tmp-scan.sh`, which `/dream` also calls. That sharing is the point: a file `/tidy` calls safe must never be a file an unattended 2 AM run deletes, and the only way to guarantee that is for both to ask the same script the same question. If you find yourself judging a file from its contents here, the script is missing a signal — fix the script and its fixtures, don't work around it.

The script is a pure function of (files, time source, issue states). It makes no network calls of its own, so you supply the issue states.

1. **First pass — discover referenced issues.**

   ```
   ~/.claude/hooks/tmp-scan.sh --dir=<project>/tmp
   ```

   Read the `issues` keys off the JSON to get every `#NN` mentioned anywhere in `tmp/`.

2. **Fetch those issue states.** `gh issue view NN --repo <tracker> --json state -q '.state'` for each. `<tracker>` = the current project's issue tracker per the orbit rule in `references/product-json.md` — `USER/example-app` for the example-app orbit {example-app, example-context, dev-reference, claude-config}, otherwise the repo's own slug. For validation files referencing a PR, check whether the PR is merged and treat merged as `CLOSED`.

3. **Second pass — the authoritative one.**

   ```
   ~/.claude/hooks/tmp-scan.sh --dir=<project>/tmp --issue-states=1027=CLOSED,1221=OPEN
   ```

   Leave `--time-source` at its `mtime` default. You are running against a live working tree, where mtime is correct. (`--time-source=git` exists for `/dream`'s night half, which runs in a fresh clone where `git clone` has stamped every file with checkout time — mtime there silently reports every file as 0 days old.)

4. **Read the verdicts.** Each file comes back with `verdict`, `signals[]`, `age_days`, `days_unchecked`, and `issues{}`:
   - `skip` — never delete: a `(keep)` marker, an active `keep-until-issue` park, OR an open cited issue (`open-issue-keep`); render with strikethrough
   - `delete` — a clear done signal; pre-check as `- [x]`
   - `review` — no clear signal; leave as `- [ ]` for USER to judge

   Use `signals[]` verbatim as the reason text — it is what the script actually keyed on, so the review file states the real basis rather than a paraphrase of it.

   One signal explains an otherwise-surprising `skip`: `open-issue-keep` means the file references an issue that is not confirmed closed (open OR unknown state), so it was kept rather than surfaced — **an open cited issue is a keep, not a triage question** (USER 2026-08-05: "if something is still open, you shouldn't ask me if I want to archive it"). This holds even when the file also carries a done signal (a ticked `- [x] Done`, or every checkbox ticked). It self-expires like a `keep-until-issue` park: once every cited issue closes, the file re-earns `issues-all-closed` and, if it has a done signal, becomes a `delete` on the next pass. (History: a done box used to outrank an open issue → `delete`; 2026-07-25 that was reversed to an open-issue *veto* → `review`; 2026-08-05 the veto was strengthened to a keep → `skip`. The live trigger was `dream-workflow-framing-2026-07-24.md`, classified `delete` while #1221 was open and its brief cited that very file.)

5. **Two signals still need your judgment, because the script deliberately refuses to guess:**
   - `mockup-needs-brief-state` — check whether the related brief has shipped (moved to `briefs/archive/` or marked complete), then decide the checkbox.
   - `untracked-fallback` — only appears under `--time-source=git`; the file has no commit history, so its age fell back to mtime. Treat that age as unreliable rather than as zero.

6. **Report `days_unchecked`** in the review file for anything still carrying an unchecked `- [ ] Done` box. A file that has sat unchecked for 90 days is the thing worth surfacing — it is how "I'll finish this later" becomes visible instead of accumulating silently.

### Phase 2: Flag stale briefs and ideas

1. Read `project-ideas.md` — flag any Active Ideas older than 30 days that haven't been touched
2. Scan `briefs/` directory:
   - For each brief, check if it has any open GitHub issues (`gh issue list --repo <tracker> --search "<brief name>" --json number,state`)
   - Flag briefs with no open issues AND no modifications in the last 30 days as potentially stale
   - Don't flag briefs in `briefs/archive/` — those are already handled

### Phase 3: Write findings to a review file (DO NOT act yet)

Write a markdown file to `tmp/tidy-review-YYYY-MM-DD.md` with checkbox lists so USER can toggle them in any markdown editor.

**File format:**

```markdown
# Tidy Review — YYYY-MM-DD

Toggle checkboxes below, then tell me to go.

## Delete Temp Files

- [x] `filename.md` — issues-all-closed (#NN closed)
- [ ] `filename.js` — no signal, 47 days unchecked
- ~~`filename (keep).md` — keep-marker, skipped~~

## Archive Briefs

- [x] `brief-name.md` — #NN closed, shipped
- [ ] `other-brief.md` — Deferred, no recent activity
```

**IMPORTANT:** Use standard markdown checkbox syntax (`- [x]` and `- [ ]`) so checkboxes are interactive in Obsidian/VS Code/GitHub. Do NOT use tables — checkboxes inside table cells don't render as toggleable. Use strikethrough (`~~`) for skip items (no checkbox needed).

**Checkbox defaults:**
- `- [x]` for items with clear done signals (issue closed, all checkboxes done, shipped)
- `- [ ]` for items that need USER's judgment (no clear signal, deferred features, active briefs)
- `~~` strikethrough for `(keep)` files (cannot be selected)

After writing the file, tell USER it's ready for review and STOP. Do not proceed until he says to go.

### Phase 4: Act on reviewed file

**HARD GATE: Do not delete or archive anything until USER explicitly says to go.**

1. Re-read `tmp/tidy-review-YYYY-MM-DD.md` to pick up USER's edits
2. Delete files where the checkbox is `- [x]` under "Delete Temp Files"
3. Move briefs where the checkbox is `- [x]` under "Archive Briefs" to `briefs/archive/`
4. Delete the tidy review file itself after acting
5. List exactly what was removed/archived so USER can verify

## Guidelines

- **Never delete `(keep)` files.** The user explicitly marked them.
- **Never delete without explicit text approval.** Present the list, then STOP and wait for USER to reply in plain text. Do not use AskUserQuestion for the delete confirmation — it's too easy to misread the response. Wait for a real reply.
- **Be conservative with briefs.** A brief might be inactive but still relevant — flag for review, don't assume it's stale.
- **Check git status first.** If a temp file has uncommitted changes, mention it — the user may be mid-work.
- **GitHub CLI path:** May need `export PATH="$PATH:/c/Program Files/GitHub CLI"` before running `gh` commands.
- **Scope:** This skill operates on the current project's `tmp/` and `briefs/` directories. It does not touch `~/.claude/` files, session captures, or other projects.
