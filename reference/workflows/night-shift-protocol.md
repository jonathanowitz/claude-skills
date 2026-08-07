# Night Shift Protocol

**Purpose:** Autonomous implementation loop that works through a task queue with test-first discipline, review persona gates, and self-improving feedback.

**Skill:** `/night-shift [queue-path | "resume"]`

---

## Overview

The night shift loop follows this cycle for each task:

```
Analyze → Write Tests → [RED gate] → Plan → Review Gate → Implement → [GREEN gate] → Cleanup → Validate → Review Gate → Ship → Capture Learnings → Next Task
```

Key invariants:
- **Red/Green TDD gates are mechanical, not advisory.** RED gate: test runner exits non-zero with behavioral assertion failures. GREEN gate: test runner exits zero with all tests passing. An agent cannot proceed past either gate without the test runner confirming.
- Tests before implementation, always
- No shipping without review persona approval
- Maximum iteration limits prevent infinite loops
- Learnings feed forward to improve subsequent tasks

## Stacked Branches

Night shift uses **stacked branches** so tasks can be merged sequentially without rebasing. Each task branches from the previous task's branch, forming a chain:

```
main
 └─ night-shift/ns-01
     └─ night-shift/ns-02
         └─ night-shift/ns-03
             └─ ...
```

**Merge order:** Merge ns-01 into main first, then ns-02 (fast-forward or clean merge), then ns-03, etc. No rebasing required.

**Rules:**
- Task 1 branches from `main`
- Task N branches from task N-1's branch (the previous completed task)
- Each worktree is created from the tip of the previous task's branch
- If a task is skipped, the next task branches from the last *completed* task's branch
- The state file tracks the current stack tip (branch name) so `resume` can reconstruct the chain

**Why not independent branches:** With 5+ tasks, merging the first PR invalidates the base of all remaining branches. Stacking avoids N-1 rebases and lets USER merge them sequentially as a batch.

## Components

### Task Queue (`tmp/night-shift-queue.md`)
Markdown file with tasks to work through. Each task has: ID, type, spec, relevant files, priority, and persona selection.

Created by:
- `/test-coverage-review` (generates gap list → convert to queue)
- `/bug-squash` (generates priority list → convert to queue)
- Manual creation for feature work

**Before an issue enters the queue, run it through the queue-readiness rubric** (`night-shift-queue-readiness.md`) — the front-door check that a candidate's premise is still true, its decisions are made, and it has a test oracle. The loop's runtime gates catch a *stuck* task; they do not catch a *stale* one (a false premise every persona ratifies). The premise check requires reading the current code at each cited location, not grepping the issue.

### Review Personas (`~/Projects/dev-reference/agents/review-*.md`)
Six independent reviewer agents, each in its own file:
- `review-code-expert.md` — correctness, test quality, logic errors
- `review-domain-expert.md` — business logic, real-world data, edge cases
- `review-architect.md` — structure, patterns, abstraction boundaries
- `review-ux.md` — usability, accessibility, real-world usage context
- `review-performance.md` — speed, resources, scalability
- `review-security.md` — auth, input validation, information disclosure

Selection guide: `~/Projects/dev-reference/agents/REVIEW_PERSONAS.md`

**UX persona is not needed for implementation tasks.** Telemetry shows 0% signal rate on "make tests green" work — UX flagged valid design concerns but none were actionable for implementation correctness. Use UX personas during shaping and design review, not during implementation. Skip for tasks where the spec is already approved and the work is "pass these tests."

(Evidence: 2026-04-03 — Night shift Slice 2 implementation. UX reviewer flagged empty state and AND/OR semantics, both already resolved in the approved brief. Zero actionable findings for the implementation task.)

### Cleanup Pass

Runs between Implement and Validate. A separate focused pass (ideally Haiku-tier) that reads the diff and removes artifacts the implementation step left behind. Negative instructions in the implementation prompt ("don't add console.logs") are unreliable — removal as a dedicated step works better.

The cleanup agent reviews the diff and removes:
- `console.log` / debug statements
- Over-defensive code (guards for impossible states, redundant null checks)
- Unnecessary comments (restating what the code does)
- Dead imports
- TODO/FIXME comments that aren't in the issue tracker
- Tests that don't test real behavior (e.g., testing that a mock returns what you told it to)

The cleanup agent must NOT add anything — only remove. If it can't find anything to remove, that's fine.

(Insight: from the "de-sloppify" pattern — removal is a separate skill from creation, and agents are better at it when it's the only thing they're doing.)

### Review Persona Isolation

For maximum review quality, review personas should run as separate headless `claude -p` invocations that only see the diff — not in-session Agent calls that have witnessed the implementation journey. A reviewer that "saw" the implementation is biased toward understanding it.

When running in-session (simpler, current approach), this is acceptable. When running headless overnight (Level 4 maturity), use separate invocations:

```bash
claude -p "$(cat ~/Projects/dev-reference/agents/review-code-expert.md)

## Diff to Review
$(git diff main...HEAD)" \
  --allowedTools "Read,Glob,Grep" \
  --model sonnet
```

