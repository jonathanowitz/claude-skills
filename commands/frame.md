---
description: Frame a problem before jumping to solutions
argument-hint: <problem, idea, or observation>
allowed-tools: [Read, Edit, Write, AskUserQuestion]
---

# Frame the Problem

Frame this problem before shaping a solution: $ARGUMENTS

## Philosophy

Most ideas arrive as embedded solutions — "we need feature X" or "add a button that does Y." This skill strips away solution assumptions and explores the underlying problem so that `/shape-project` has a solid foundation to design against.

**The goal is a clear problem statement, NOT a solution.**

## Instructions

### Step 1: Identify what was said vs. what's underneath

Read $ARGUMENTS and separate:
- **Surface request:** What was literally asked for (often contains a solution assumption)
- **Underlying signal:** What problem or frustration is driving the request

State both back to USER in 1-2 sentences each. Ask if the underlying signal is right before continuing.

### Step 2: Explore the problem space (one question at a time)

Work through these areas conversationally. Ask ONE question, wait for the answer, then ask the next — adapting based on what you learn. Skip areas that are already clear from context or previous answers.

**Who and when:**
- Who experiences this problem? How often? How painful is it?

**Current state:**
- What happens today? What workarounds exist? What breaks or frustrates?

**Trigger:**
- What specific moment or event surfaces this problem?

**Success criteria:**
- If this were solved, how would you know? What changes for the user?

**Constraints:**
- What technical, business, or time constraints shape what's possible?

**Cost of inaction:**
- What happens if we don't solve this? Is it getting worse?

You don't need to ask all of these — stop when the problem is clear. Some problems are simple and need 2 questions. Some need all 6. Use judgment.

### Step 3: Synthesize the problem brief

Once you have enough to frame the problem clearly, write a problem brief. Use AskUserQuestion to confirm it captures the problem accurately before saving.

### Step 4: Save the problem brief

1. Read `~/.claude/project-ideas.md`
2. Add the problem brief under "## Active Ideas" (newest first)
3. If a prior entry exists for this idea, replace it

## Problem Brief Format

```markdown
### [Descriptive Name]
**Framed:** YYYY-MM-DD

**Problem:** [2-3 sentences describing the actual problem — who has it, when it surfaces, why it matters. No solution language.]

**Current state:** [What happens today. Workarounds, pain points, gaps.]

**Success criteria:** [What "solved" looks like from the user's perspective. Observable outcomes, not features.]

**Constraints:** [Anything that limits the solution space — technical, business, time, dependencies.]

**Cost of inaction:** [What happens if this stays unsolved. Is it stable, degrading, or blocking?]

**Status:** Framed — ready for `/shape-project`
```

## Guidelines

- **No solution language in the problem brief.** If you catch yourself writing "we should add X" or "a feature that does Y," back up and restate as a problem.
- **One question at a time.** Don't dump a list of questions — explore conversationally.
- **It's okay to be brief.** A well-understood problem might only need 3-4 sentences total. Don't pad.
- **Challenge assumptions.** If the input contains "we need X," ask why. The first answer is often the real problem.
- **USER has deep domain knowledge.** Trust his read on the problem — your job is to draw it out and structure it, not second-guess it.
