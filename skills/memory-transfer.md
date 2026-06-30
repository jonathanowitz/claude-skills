# memory-transfer

Scan memory files for generalizable knowledge and promote it to dev-reference or claude-config.

## Usage

```
/memory-transfer
```

## What This Does

Memory files accumulate tooling lessons, workflow gotchas, and technical discoveries alongside user preferences and project state. This skill identifies entries that are **general-purpose** (not user- or project-specific) and proposes moving them to the canonical knowledge base where they benefit all future sessions.

## Process

### Step 1: Scan all memory directories

Read memory files from:
- `~/.claude/projects/*/memory/*.md` (all project memories)
- Focus on `type: feedback` entries — these most often contain generalizable knowledge

For each memory file, classify as:

| Category | Definition | Destination |
|----------|-----------|-------------|
| **General tooling** | CLI behavior, model quirks, API gotchas | `dev-reference/guides/` (model-selection.md, etc.) |
| **Workflow pattern** | Process lessons applicable across projects | `dev-reference/workflows/` or `dev-reference/conventions/` |
| **Claude config** | Settings, hooks, skill improvements | `claude-config/` (appropriate file) |
| **User preference** | How USER wants to work | Keep in memory |
| **Project-specific** | Tied to a specific codebase or feature | Keep in memory |

### Step 2: Present findings

For each general-purpose entry found, report:
```
MEMORY: [file path]
CONTENT: [1-line summary]
PROPOSED DESTINATION: [target file in dev-reference or claude-config]
REASON: [why this is general, not project-specific]
```

Group by destination file so related entries can be merged in one edit.

### Step 3: Execute transfers (with approval)

For each approved transfer:
1. Add the knowledge to the destination doc (merge into existing section, don't create new files unless no good home exists)
2. Delete the memory file
3. Remove the pointer from the project's `MEMORY.md` index

### Step 4: Report

```
Transferred: N entries → dev-reference/claude-config
Kept: N entries (user/project-specific)
Files updated: [list]
```

## Decision Framework

**Promote to docs when:**
- The lesson applies to any project using the same tool (Claude CLI, Gemini, Supabase, Vercel, etc.)
- Someone else hitting the same issue would benefit from finding it in a guide
- It describes tool behavior, not user preference

**Keep in memory when:**
- It's about USER's working style or preferences
- It references specific project state (issue numbers, branch names, deadlines)
- It's a relationship detail (who owns what, who to ask)

## When to Run

- After `/maintenance` sessions
- When memory file count exceeds ~20 per project
- Periodically (monthly) as hygiene
- When you notice yourself saving something to memory that feels like a doc entry

## Related

- Skill: `/maintenance` (session analysis, pattern extraction)
- Skill: `/tidy` (cleanup completed temp files)
- Convention: `dev-reference/conventions/claude-md-conventions.md`
