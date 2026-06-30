---
description: RED-GREEN TDD for one vertical slice — write tests, confirm RED, implement, confirm GREEN
argument-hint: <slice name from implement plan>
allowed-tools: [Read, Edit, Write, Grep, Glob, Bash]
---

# Implement Slice

Execute one vertical slice using strict RED→GREEN TDD. This is the repeatable unit of `/implement`.

**Input:** A slice name ($ARGUMENTS) matching a section in the implementation plan file.

## Step 1: Read the Slice Spec

Find the slice in `tmp/implement-plan-*.md`. Extract:
- **RED section:** test file path, what to assert, expected failure pattern
- **GREEN section:** implementation file path, what to build
- **Context needed:** any function signatures or API contracts from prior phases

## Step 2: Read Context from Prior Phases

If this slice depends on prior phases (e.g., "client module tests need the handler's API contract"):
- Read the actual implementation files from prior phases
- Extract the exact function signatures, response shapes, and export names
- Do NOT use the brief's spec — use what was actually built

## Step 3: Write Tests (RED)

Write the test file(s) specified in the slice's RED section.

**Test writing rules:**
- Follow existing test patterns in the same directory (import style, mock patterns, fixture conventions)
- Every test must have a meaningful assertion — no `toBeDefined()` alone
- Tests must import from the stub file created in Phase 0
- Tests should fail with **behavioral** assertions (expected X, got Y), NOT structural errors (module not found, undefined is not a function)
- Include edge cases: empty input, null, boundary values, error conditions

**Run the tests.** Confirm:
- All new tests FAIL **with behavioral assertion errors** — not module-resolution errors
- **HARD RULE:** `Cannot find module`, `ENOENT`, `ReferenceError`, or `X is not a function` from a missing export are NOT valid RED. The test body never executed; the assertion never ran. Add stub modules at the canonical import paths (minimal exports, no behavior — API handlers return 501; pure functions return `null`) and re-run. Full pattern: `~/Projects/dev-reference/patterns/red-state-must-be-behavioral.md`.
- Any tests that PASS are suspect — verify they're testing legitimate default behavior from the stub (e.g., `isReported()` returning `false` before any reports is correct default behavior, not a vacuous pass). If you can't justify a stub-pass, fix or delete the test.

Report: "RED checkpoint: N tests failing on assertions, 0 failing on imports. M tests passing (justified per test)."

## Step 3.5: Test Review (Stage 4 gate) — hard gate, mechanically enforced

Run `/review-tests` on the newly-written test files. This runs 3 parallel Claude personas (QA, code expert, domain expert) + a two-call Gemini depth+breadth cross-model review. It catches vacuous passes, mock-fidelity gaps, assertion-behavior mismatches, and coverage holes *before* they get baked into the implementation.

Fix every BLOCKER it surfaces before moving to Step 4. WARNINGS should be addressed or explicitly justified in the slice's deviation log.

Skip only if the slice is a trivial one-line test addition (e.g., a single regression test for a reported bug).

**Mechanical backstop.** A PostToolUse hook (`test-review-gate-post.sh`) tracks test-file writes in this worktree. When cumulative test count crosses 5, the PreToolUse hook (`test-review-gate-pre.sh`) denies impl-file Write/Edit and test-suite Bash runs (`vitest`, `playwright`, `docker compose run test`) until `/review-tests` resolves all blockers + warnings and removes the lock at `/tmp/review-tests-pending-<cwd_hash>.lock`. If you skip this step, Step 4's first Write will fail. Don't try to bypass — run the review. Evidence: 2026-04-21 (#680 Slice 0), this gate was skipped via advisory memory alone, so it's now mechanical.

## Step 4: Implement (GREEN)

Write/modify the implementation file(s) specified in the slice's GREEN section.

**Implementation rules:**
- Follow existing codebase patterns exactly (handler pattern, IIFE pattern, error response shape)
- Match the JSDoc contract from the stub file
- No feature creep — implement exactly what the tests assert, nothing more

**Run the targeted tests.** Confirm all pass.

If tests fail:
- Read the error message carefully
- Fix the implementation (not the tests)
- **After 2 failed fix attempts**, escalate: run `/second-opinion` with the test file + implementation file + error output. A fresh model catches type mismatches and contract violations that you've been staring past. Apply Gemini's findings, then continue.
- Maximum 5 fix iterations total (including post-escalation attempts) — if still not converging, stop and report.

## Step 5: Full Suite Check

Run the full test suite. Confirm:
- **Unit:** `npm test` — new tests pass (GREEN), no regressions
- **E2E (if specs exist for this slice):** `docker compose run --rm test e2e/<feature>.spec.js` — Docker starts its own vercel dev, no host dev server needed
- No regressions (baseline count maintained or exceeded)

Report: "Slice '<name>' complete. +N new tests. Suite: X total passing."

## Failure Modes to Avoid

- Writing tests that pass against the stub (vacuous tests)
- Modifying tests to make implementation pass (tests are the spec)
- Implementing more than the tests require
- Skipping the RED checkpoint ("tests will obviously fail")
- Using the brief instead of reading actual prior-phase code
