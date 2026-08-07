---
description: Execute an approved implementation plan end-to-end, producing a PR
argument-hint: [optional path to plan file]
allowed-tools: [Read, Edit, Write, Grep, Glob, Bash, Agent, TaskCreate, TaskUpdate, TaskGet, TaskList]
disable-model-invocation: true
---

# Implement

Execute an approved implementation plan autonomously, producing a committed branch and PR.

**This is a walk-away skill.** After launching, USER should not need to intervene until the PR is created.

**Stack scope — learn it from the repo under review, don't assume it.** This pipeline was written against example-app's stack (Supabase migrations, `vercel dev`, Docker + Playwright E2E, and its vanilla-JS DOM conventions). The specific commands, selectors, API routes, and ready-signals shown throughout the `/implement*` family are **worked examples of that stack**, not universal facts. When running in a repo whose stack differs (including example-app's own Vite/React rebuild), read that repo's `CLAUDE.md`, its test conventions, and its existing tests, and carry the same rigor to *its* toolchain — not these literal names.

## Prerequisites

1. **Find the plan file.** Check in order:
   - $ARGUMENTS if provided
   - `tmp/implement-plan-*.md` (most recent by date in filename)
   - If no plan found, stop: "No implementation plan found. Run `/implement-plan <brief>` first."

2. **Verify the plan is approved.** The plan file should exist and USER should have approved it in a prior conversation turn or session. If unsure, ask.

3. **Verify pre-work is done.** Before `/implement` runs:
   - **Plan file** must exist with test-ready behavior map entries (created via `/implement-plan`, approved by USER)
   - **Migration applied** — USER has run `supabase db push` or equivalent. The migration SQL file will be created by `/implement-stubs`, but USER applies it to the database manually before or during the autonomous run.
   
   If no plan file exists, stop: "No implementation plan found. Run `/implement-plan <brief>` first."

4. **Verify the worktree.** Check if we're in a worktree (not the main repo). If not, create one per the git workflow conventions. Install dependencies.

5. **Read the full plan file** into context. This is the execution spec.

6. **Run the baseline test suite.** Record the count. Every phase must maintain this count and progressively add new passing tests.
   - **Unit tests:** `npm test` (runs on host, fast)
   - **E2E tests:** `docker compose run --rm test <spec>` (starts its own vercel dev in Docker, runs Playwright, tears down — no host dev server needed). Run one spec at a time during development; full suite for final verification.

7. **Create tasks** for each phase (Stubs, E2E, each Slice, Integration, Ship). This gives USER visibility into progress.

## Execution Loop

For each phase in the plan, in order:

### Phase 0: Foundation
Run `/implement-stubs` — creates migration file, stub handlers (501), stub IIFEs (empty), route wiring, and any bundled bug fixes. This is mechanical — the plan specifies exactly what to create.

### E2E Specs (RED)
Run `/implement-e2e` — generates E2E test specs from the plan's test-ready behavior map entries. This is a mechanical translation: each behavior map entry with trigger, preconditions, API call, and expected outcomes becomes one or more test cases. The specs will fail (RED) because the stubs from Phase 0 return 501 / empty values, so assertions fail with **behavioral** errors (`expected 200, got 501`) — not module-resolution errors. If you see `Cannot find module` or `ENOENT`, Phase 0 stubs are missing — go back and fix them before declaring RED. See `~/Projects/dev-reference/patterns/red-state-must-be-behavioral.md`.

### Test Review (Stage 4 gate) — mechanically enforced
Run `/review-tests` immediately after `/implement-e2e`. This is the Stage 4 quality gate — the test files are the spec, and once they're locked, implementation chases them. A flawed spec produces a flawed implementation no matter how clean the code is. `/review-tests` runs 3 parallel Claude personas + a two-call Gemini depth+breadth cross-model review. Fix every BLOCKER it surfaces before proceeding to slices. This is non-optional for `/implement` runs.

**Mechanical backstop.** The PostToolUse hook `test-review-gate-post.sh` tracks test-file writes in the worktree; once cumulative tests cross 5, the PreToolUse hook `test-review-gate-pre.sh` denies implementation writes and test-suite Bash runs until `/review-tests` resolves all blockers + warnings and removes the lock at `/tmp/review-tests-pending-<cwd_hash>.lock`. The same gate fires inside `/implement-slice` Step 3.5 (per-slice unit tests). No bypass short of explicit `rm` of the lock (audit trail preserved). See `~/.claude/rules/hooks-and-agents.md` § Autonomous Agents.

**E2E specs are IMMUTABLE after this point.** All subsequent phases may only modify application code to satisfy the tests.

**Human review checkpoint after `/review-tests` PASS — STOP, do not auto-proceed to GREEN.** A `/review-tests` PASS clears the *mechanical* gate; it is NOT authorization to start implementation. The mechanical gate and USER's human review are two distinct approvals — clearing the first does not grant the second. After PASS, present the reviewed test files (or a tight summary) and **wait for USER's explicit "go to green"** before dispatching any GREEN / `/implement-slice` work. (Evidence: 2026-06-26 and 2026-06-29 — dispatched the GREEN implementation agent straight off a `/review-tests` PASS without pausing; 2026-06-29 USER: "you did it again, I did not say go to green yet.")

### Each Vertical Slice
Run `/implement-slice` with the slice spec from the plan. Each slice writes unit tests (RED) then implementation (GREEN). The E2E specs remain RED during this phase — they turn GREEN after wiring.

### Integration Phase + GREEN Verification Loop
Run `/implement-wire` with the integration spec from the plan.

After wiring, run the full test suite:
- **Unit:** `npm test`
- **E2E:** `docker compose run --rm test e2e/<feature>.spec.js` for each feature spec. Docker handles vercel dev startup/teardown automatically.

Check which E2E specs are now GREEN.

**E2E specs are IMMUTABLE during the verification loop.** You may only modify application code to satisfy the tests. The E2E specs are the spec — they define what was approved. If a test seems wrong, that's a planning error, not an implementation issue. Stop and report rather than modifying the test.

**If E2E specs are still RED after wiring:**
1. Read the failing E2E test's error message — what element is missing, what assertion failed?
2. Run `/implement-fix` with the failing test output + relevant source file paths. This is a dedicated debugging skill — it takes failing tests and patches application code until they pass.
3. Re-run E2E specs after each fix: `docker compose run --rm test e2e/<feature>.spec.js`
4. **After the first failed fix attempt**, escalate: run `/second-opinion` with the failing E2E test + the relevant source files + error output. Wiring bugs across multiple files are where a fresh model adds the most value.
5. **Maximum 3 loops through this cycle.** If E2E specs still fail after 3 loops (including post-escalation attempts), stop and report: which specs fail, what the errors are, what Claude tried, and what Gemini said. USER decides next steps.

This loop is the key difference from a linear pipeline — implementation is done when the E2E specs (written as spec) are GREEN, not when each phase reports "complete."

### Ship Phase
Run `/implement-ship` with the brief path and issue number from the plan. Only enter this phase when:
- All unit tests are GREEN
- All E2E specs are GREEN (or explicitly marked as requiring live-server verification)
- No regressions against baseline

## Context Carrying

**This is the critical orchestration responsibility.**

After each phase completes:
1. Note which files were created or modified (file paths only — do NOT read full contents into orchestrator context)
2. Pass file paths to the next phase's skill — let the skill read what it needs directly
3. Only read specific lines when you need to make a routing decision (e.g., checking a function signature to decide which slice to re-enter)

Do NOT relay on the brief's spec for what prior phases built. Let downstream skills read the actual code. The implementation may have deviated slightly from the brief (e.g., an extra parameter, a renamed function) and downstream phases must use reality, not the plan.

**Why paths not payloads:** Reading every new file into the orchestrator context balloons the window exponentially (orchestrator reads it, then passes it to the skill, which reads it again). This causes context degradation in later phases. The orchestrator is a router, not a relay.

## Subagent Dispatch Protocol (mandatory)

Every `Agent` tool call made while running `/implement` — planning, parallel Phase 2 tracks, Phase 3 integration, wiring check, PR review, any helper — MUST include **EXPLICIT output-persistence instructions** in the prompt. Do not rely on the agent to invent the right output format.

**Every location/convention claim in a dispatch prompt must carry a grep-verified citation.** A prompt that tells a subagent to "add X at path Y", "install the plugin under workspace Z", "follow the pattern in file F", or "the RPC is called N" asserts a fact the subagent cannot see the basis for — and it will obey a wrong instruction faithfully. Before writing any "do X at location Y" into a dispatch prompt, grep to confirm Y, and include the citation (`per <file>:<line>`) in the prompt so the subagent can self-check rather than comply blindly. This is Critical Rule #3 (verify external claims) applied to the prompts you *write*, not just to claims you act on. (Evidence: 2026-07-06 — an FS-5 dispatch prompt specified a Capacitor plugin install at the `app/` workspace when the repo convention is repo-root; the subagent flagged the conflict but obeyed the explicit wrong location anyway.)

**Dispatch prompts must also carry the PRODUCT facts, not just the technical spec** — who the user actually is, which scenarios are live, and which cases the data model *can* represent but never *does* (e.g. a coach works at one gym → no cross-gym name collisions; see memory `project_coaches_single_gym_no_name_collision`). A subagent reasons *inside* whatever premise its prompt hands it: give it only the schema and it will faithfully harden a branch, a validation, or six tests for a user who doesn't exist — and a cross-model reviewer handed the same premise reinforces the false case instead of challenging it. This is the MVS ladder's **rung 0 ("is this scenario real?")** applied at dispatch time: the agent can't run rung 0 itself because it can't see the product, so you have to pre-answer it in the prompt. Before locking any conditional/schema/test into a dispatch, state the live scenarios explicitly. (Evidence: 2026-07-16, three times in five days — a parent-gym-qualifier span rule [6 tests + fixture + schema expansion] built for a multi-gym coach who doesn't exist; both reviewers reinforced the false premise. See `~/Projects/dev-reference/conventions/minimum-viable-solution-ladder.md` rung 0.)

Paste this block into every dispatch prompt (customize `<phase-name>` and required-sections):

```
## EXPLICIT OUTPUT REQUIREMENT (must fulfill before returning)

Write your detailed report to `~/.claude/subagent-reports/<phase-name>-<YYYY-MM-DD-HHMMSS>.md` before returning. Create the parent directory if it doesn't exist (`mkdir -p ~/.claude/subagent-reports`). Use UTC timestamp from `date -u +%Y-%m-%d-%H%M%S`.

**Why outside the worktree:** subagent reports are session-state (orchestrator's view of what subagents did), NOT branch-state. They must survive worktree removal so `/session-capture` can merge their telemetry. Writing inside `<worktree>/tmp/` was the prior convention; reports were destroyed when the worktree was cleaned up post-merge before `/session-capture` ran. This new path is structurally safe by construction.

The file must include:
1. Timestamp (absolute date + time)
2. Agent ID + model
3. Verbatim findings — what you touched, what you decided, deviations from the plan, test output
4. <any phase-specific sections>
5. **Telemetry section** (mandatory — `/session-capture` globs `~/.claude/subagent-reports/*.md` filtered by mtime within the session window and merges these sections into the parent session summary; without this, the iteration/redirect/validation-skip events that happened inside your session are invisible to maintenance trend telemetry):

   ```
   ## Telemetry

   ### Learning events
   Use the orchestrator-side vocabulary so events merge cleanly: `redirected` | `assumption` | `validation-skip` | `green-field-error` | `scope-creep` | `protocol-followed` | `efficiency-win`. One block per event:
   - **Type:** <tag>
   - **What happened:** <specific, factual>
   - **Root cause:** <the actual mechanism, not "I made a mistake">
   - **Protocol gap:** <which reference doc should have prevented this, or "none">

   If the run was clean, write: "No learning events. Protocols followed."

   ### Tool telemetry (honest counts)
   - Dead-end tool calls: <N> — failed Bash commands, wrong file paths, empty grep/glob, retries with different args
   - Retries from guessing vs reading: <N> — times you guessed an identifier (selector, route, column, path) and were wrong
   - Fix iterations on the same problem: <N attempts on <component>> — anything >1 is notable
   - Validation steps skipped: <list with reason; "none" is acceptable> — e.g. "Playwright not run — Docker daemon unavailable in agent env"
   - Unnecessary operations: <N> — re-reads of files already in context, searches for things you already had

   ### Inputs touched
   - Files modified: <paths only, no diffs>
   - Issues: <#NN refs>
   - Redirections received from the orchestrator prompt: <list — places where the prompt was ambiguous, contradicted the brief, or where you escalated a scope question; "none" is acceptable>
   ```

Your final chat message must state "Report written to ~/.claude/subagent-reports/<phase-name>-<timestamp>.md" as the first line, then summarize in under 150 words. The full detail lives in the file — the chat summary is only a pointer.

Do NOT return without writing the report. The Telemetry section is non-negotiable: a report without it is a failed dispatch, even if the operational work succeeded.
```

**Rationale:** subagent work is otherwise invisible to USER. Reports live only in the orchestrator's conversation context and vanish on `/clear`. The wiring check, the parallel GREEN tracks, the PR review — every one of these generated detail that should have been inspectable on disk. When this protocol was NOT enforced (2026-04-22 Slice 3 session), USER explicitly flagged it and asked for the protocol change. Do not regress.

**Parallel Phase 2 dispatch checklist:** when spawning 3+ parallel Agent calls for independent tracks:
- Each gets its own report filename (`~/.claude/subagent-reports/phase-2-track-a-<timestamp>.md` etc.)
- Each gets a strict file-scope constraint (which files it owns)
- Each gets model=sonnet (see `~/.claude/rules/hooks-and-agents.md` § Model Policy)
- Orchestrator does NOT relay report contents between tracks — downstream phases read the code directly

**If an agent returns without writing its report**, treat that as a failed dispatch. Do not trust the chat summary — either re-dispatch with a reminder, or do the work yourself.

## Error Handling

- If a phase's test suite shows regressions, fix them before proceeding
- If a phase fails after 3 attempts, stop and report what went wrong — do not skip
- If the E2E GREEN verification loop hits 3 iterations, stop and report (see Integration Phase above)
- If an unexpected file needs modification (not in the plan), note it but proceed if the change is clearly necessary
- Log any deviations from the plan in the commit message

## Completion

After `/implement-ship` succeeds, report:
- PR URL
- Total tests (baseline → final)
- Files changed count
- Any deviations from the plan
- What USER should manually test
