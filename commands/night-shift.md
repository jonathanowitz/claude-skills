---
description: Autonomous work loop — picks tasks from a queue, implements with test-first discipline, gates on review personas, and improves over iterations
argument-hint: [task queue path or "resume"]
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash, Agent, AskUserQuestion, TaskCreate, TaskUpdate]
disable-model-invocation: true
---

# Night Shift

Autonomous implementation loop. Work through a task queue with test-first discipline, review persona gates, and self-improving feedback.

## Philosophy

The loop is the product. Each iteration should be better than the last — not because the code improves (that's table stakes), but because the process tightens. Capture what worked, what didn't, and feed it forward.

**Core invariant:** No implementation ships without (1) tests that validate the spec, (2) passing full suite, (3) review persona approval on the diff.

## Telemetry Schema

Every completed task emits a structured JSON row to `tmp/night-shift-telemetry.jsonl` (append-only). This is the measurement backbone — prose learnings explain *why*, telemetry shows *what* and *how much*.

```jsonl
{
  "run_date": "2026-03-24",
  "run_id": "ns-2026-03-24-1",
  "task_id": "NS-01",
  "task_type": "unit-test",
  "priority": "HIGH",
  "outcome": "shipped|skipped|failed",
  "skip_reason": null,
  "personas_selected": ["code", "domain"],
  "personas_approved_first_pass": ["code"],
  "personas_requested_changes": ["domain"],
  "personas_useful": ["code", "domain"],
  "personas_noise": [],
  "review_iters_plan": 1,
  "review_iters_impl": 0,
  "fix_iters": 0,
  "blockers_found": 0,
  "warnings_found": 2,
  "nits_found": 1,
  "blockers_real": 0,
  "blockers_false_positive": 0,
  "tests_written": 4,
  "tests_pass": 4,
  "tests_fail": 0,
  "files_created": 1,
  "files_modified": 0,
  "pr_number": 432,
  "duration_min": 12,
  "test_modified_after_write": false,
  "escalated_to_human": false
}
```

### Key Metrics (computed from telemetry at startup)

| Metric | How to Compute | Target Trend |
|--------|---------------|--------------|
| **First-pass approval rate** | `personas_approved_first_pass / personas_selected` across all tasks | Trending up (writing better first drafts) |
| **Review iteration average** | Mean of `review_iters_plan + review_iters_impl` per task | Trending down |
| **Fix iteration average** | Mean of `fix_iters` per task | Trending down |
| **Persona signal-to-noise** | Per persona: `useful_count / selected_count` across all tasks | Informs selection — drop personas below 30% signal rate for a task type |
| **Blocker false positive rate** | `blockers_false_positive / blockers_found` | Should decrease as personas calibrate |
| **Test stability** | `test_modified_after_write == false` rate | Should be high — tests shouldn't need post-hoc fixes |
| **Skip rate** | `skipped / total` | Should decrease as the loop learns |
| **Time per task by type** | Mean `duration_min` grouped by `task_type` | Trending down within type |

## Step 0: Initialize

### Locate task queue
- If `$ARGUMENTS` is a file path, use it as the task queue
- If `$ARGUMENTS` is "resume", look for `tmp/night-shift-state.md` and resume from where the last run left off
- If empty, look for `tmp/night-shift-queue.md` in the current project
- If no queue found, ask USER what to work on

### Read and analyze telemetry
If `tmp/night-shift-telemetry.jsonl` exists, read it and compute the key metrics from the Telemetry Schema section above. Report a brief dashboard:

```
Night Shift Telemetry — N prior tasks across M runs
  First-pass approval rate:  72% (target: trending up)
  Avg review iterations:     1.4 (target: trending down)
  Avg fix iterations:        0.8 (target: trending down)
  Persona signal rates:      code: 91%, domain: 64%, ux: 45%, ...
  Test stability:            88% written correctly first time
  Skip rate:                 10%
```

**Act on the data:**
- If a persona's signal rate is below 30% for a specific task type, skip that persona for that type (note the override in the state file)
- If fix iterations are trending up, read the learnings for the last 3 tasks to understand why
- If test stability is below 80%, slow down in Step 3 — spend more time analyzing before writing

### Read prose learnings
Read `tmp/night-shift-learnings.md` if it exists. These complement the telemetry with qualitative patterns:
- Common failure patterns to watch for
- Test approaches that worked well
- Codebase-specific gotchas discovered in prior runs

### Read review personas
Read `~/Projects/dev-reference/agents/REVIEW_PERSONAS.md` for persona definitions and selection rules.

### Clean working tree
```bash
git status
```
If there are uncommitted changes:
- If changes look like in-progress work → `git stash push -m "night-shift-stash-$(date +%Y%m%d-%H%M)"`
- If changes look like completed work that was forgotten → ask USER before proceeding
- Report what was done

### Run existing test suite
```bash
npm test
```
If any tests fail, fix them BEFORE starting the queue. These are pre-existing regressions and must not be conflated with new work. If fixes are non-trivial, add them as a task to the front of the queue instead of fixing inline.

### Write state file
Create `tmp/night-shift-state.md`:
```markdown
# Night Shift State
**Started:** YYYY-MM-DD HH:MM
**Queue:** [path to queue file]
**Status:** running
**Current task:** none
**Completed:** 0
**Skipped:** 0
**Stack tip:** main

## Task Log
(entries added as tasks complete)
```

### Branch Stacking

Night shift uses **stacked branches** so tasks can be merged sequentially without rebasing:

```
main
 └─ night-shift/ns-01
     └─ night-shift/ns-02
         └─ night-shift/ns-03
```

- Task 1 branches from `main`
- Task N branches from the **last completed task's branch** (the "stack tip")
- If a task is skipped, the stack tip stays where it was
- The state file tracks the current stack tip so `resume` can reconstruct the chain
- **Merge order:** ns-01 into main first, then ns-02 (fast-forward), then ns-03, etc. No rebasing.
- **PR base:** Each PR targets the previous task's branch (not `main`), except the first which targets `main`. This keeps PR diffs scoped to just that task's changes.

## Step 1: Pick Next Task

Read the task queue. Pick the first uncompleted task. Mark it `[in-progress]` in the queue file.

Update state file with current task.

### Task queue format
Each task should have:
- **ID** — short identifier
- **Type** — `unit-test`, `e2e-test`, `bug-fix`, `feature`, `refactor`
- **Spec** — what to build (inline description, issue number, or path to spec file)
- **Files** — relevant source files to read
- **Priority** — HIGH, MED, LOW
- **Review personas** — which personas to engage (or "auto" to select based on type)

## Step 2: Analyze

Read the spec thoroughly. Then read the relevant source files. Understand:
- What behavior exists today
- What behavior should exist after the task
- What the test should verify
- Where the change belongs in the codebase

If the task references a commit (e.g., for regression tests), read the commit diff:
```bash
git show <sha> --stat
git show <sha> -- <relevant-files>
```

**For regression tests specifically:** The code is already fixed. The test must verify the fix works. Validate this by confirming the test would have FAILED on the pre-fix code. Read the diff to understand the before/after.

## Step 3: Write Tests

**This is the critical gate. Tests before implementation, always.**

### For unit tests:
1. Create test file following existing patterns (check `tests/` for naming conventions)
2. Write tests that exercise the specific behavior from the spec
3. Each test must have a meaningful assertion — no `toBeDefined()` alone, no `expect(true)`
4. Include edge cases: empty input, null, boundary values, error conditions

### For E2E tests:
1. Follow `e2e-test-conventions.md` strictly
2. Verify ALL selectors against the actual HTML files (grep, don't guess)
3. Handle overlay suppression, `data-app-ready`, and auth fixtures correctly
4. Include the three-scenario check where applicable

### Run the tests
```bash
npm test -- --run [test-file]     # unit tests
npx playwright test [spec-file]   # e2e tests
```

**Expected results for regression tests:** Tests should PASS (the fix already exists).
**Expected results for new feature tests:** Tests should FAIL (the feature doesn't exist yet).

If results don't match expectations, investigate before proceeding. Don't guess — read the code.

## Step 4: Plan Implementation

For tasks that require code changes (not just test writing):

1. Write a brief implementation plan (what files to change, what to add/modify)
2. Keep it proportionate — don't over-plan a one-line fix

**Skip this step for test-only tasks** — the tests ARE the deliverable.

## Step 5: Review Gate (Plan)

**Model for all review-persona Agent spawns (this step AND Step 8):** pass `model: "sonnet"`. Night Shift runs autonomously across many tasks — the cost multiplier is huge, and Sonnet is sufficient for plan and implementation review. Do not inherit the parent session model. Do not override to Opus without USER's explicit request for a specific task.

Select review personas based on the task type (see `~/Projects/dev-reference/agents/REVIEW_PERSONAS.md` selection table).

For each selected persona:
1. Read its individual file (e.g., `~/Projects/dev-reference/agents/review-code-expert.md`)
2. Build an agent prompt using ONLY that persona's file — do not include other personas' instructions

Launch all selected personas in parallel using the Agent tool. **All must be launched in a single message** — no sequential launches.

Each agent prompt should be structured as:
```
[Full content of the persona's .md file]

---

## Task for Review

**Task:** [task spec]
**Type:** [task type]
**Files to change:** [list]

### Test file(s)
[full content of test files]

### Implementation plan
[plan from Step 4, or "N/A — test-only task"]

### Relevant source code
[key source files — read and include the actual content]

Return your review in the Output Format specified above.
```

**Critical:** Each agent gets ONLY its own persona file. No cross-persona context. This prevents anchoring and ensures independent review.

### Process review results
- If all personas APPROVE → proceed to Step 6
- If any persona returns REQUEST_CHANGES → address the feedback, update tests/plan, re-submit ONLY to the requesting persona(s)
- If any persona returns NEEDS_DISCUSSION → add to "needs human" list, skip this task, move to next
- **Maximum 3 review iterations** — after 3 rounds without convergence, skip and flag for human review

## Step 6: Implement

### Create worktree (stacked branch)

Read the **stack tip** from `tmp/night-shift-state.md`. Create the new branch from that tip:

```bash
# First task: stack tip is "main"
git worktree add ../<repo>-ns-<task-id> -b night-shift/<task-id> <stack-tip>

# Example for task 3 (stack tip is night-shift/ns-02):
# git worktree add ../example-app-ns-03 -b night-shift/ns-03 night-shift/ns-02
```

Install dependencies in the worktree (`npm install`).

### For test-only tasks:
- Still use a stacked worktree — the branch must be part of the stack so it merges cleanly
- The stack tip advances even for test-only tasks

### For code changes:
- Work in the worktree
- Make minimal, focused changes
- Follow existing patterns (check codebase-map.md)

### Run targeted tests
```bash
npm test -- --run [test-file]
```

If tests fail, iterate. Read the error, understand it, fix it. Don't brute-force.

**Maximum 5 fix iterations** — if you can't make tests pass in 5 tries, something is wrong with the approach. Skip the task and flag for human review.

## Step 7: Validate

### Run full test suite
```bash
npm test
```

All tests must pass. If the new code broke existing tests, fix the regression before proceeding.

### Static analysis (if applicable)
Run any available linting, type checking, or other static analysis tools.

### Self-review
Re-read every changed file. Verify:
- No debug artifacts (console.log, TODO comments, hardcoded test values)
- No unintended changes (git diff should show only task-relevant changes)
- Assertions are meaningful, not vacuous
- Edge cases are covered

## Step 8: Review Gate (Implementation)

Launch the same review personas from Step 5, but now on the implementation diff.

Get the diff (against the stack base, not main — shows only this task's changes):
```bash
git diff <stack-tip-before-this-task>...HEAD
```

For each persona, build the agent prompt the same way as Step 5:
1. Read the persona's individual `.md` file
2. Include ONLY that persona's instructions (no cross-persona context)
3. Append the task spec, the full diff, and the full content of changed files (not just the diff — reviewers need context to judge correctness)

Launch all in parallel. Same iteration rules as Step 5: max 3 rounds, skip if NEEDS_DISCUSSION.

## Step 9: Ship

### Commit
```bash
git add [specific files]
git commit -m "$(cat <<'EOF'
[Descriptive commit message]

[What changed and why — enough context for human review]

Night Shift task: [task-id]
[Issue reference if applicable]

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### Create PR (stacked)
Write the PR body to a temp file first (avoids `##` in heredocs triggering permission checks), then pass via `--body-file`.

**PR base branch:** Each PR targets the previous task's branch, not `main`. This scopes the PR diff to just this task's changes. The first task's PR targets `main`.

```bash
git push -u origin night-shift/<task-id>
# Write body to temp file
cat > /tmp/ns-pr-body.md << 'PREOF'
...PR body content...

**Stack position:** N of M — merge sequentially after previous PR.
PREOF

# First task targets main; subsequent tasks target the previous branch
gh pr create --title "[task title]" --base <previous-branch-or-main> --body-file /tmp/ns-pr-body.md
```

### Update queue and stack tip
Mark the task as `[done]` in the queue file. Record the PR number.

**Update the stack tip** in `tmp/night-shift-state.md` to this task's branch name. The next task will branch from here.

### Clean up worktree
```bash
git worktree remove ../<repo>-ns-<task-id>
```

## Step 10: Capture Telemetry + Learnings

### Structured telemetry (machine-readable)
Append one JSON row to `tmp/night-shift-telemetry.jsonl` following the schema in the Telemetry Schema section. Every field must be populated — no nulls except `skip_reason` on shipped tasks and `pr_number` on skipped tasks.

**Measuring blocker quality:** For each BLOCKER found by a review persona, classify it:
- `blockers_real` — the blocker identified a genuine issue that needed fixing
- `blockers_false_positive` — the blocker was wrong or irrelevant (you proceeded without the suggested fix and nothing broke)

This is how persona calibration happens over time. A persona with high false positive rate is adding noise, not signal.

**Measuring persona signal:** A persona is "useful" if it produced at least one finding that changed what you shipped (you made a code change because of their feedback). A persona is "noise" if all their findings were either false positives, already known, or too generic to act on.

### Prose learnings (human-readable)
Append to `tmp/night-shift-learnings.md`:

```markdown
## Task: [task-id] ([date])
- **What worked:** [approach that succeeded — be specific enough to replicate]
- **What didn't:** [approaches that failed — include why, not just what]
- **Pattern:** [reusable insight for future tasks, or "none"]
- **Unrelated TODOs noticed:** [anything worth flagging that wasn't in scope]
```

Keep prose learnings focused on *why* — the telemetry captures the *what* and *how much*. Don't duplicate numbers here.

### Update state file
Mark task complete, increment counters.

## Step 11: Loop

Go back to Step 1. Pick the next task.

If the queue is empty, proceed to Step 12.

## Step 12: Report

Read all telemetry rows from this run (matching `run_id`) and compute metrics. Then write `tmp/night-shift-report.md`:

```markdown
# Night Shift Report — YYYY-MM-DD

**Run ID:** [run_id]
**Duration:** [start time] → [end time]
**Tasks completed:** N / N total
**Tasks skipped:** N (reasons below)
**PRs created:** [list with numbers]

## Completed Tasks
| Task | Type | PR | Plan Reviews | Impl Reviews | Fix Iters | Duration |
|------|------|----|-------------|-------------|-----------|----------|

## Skipped Tasks (Need Human Review)
| Task | Reason | What to Look At |
|------|--------|-----------------|

## Unrelated TODOs
- [anything noticed during the run that's worth flagging]

## This Run's Telemetry
| Metric | This Run | All-Time | Trend |
|--------|----------|----------|-------|
| First-pass approval rate | X% | Y% | up/down/flat |
| Avg review iterations | X | Y | up/down/flat |
| Avg fix iterations | X | Y | up/down/flat |
| Test stability (no post-write mods) | X% | Y% | up/down/flat |
| Skip rate | X% | Y% | up/down/flat |
| Blocker false positive rate | X% | Y% | up/down/flat |

## Persona Performance (This Run)
| Persona | Times Selected | Times Useful | Signal Rate | Avg Blockers | Avg FP |
|---------|---------------|-------------|-------------|-------------|--------|

## Cross-Run Trends
[If 3+ prior runs exist, compute per-persona signal rate trend and per-task-type efficiency trend. Flag:]
- Personas whose signal rate dropped below 30% for a task type → recommend removal from selection
- Task types where fix iterations are increasing → investigate in prose learnings
- Any metric that moved in the wrong direction for 2+ consecutive runs → flag for process review

## Process Recommendations
[Based on telemetry analysis, concrete suggestions for the next run:]
- "Drop [persona] from [task-type] reviews — signal rate is N% over M tasks"
- "Spend more time in Step 2 (Analyze) for [task-type] — fix iterations averaging N"
- "Review gate is clean — consider reducing to 1 persona for [task-type]"
```

Present the report to USER. Keep it concise — details live in commit messages, PR descriptions, and the telemetry file.

### Telemetry integrity check
Before finishing, verify `tmp/night-shift-telemetry.jsonl` has exactly one row per completed or skipped task from this run. If any are missing, emit them now with `outcome: "telemetry_gap"` so the gap is visible in future analysis rather than silently missing.

## Guidelines

- **Never modify existing tests to make them pass** — fix the code, not the tests. Exception: if an existing test has a genuine bug (wrong selector, vacuous assertion), fixing the test IS the task.
- **Never skip the review gate** — even for "obvious" changes. The personas catch things you missed.
- **Don't over-iterate** — if something isn't converging, skip it. Human judgment is the escalation path, not more iterations.
- **Capture everything** — the learnings file is how the loop improves. A run without learnings is a wasted run.
- **Proportionate ceremony** — a one-line assertion fix doesn't need 6 review personas. Use the selection table.
- **Stay in scope** — if you notice a bug or improvement opportunity outside the current task, add it to the TODOs list in the report. Don't fix it now.
