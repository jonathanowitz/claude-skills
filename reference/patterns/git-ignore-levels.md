# Git Ignore Levels & the Already-Tracked Gotcha

## When to use

- A file shows as **modified every session** and you keep wishing it would just stop (e.g. `.claude/settings.local.json`).
- Deciding where a not-yet-committed file belongs: shared ignore, personal ignore, or actually commit it.
- A file "won't `git add`" or mysteriously won't show up, and you need to know which rule is hiding it.
- Triaging a pile of untracked files (scratch vs deliverable vs PII) before they get lost to a `--force` worktree removal.

## The three ignore levels

Git has three places to ignore files, by **who** the ignore is for:

| Level | File | Tracked? | Use for |
|---|---|---|---|
| **Shared** | `.gitignore` (committed) | Yes — everyone gets it | Build artifacts, deps, secrets, anything every clone should ignore |
| **Personal, per-repo** | `.git/info/exclude` (untracked, local) | No | *Your* scratch files in *this* repo that others might legitimately want |
| **Personal, all repos** | `~/.config/git/ignore` (global; set via `git config --global core.excludesfile`) | No | `.DS_Store`, editor junk, machine-wide noise |

Rule of thumb: **shared concern → `.gitignore`; personal concern → `info/exclude` or global.** Don't put your personal scratch patterns in the committed `.gitignore`, and don't rely on the shared `.gitignore` for machine-specific noise.

## The gotcha: a `.gitignore` rule does NOT ignore an already-tracked file

This is the one that bites. If a file is **already tracked**, adding it to `.gitignore` does **nothing** — Git keeps tracking it and it keeps showing as modified. Ignore rules only apply to *untracked* files.

Fix — stop tracking it but keep it on disk:

```bash
git rm --cached <file>      # untrack; working-tree copy stays
git commit -m "stop tracking <file> — #NN"
# now the existing .gitignore rule takes effect
```

(`git rm --cached` removes from the index only. Plain `git rm` would delete the working file too — not what you want here.)

**Evidence (2026-06-19, example-app #910):** `.claude/settings.local.json` was committed back in #778 and the `.gitignore` `.claude/*` rule looked like it should have ignored it — but because it was already tracked, it churned +284 lines of local permission-allowlist every session. `git rm --cached` + the existing rule fixed it permanently.

## The diagnostic: `git check-ignore -v`

When you don't know whether/why a file is ignored:

```bash
git check-ignore -v <file>
# prints e.g.:  .gitignore:116:tools/x/contacts.csv	tools/x/contacts.csv
# (source-file : line-number : pattern  TAB  path)
```

No output = the file is **not** ignored. Use it to *confirm* an ignore landed on the right file by the rule you intended — especially after writing a tricky negation pattern.

## Re-including specific files from an ignored directory

To ignore a directory's bulk but keep certain files (e.g. commit parser *scripts*, ignore the data), you must re-include the **directories** too — Git can't re-include a file whose parent dir is excluded:

```gitignore
tools/parser-fixtures/**
!tools/parser-fixtures/**/        # re-include subdirs so git can descend
!tools/parser-fixtures/**/*.py    # then re-include the files you want
!tools/parser-fixtures/**/*.cjs
!tools/parser-fixtures/**/*.md
```

## Triage discipline (scratch vs deliverable vs PII)

Before hiding untracked files in `info/exclude`, look at what they are — `info/exclude` is for *throwaway*, not for valuable-but-uncommitted work (which is exactly what gets eaten by a `--force` worktree removal; see [[git-fsck-recovery]]).

- **Deliverable** (fixtures, templates, real tools) → commit it.
- **PII / secrets** (contact CSVs with emails/phones, anything personal) → ignore it in the shared `.gitignore` so it can never be committed by accident. Grep first: `grep -lEi "@|[0-9]{3}[-.][0-9]{3}[-.][0-9]{4}" *.csv *.md`.
- **Large derived data** (parsed JSON, PDFs, dumps) → ignore (matches the "large, not source code" policy).
- **Genuinely personal scratch** → `.git/info/exclude`.

## See also

- [[git-fsck-recovery]] — recovering work already lost (the failure mode this prevents).
