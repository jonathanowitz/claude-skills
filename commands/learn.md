---
description: Capture a reusable pattern or insight into dev-reference while it's fresh
allowed-tools: [Read, Glob, Grep, Write, Edit, AskUserQuestion]
---

# Learn

Capture a reusable pattern, debugging technique, codebase gotcha, or workflow insight into `~/Projects/dev-reference/` immediately — before it fades into a session transcript.

**Usage:** `/learn` or `/learn <brief description of what was learned>`

## Why This Exists

Hard-won insights currently take days to reach dev-reference: discover → finish session → write summary → tag reflection → wait for `/maintenance` → update dev-reference. This skill short-circuits that pipeline. Capture it now, use it next session.

## Step 1: Identify What Was Learned

If the user provided a description in the arguments, use that. Otherwise, look at the current session for:
- A debugging approach that worked (or a dead end worth documenting)
- A codebase gotcha or API quirk that surprised you
- A tool behavior or configuration detail that wasn't obvious
- A convention that should be standardized
- A pattern that solved a recurring problem
- A correction from USER that applies broadly

**Filter aggressively.** Only capture patterns that will save time in future sessions. Skip:
- Trivial fixes (typos, simple syntax errors)
- One-time issues (specific API outages, transient bugs)
- Project-specific details that belong in that project's CLAUDE.md
- Things already documented in dev-reference (grep first)

## Step 2: Classify and Route

Determine where this belongs based on what it is:

| Type | Target Directory | Examples |
|------|-----------------|----------|
| **Code/UI pattern** | `patterns/` | Event delegation, scroll-snap, caching strategies |
| **Convention/standard** | `conventions/` | Naming rules, file structure, testing requirements |
| **Tool/environment knowledge** | `guides/` | Model quirks, CLI flags, deployment gotchas |
| **Process/workflow improvement** | `workflows/` | New checklist items, protocol additions |
| **Debugging technique** | `conventions/` or `guides/` | Diagnostic approaches, root cause patterns |

## Step 3: Check for Existing File

Before creating a new file, search for an existing file that covers this topic:

1. `Grep` for key terms across `~/Projects/dev-reference/`
2. If an existing file covers the same area, **update it** — add the new insight as a new section or bullet point. Include evidence (date, issue number, what happened).
3. Only create a new file if no existing file covers this topic.

**This is critical.** Dev-reference has a "one file per concept" rule. Adding a new section to `e2e-test-conventions.md` is almost always better than creating `e2e-timing-gotcha.md`.

## Step 4: Write the Pattern

### If updating an existing file:

Add the insight in the appropriate section. Use the file's existing format. Include:
- The pattern/rule itself (imperative — "Do X" or "When Y, do Z")
- **Why** it matters (what goes wrong without it)
- **(Evidence: date — brief description of the incident)**

### If creating a new file:

Use this structure:

```markdown
# <Pattern Name>

<1-2 sentence description of what this pattern solves>

## When to Use
- [Trigger conditions — when should Claude/USER reach for this?]

## The Pattern
[The actual technique, convention, or approach. Be specific and actionable.]

## Why This Matters
[What goes wrong without this. Concrete consequences, not theoretical risks.]

## Evidence
- YYYY-MM-DD — [What happened that taught us this]

## See Also
- [Links to related dev-reference files, if any]
```

Keep it short. A good pattern file is 20-60 lines. If it's longer, it's probably two patterns.

**Filename:** Use kebab-case descriptive names: `content-hash-caching.md`, `supabase-rls-gotchas.md`, `playwright-state-management.md`.

## Step 5: Verify

1. `Read` the file back to confirm the edit landed correctly
2. If a new file was created, verify it's in the right directory
3. `Grep` for the key insight to confirm it's findable by future sessions

## Step 6: Report

Tell USER:
- What was captured and where it was written
- Whether it was a new file or an update to an existing file
- The one-line summary of the pattern (so USER can confirm it's correct)

## Guidelines

- **Speed over perfection.** A rough pattern captured now beats a polished one captured never. It can be refined during `/maintenance`.
- **Evidence is mandatory.** Every pattern must have at least one evidence entry with a date. Patterns without evidence are opinions.
- **Don't duplicate.** If it's already in dev-reference, don't re-add it. If the existing version is incomplete, update it.
- **Cross-project only.** If the insight only applies to one project, it belongs in that project's CLAUDE.md, not dev-reference.
- **Grep before writing.** Spend 10 seconds searching to avoid duplication. This is a hard gate.
