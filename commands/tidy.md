---
description: Clean up completed temp files and flag stale briefs/ideas
allowed-tools: [Read, Glob, Grep, Bash, Edit, AskUserQuestion]
---

# Tidy Up

Scan for completed temp files to delete and stale briefs/ideas to review.

## Instructions

### Phase 1: Scan temp files for cleanup

1. List all files in the project's `tmp/` directory
2. For each file, check these signals (in priority order):

   **Skip signals (never delete):**
   - Filename contains `(keep)` → skip entirely

   **Done signals (candidate for deletion):**
   - `- [x] Done` checkbox near the top of the file
   - All step/task checkboxes in the file are `[x]` (no unchecked `[ ]` remain)

   **GitHub cross-reference signals:**
   - Extract issue numbers (`#NN`) from the file
   - Run `gh issue view NN --repo USER/example-app --json state -q '.state'` for each
   - If all referenced issues are `CLOSED`, flag as a deletion candidate
   - For validation files referencing a PR, check if the PR is merged

   **Companion file signals:**
   - If a `.md` file is marked for deletion, also flag its companion `.js` file (same base name)

   **Mockup signals:**
   - For `mockup-*.html` files, check whether the related brief has shipped (moved to `briefs/archive/` or marked complete)

3. Build a deletion list with reasons for each file

### Phase 2: Flag stale briefs and ideas

1. Read `project-ideas.md` — flag any Active Ideas older than 30 days that haven't been touched
2. Scan `briefs/` directory:
   - For each brief, check if it has any open GitHub issues (`gh issue list --repo USER/example-app --search "<brief name>" --json number,state`)
   - Flag briefs with no open issues AND no modifications in the last 30 days as potentially stale
   - Don't flag briefs in `briefs/archive/` — those are already handled

### Phase 3: Write findings to a review file (DO NOT act yet)

Write a markdown file to `tmp/tidy-review-YYYY-MM-DD.md` with checkbox lists so USER can toggle them in any markdown editor.

**File format:**

```markdown
# Tidy Review — YYYY-MM-DD

Toggle checkboxes below, then tell me to go.

## Delete Temp Files

- [x] `filename.md` — #NN closed, shipped
- [ ] `filename.js` — No clear done signal, context about what it is
- ~~`filename (keep).md` — Marked (keep), skipped~~

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