### State, Telemetry & Learnings
- `tmp/night-shift-state.md` — current run progress (task in progress, completed count, **stack tip branch**)
- `tmp/night-shift-telemetry.jsonl` — **append-only structured data** — one JSON row per task with metrics (iterations, persona verdicts, timing, blocker quality). This is the measurement backbone.
- `tmp/night-shift-learnings.md` — qualitative patterns (why things worked or didn't). Complements telemetry with prose explanation.
- `tmp/night-shift-report.md` — end-of-run summary with computed trends from telemetry

## Running the Night Shift

### First Run
```
/night-shift tmp/night-shift-queue.md
```

### Resume After Interruption
```
/night-shift resume
```

### Creating a Queue from Coverage Review
1. Run `/test-coverage-review`
2. Convert gaps to queue format in `tmp/night-shift-queue.md`
3. Run `/night-shift`

## Context Bridge (`tmp/night-shift-notes.md`)

Each step in the loop writes a structured handoff note to `tmp/night-shift-notes.md`. This is the recovery mechanism — if the session crashes or hits compaction, `resume` reconstructs from this file instead of relying on conversation context.

After each task completion, append:

```markdown
## Task <ID> — <status: done|skipped|reduced>

**What was done:** [1-2 sentences]
**Codebase gotchas discovered:** [anything the next task should know]
**Files modified:** [list]
**Tests added/changed:** [list]
**Next task context:** [anything relevant to the next queue item]
```

On `resume`, the coordinator reads `night-shift-notes.md` + `night-shift-state.md` + `night-shift-telemetry.jsonl` to reconstruct full context without needing conversation history.

## Model Routing

Not every step in the loop needs the same model. Route by task complexity:

| Step | Model | Rationale |
|------|-------|-----------|
| Analyze (read code, understand scope) | Sonnet | Fast, good at code comprehension |
| Write tests | Sonnet | Implementation work |
| Plan | Sonnet | Straightforward given analysis |
| Review gate | Sonnet | Persona prompts are self-contained |
| Implement | Sonnet | Default; escalate to Opus if fix iterations > 2 |
| Cleanup pass | Haiku | Mechanical removal, no creativity needed |
| Validate | Haiku | Running commands, checking output |
| Capture learnings | Haiku | Structured extraction from known template |

**Escalation rule:** If a task hits fix iteration 3, escalate the implementation model to Opus for the remaining attempts. Complex failures need stronger reasoning.

## Safety Rails

| Limit | Value | What Happens |
|-------|-------|--------------|
| Review iterations per gate | 3 max | Task skipped, flagged for human review |
| Fix iterations per task | 5 max | Task skipped, flagged for human review |
| **Scope reduction at iteration 3** | Auto | Isolate failing test/assertion, try narrower fix (see below) |
| NEEDS_DISCUSSION verdict | Any persona | Task skipped immediately |
| Pre-existing test failures | Any | Must fix before starting queue |
| **Max duration per task** | 30 min | Task skipped, flagged for human review |
| **Max duration per run** | 4 hours | Run ends, remaining tasks stay in queue |

### Scope Reduction (Iteration 3)

When a task hits fix iteration 3 without passing, don't just keep retrying at the same scope:

1. **Isolate** — identify the specific failing test assertion(s)
2. **Reduce** — create a minimal reproduction: just the failing test + the smallest code surface
3. **Retry with reduced scope** — fix only the isolated failure, not the full task
4. **If iteration 4 fails on reduced scope** — skip the task. The problem likely needs architectural judgment.

This prevents the common failure mode of retrying the same broad approach 5 times. Narrowing scope often reveals the actual root cause.

## Telemetry & Self-Improvement

Two feedback channels work together:

### Structured telemetry (`tmp/night-shift-telemetry.jsonl`)
Append-only JSONL. One row per task. Machine-readable metrics that enable trend analysis:

| Metric | What It Measures | Target Trend |
|--------|-----------------|--------------|
| First-pass approval rate | % of personas that approve without changes | Up (better first drafts) |
| Review iteration average | Rounds needed per gate | Down |
| Fix iteration average | Code attempts to pass tests | Down |
| Persona signal rate | Per persona: useful / selected | Informs selection — drop below 30% |
| Blocker false positive rate | Incorrect blockers / total blockers | Down (persona calibration) |
| Test stability | Tests not modified after initial write | Up (better analysis in Step 2) |
| Skip rate | Skipped / total | Down |
| Duration per task type | Minutes by task type | Down within type |

### Prose learnings (`tmp/night-shift-learnings.md`)
Free text. Explains *why* the numbers look the way they do. Captures codebase gotchas, test patterns that worked, and approaches that failed.

### How they interact
At startup, the coordinator:
1. Reads telemetry → computes dashboard → identifies metrics moving in wrong direction
2. Reads prose learnings → finds explanations for the trends
3. **Acts on the data:**
   - Persona signal rate < 30% for a task type → skip that persona
   - Fix iterations trending up → slow down in analysis step
   - Test stability below 80% → spend more time reading code before writing tests
   - Blocker FP rate high for a persona → note in PR that persona's blockers need human triage

Over time, the loop converges: fewer iterations, better persona selection, faster task completion. The telemetry makes this measurable rather than aspirational.

---

*Created: 2026-03-24*
