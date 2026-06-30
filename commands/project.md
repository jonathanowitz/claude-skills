---
description: Capture a new project idea into the unshaped ideas queue
argument-hint: <project idea description>
allowed-tools: [Read, Edit]
---

# Capture Project Idea

Capture the following project idea into the unshaped ideas queue: $ARGUMENTS

## Instructions

1. Read `~/.claude/project-ideas.md` to see the current structure
2. Add a new entry under the "## Active Ideas" section with:
   - **Captured:** Today's date (YYYY-MM-DD format)
   - **Concept:** The idea from $ARGUMENTS (1-2 sentences)
   - **Shaping Questions:** Generate 3-5 relevant shaping questions based on the idea (use table format)
   - **Next step:** Suggest a clear action to shape this idea (usually interviewing USER or researching existing solutions)
3. Use the Edit tool to add the new entry at the top of the Active Ideas section (newest first)
4. Confirm to USER that the idea has been captured with a brief summary

## Entry Format Template

```markdown
### [Descriptive Project Name]
**Captured:** YYYY-MM-DD

**Concept:** [Brief 1-2 sentence description of the idea]

**Shaping Questions:**

| Question | Your Answer |
|----------|-------------|
| [Question about the problem space or user need] | |
| [Question about potential users/audience] | |
| [Question about core features or functionality] | |
| [Question about technical approach or complexity] | |
| [Question about similar solutions or differentiation] | |

**Status:** Needs shaping (fill in answers above)
```

## Guidelines

- Keep the concept brief and clear
- Questions should help shape the idea during future exploration, not answer it now
- Generate a descriptive project name based on the concept
- Maintain chronological order (newest ideas at top)
- Use table format for questions with empty "Your Answer" column for USER to fill in
- Set status to "Needs shaping (fill in answers above)"
- Be concise in confirmation - just state what was captured
