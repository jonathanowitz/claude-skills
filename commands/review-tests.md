---
description: Review test files with 3 parallel expert agents + Gemini cross-model review (Stage 4 gate)
---

# Review Tests — Stage 4 Quality Gate

Review test files written before implementation. Three parallel Claude agents (QA, Code Expert, Domain Expert) review independently, then findings feed into a Gemini cross-model review.

**Trigger:** After writing test files from a brief's Verification section, before sharing with USER.

## Inputs

Detect automatically:
1. **Test files** — Find recently modified test files: `git diff --name-only HEAD` or unstaged `git diff --name-only`. Filter to `tests/**/*.test.js` and `e2e/*.spec.js`.
2. **Stub module** — If a stub exists (referenced by the test's import), include it.
3. **Brief** — Look for the shaped brief in `example-context/briefs/` that matches the feature. Use the Verification section and Behavior Map Entries.
4. **Behavior map** — Read `example-context/architecture/app-behavior-map.md` for canonical behaviors.

If $ARGUMENTS is provided, treat it as a path or glob to specific test files to review.

## Stage 1: Three Parallel Review Agents

**Model:** Every Agent call in this skill must pass `model: "sonnet"`. Do not inherit from the parent session. Test review is a breadth-over-depth job — three Sonnet perspectives plus the Gemini depth+breadth cross-model review in Stage 3 is the quality gate, not per-agent model strength. Do not override to Opus without USER's explicit request.

Launch all three agents simultaneously using the Agent tool. Each agent gets:
- The test file(s) content
- The stub module content
- The brief's Verification section and Behavior Map Entries
- Its persona-specific context (below)

Each agent is read-only — no edits, no execution.

### Agent 1: QA Reviewer

**Lens:** Test quality — are these tests trustworthy?

You are a QA engineer reviewing test files written BEFORE implementation (test-first). The implementation does not exist yet. Tests should fail against the stub and pass only when the feature is correctly built.

Check for:
- **Vacuous assertions (BLOCKER)** — Tests that pass regardless of implementation. Hardcoded truths, assertions on always-true conditions, `toBeDefined()` without value checks.
- **Vacuous passes against stub (BLOCKER)** — Run the logic mentally against the stub. If a test would pass against the stub's no-op implementation, it needs a control assertion proving it can distinguish working from broken.
- **Assertion-behavior mismatch (BLOCKER)** — Test name says one thing, assertion checks something else. "locked cards are non-tappable" but assertion only checks a CSS class exists.
- **Missing negative assertions (WARNING)** — Good tests verify what SHOULD and SHOULD NOT happen. "User sees X" should also check "User does NOT see Y."
- **Insufficient specificity (WARNING)** — Locators like `.locator('div')` instead of `.locator('.entry-card')`. Text assertions that match too broadly.
- **Test isolation (WARNING)** — Tests sharing mutable state, order-dependent behavior, leaked globals between test cases.
- **Mock accuracy (WARNING)** — Do the mock helpers (escHtml, formatTime, etc.) match the real implementations? Does the mock DOM support the operations the real DOM would?

### Agent 2: Code Expert Reviewer

**Lens:** Technical correctness — will these tests catch real bugs?

Read the persona file at `~/Projects/dev-reference/agents/review-code-expert.md` for full instructions. Apply its checklist with this additional test-specific focus:

- **Stub API surface** — Does the stub match the brief's API spec exactly? Missing methods, wrong signatures, missing parameters?
- **Mock DOM fidelity** — Does the mock `createElement`/`querySelector`/`classList` implementation support the operations the real code will need? Missing methods = tests that pass in mock but fail in browser.
- **Selector verification** — For e2e tests, are the selectors (`.entry-time`, `.card-expand`, `.follow-btn`, `.fav-star`) consistent with the brief's HTML template? Grep the brief for the actual class names.
- **Convention compliance** — Does the test follow patterns from existing tests in the same directory? Check sandboxed eval pattern, import style, mock setup, assertion patterns against 2-3 existing tests.
- **Data-model invariant changes (second-order regressions)** — Does this change alter the cardinality or shape of stored data (rows-per-key, nullable→required, a new enum value, a new row written per event)? If so, enumerate every EXISTING query/code path that reads that data and confirm a test exercises it AGAINST the new data state. New features are tested from a clean slate; the bug is usually old code meeting new data. Flag [BLOCKER] if a cardinality change (e.g. 1→N rows per key) has no test that drives an existing reader through the multi-row state. (Evidence: 2026-05-29 #827 Slice 0 — renewal began writing a new subscriptions row per season, breaking the `.maybeSingle()`-by-`stripe_customer_id` lookups that assumed one row per customer; every test started from a single-row slate, so the crash was untested.)
- **Race conditions** — For e2e tests, are there unguarded async operations? Missing `waitForSelector`, assertions without timeouts, clicks before elements are interactive.
- **Edge cases from pre-mortem** — Read the pre-mortem file if it exists. Are the HIGH/MEDIUM risks addressed by tests?

### Agent 3: Domain Expert Reviewer

**Lens:** Behavior completeness — do these tests cover what users actually do?

Read the persona file at `~/Projects/dev-reference/agents/review-domain-expert.md` for full instructions. Apply with this test-specific focus:

- **Behavior map coverage** — For each behavior map entry tagged `[untested]` in the brief, is there a corresponding test? List any gaps.
- **Realistic test data** — Are entry fixtures realistic? Real gym names ("Acme Athletics"), real division names ("Senior Level 5"), real team names ("Bears"). Not "Team A" / "Division 1."
- **Domain edge cases** — Program-only entries (no team), teams competing multiple times, gym name variants, entries with missing fields (no hall, no city).
- **User state coverage** — Do e2e tests cover: unfollowed card, followed card, no cards available (skip gracefully)? Does the test handle the smart default / browse-full-btn flow?
- **Competition context** — In the real app, users are at loud events, one-handed, stressed. Do the e2e tests exercise the primary one-tap flows (expand, follow, collapse) rather than complex multi-step sequences?

## Stage 2: Synthesize Findings

After all three agents return:

1. **Deduplicate** — Same issue flagged by multiple agents = higher confidence. Note consensus.
2. **Classify** — Organize by severity: BLOCKER > WARNING > NIT.
3. **Build context file** — Write combined findings + test files to a temp file for Gemini.

## Stage 3: Cross-Model Review (Gemini) — depth + breadth pattern

**Background:** An empirical A/B on 2026-04-11 showed that a single broad Gemini review call reliably drops one review dimension under cognitive load (mock fidelity, month-boundary coverage, or vacuous passes — varies by run). Parallel focused calls catch the depth question they're asked but miss unexpected findings outside the checklist. The reliable pattern is **two parallel calls: one focused on the hardest single question, one deliberately unstructured breadth sweep.** See `~/Projects/dev-reference/patterns/cross-model-review-depth-breadth.md`.

**Preflight (fail loudly):** `command -v agy >/dev/null || { echo "PREFLIGHT FAIL: agy not installed — cross-model test review OFFLINE"; exit 1; }`. `agy` is the Antigravity CLI; `gemini` is dead (free tier retired 2026-06, issue #823). If `agy` is missing or unauthed, STOP — do not pass the gate on a Claude-only review.

Run TWO `agy -p` calls in parallel, both against the same files (test file + stub + source being tested, if applicable).

**CRITICAL — never use `@file` references.** `@file` is workspace-relative and silently fails for files outside the main repo (worktrees, sibling repos). When it fails, the model tries to find the files itself, hallucinating paths and burning tool calls on a fruitless filesystem search. Always inline file contents into the prompt **using temp-file composition** (see invocation pattern below). The shell reads the file before `agy` receives the prompt — workspace boundary is irrelevant.

**CRITICAL — never invoke `agy` without `--model "<display string>"`.** `--model` is mandatory and takes the exact display name from `agy models` (there is **no `-m` short flag** — that was gemini-cli). Use `--model "Gemini 3.1 Pro (Low)"` (breadth) or `--model "Gemini 3.1 Pro (High)"` (depth, fallback to Low). See `~/Projects/dev-reference/patterns/cross-model-review-depth-breadth.md`.

**CRITICAL — validate that file inlining worked.** Gemini will fabricate plausible findings when files aren't actually inlined (e.g. citing test names that don't exist). Always cross-check at least one quoted identifier in Gemini's response against the actual file. Include in the prompt: "If you flag a finding, you MUST quote a snippet from the actual code to prove you read it." See `~/Projects/dev-reference/patterns/shell-llm-prompt-composition.md` § "How to detect that prompt building silently failed".

### Call A — Depth (focused on the hardest single question)

Pick ONE question based on what the test file is exercising. Do not combine multiple questions into this call — focus is the point.

| Feature type | Depth question |
|---|---|
| API handler + DB mock | "Walk through every `await supabase.from(...)...` statement in the source file and confirm the hand-rolled mock in the test file faithfully emulates every chain pattern (method sequence, `{ data, error }` shape, thenable vs chainable). Flag [BLOCKER] for any chain the mock would fail to emulate. **Then verify terminal-operator CONTRACT fidelity, not just chain shape:** `.single()` and `.maybeSingle()` both ERROR when more than one row matches; `.maybeSingle()` returns null on zero rows; `.single()` errors on zero. For every query, inspect its filter columns — **if a query filters by a NON-UNIQUE column (e.g. `stripe_customer_id`, not a primary key or a unique compound key) and the mock always returns exactly one row regardless of state, flag [BLOCKER]:** the mock cannot represent the multi-row case, so a multi-row regression is structurally invisible. Pay special attention when the diff INTRODUCES new rows for a key that existing queries already read by." |
| Time/date logic with fixtures | "Independently compute every `vi.setSystemTime(...)` fixture's expected output and compare to the asserted value. Flag any mismatch. Flag any fixture that falls inside a DST transition hour." |
| E2E with DOM selectors | "Grep the actual HTML files for every element ID/class the test uses. Flag any selector that doesn't appear in the HTML." |
| State machine / reducer | "Enumerate every state transition the tests cover and compare to the brief's state table. Flag missing transitions." |
| Parser / extractor | "Walk through each input fixture and independently compute the expected output. Flag mismatches." |

Model: `Gemini 3.1 Pro (High)` (fallback `Gemini 3.1 Pro (Low)` on capacity error). Depth questions benefit from the stronger reasoning model.

### Call B — Breadth (deliberately unstructured)

Prompt template (no numbered checklist, no "do NOT flag" list — those constraints are what cause dimension-dropping):

```
Act as a senior QA engineer reviewing a test file written before
implementation. Three other reviewers have already flagged the obvious
issues: vacuous passes, selector verification, behavior map coverage,
basic mock correctness. Your job is to find what they missed.

Look for things like:
- Test names that don't match what the assertions actually check
- Repetitive hygiene issues (cleanup duplication, fragile fixtures)
- Cases where the test would pass for the wrong reason
- Edge cases in the feature's domain that nobody wrote a test for
- Anything that makes you say "huh, that's suspicious"

Classify findings as [BLOCKER], [WARNING], or [SUGGESTION]. Be terse.

[inline test file content here via $(cat <absolute-path-to-test-file>)]
[inline stub content here via $(cat <absolute-path-to-stub>)]
[inline source file content here via $(cat <absolute-path-to-source>) if applicable]
```

**Invocation pattern — temp-file composition (the only form that works):**

Do NOT use `agy -p "$(cat <<'PROMPT' ... $(cat /path) ... PROMPT)"` — the single-quoted heredoc delimiter blocks shell substitution, so `$(cat /path)` arrives at the model as literal text and it fabricates findings about files it never read. This trap has bitten multiple times; see `~/Projects/dev-reference/patterns/shell-llm-prompt-composition.md`.

Instead, build the prompt to a file via a shell script and pass the file to `agy`:

```bash
#!/bin/bash
set -e
PROMPT_FILE=$(mktemp)

# Static header (quoted heredoc — no expansion needed)
cat > "$PROMPT_FILE" <<'HEADER'
Act as a senior QA engineer reviewing test files written before implementation.
[rest of breadth template above]

If you flag a finding, you MUST quote a snippet from the actual code to prove
you read it.

=== TEST FILES UNDER REVIEW ===
HEADER

# Dynamic content (plain cat — always expands, no quoting hazards)
cat /absolute/path/to/test1.test.js >> "$PROMPT_FILE"
cat /absolute/path/to/test2.test.js >> "$PROMPT_FILE"

# Invoke agy with explicit model (--model is mandatory; takes the display string)
agy --model "Gemini 3.1 Pro (Low)" -p "$(cat "$PROMPT_FILE")"
rm -f "$PROMPT_FILE"
```

Model: `Gemini 3.1 Pro (Low)` for breadth. `Gemini 3.1 Pro (High)` for depth, fallback `Gemini 3.1 Pro (Low)` on capacity error. Always pass `--model` explicitly — see CRITICAL note above.

### Synthesize both calls

1. **Consensus findings** (both A and B flagged) → highest confidence, present as BLOCKERs even if individually classified lower.
2. **Depth-only findings** → medium confidence on their specific dimension.
3. **Breadth-only findings** → evaluate each carefully; these are often the highest-leverage catches because they're things you didn't know to look for. Do NOT dismiss as "out of scope" without a concrete reason.
4. **Conflicts** → if A says something is fine and B flags it, investigate before choosing.

Then merge with the Claude 3-agent findings from Stage 2 before moving to Stage 4.

## Stage 4: Final Report

Present a unified report to the conversation:

```markdown
## Test Review — [Feature Name]

### Files Reviewed
- [list of test files and stub]

### Blockers (must fix before showing to USER)
- [finding] — flagged by [agent(s)] [+ Gemini if confirmed]

### Warnings (should fix)
- [finding] — flagged by [agent(s)]

### Suggestions (optional improvements)
- [finding] — flagged by [agent(s)]

### Coverage Assessment
- Behavior map entries covered: N/M
- Behavior map gaps: [list any B# entries without tests]
- Pre-mortem risks addressed: [list HIGH risks with/without test coverage]

### Consensus Findings (2+ reviewers agree)
- [finding]

### Gemini-Only Findings (fresh perspective)
- [finding]

### Verdict
[PASS — ready for USER review / FAIL — fix blockers first]
```

After presenting the report, fix any BLOCKERs before proceeding. WARNINGs should be addressed or explicitly justified.

## Stage 5: Test Review File for USER + Clear the Gate Lock

**Gate lock** — the PostToolUse `test-review-gate-post.sh` hook has been tracking test-file writes in this worktree. Once cumulative tests crossed 5, it created a lock at `/tmp/review-tests-pending-<cwd_hash>.lock` that blocks further impl-file writes and test-suite runs until this skill completes.

**Hard precondition: verify behavioral RED before clearing the lock.** "Tests are RED" is not enough — they must fail on **assertions**, not on import resolution. See `~/Projects/dev-reference/patterns/red-state-must-be-behavioral.md` for full rationale.

Steps:

1. Create stub modules at every canonical import path referenced by the tests. Minimal exports only — no behavior. Mark `// STUB — replace with real impl` on line 1. For paths that have an intentional v1 "not implemented" final form (e.g. a paypal-adapter stub per a brief), the stub IS the impl; leave it as a real file without the STUB comment.
2. Run the test suite. The vitest summary alone is not enough — scan the failure messages.
3. Categorize every test:
   - **Assertion failure** (`expected X to be Y`, `expected promise to reject`, status mismatch, missing field) → legitimate RED ✓
   - **Module-resolution failure** (`Cannot find module`, `X is not a function` on a missing export) → stub surface is incomplete ✗
   - **Test passing against stub → HARD GATE FAILURE.** A test that passes against the no-op stub has proven NOTHING — it is a failure, the same category as a skip. There is NO "justified" or "coincidentally legitimate" stub-pass. The usual culprit is a negative-only assertion (`queryByText(...).not.toBeInTheDocument()`, "does not throw", "renders no cards") that a null/empty stub satisfies. Fix it by **pairing the negative assertion in the SAME test with a positive assertion the stub cannot satisfy** (e.g. assert the real card renders AND the unknown-type one does not). Do NOT write a justification. Do NOT clear the lock. Re-run until **0 tests pass against the stub.** (Evidence: 2026-06-13 S1.3 — reported 3 stub-passes as "justified"; USER: "stub passes are failure - i don't know how many fucking times i have to say that.")
   - **SKIPPED (conditional on an absent resource)** — DB-integration tests gated on `TEST_SUPABASE_URL`, e2e gated on `TEST_BASE_URL`, any `conditionalDescribe = HAS_X ? describe : describe.skip`. A skipped test has demonstrated **nothing** — it is neither RED nor GREEN. It does NOT count toward behavioral-RED clearance. See `red-state-must-be-behavioral.md` § "integration / DB tests."
4. Report counts: "Tests failing on assertions: N", "Tests failing on imports: 0 (required)", **"Tests passing against stub: M — MUST be 0; any M>0 is FAIL, fix and re-run"**, **"Tests SKIPPED / validation-deferred: K (resource each needs)"**.
4b. **Validation-deferred handling (skipped integration/DB tests).** These cannot show RED at review time because the resource (migration on a test branch, deployed endpoint) doesn't exist yet. Do NOT let them clear silently:
   - Catalogue each in the review file under a **`## Validation-Deferred (Gate 2)`** section, naming the resource it needs and stating "unvalidated until run RED→GREEN against <resource>."
   - The slice is NOT done — and **no PR may open** — until **Gate 2** runs: (a) RED-baseline against the un/incompletely-provisioned resource, (b) GREEN against the correct one, (c) a **mutation check** on the highest-risk assertions (break one CHECK/FK/RLS/seed-count, confirm only the matching test flips red, restore). GREEN-only is the vacuous-pass trap. The migration-not-applied state is the DB test's "stub."
   - Clearing the Gate 1 lock (below) on the *unit* tests' RED is fine — but the review report's verdict must say "PASS for Gate 1; K tests validation-deferred to Gate 2," never an unqualified PASS.
5. **Only after step 4 returns N>0 assertion failures, 0 import failures, AND 0 stub-passes for the runnable tests, clear the Gate-1 lock:**

```bash
# When verdict = PASS (all blockers + warnings resolved AND behavioral RED verified):
rm -f /tmp/review-tests-pending-*.lock
```

If verdict = FAIL (unresolved blockers/warnings, OR import-resolution failures, OR **ANY stub-pass** — there is no justified stub-pass), leave the lock in place, fix, re-run. The lock stays active through as many cycles as needed.

**Evidence for the behavioral-RED requirement:** 2026-05-19 — #795 Slice 2. Declared tests RED with 16 module-resolution failures. USER flagged: "we go through this every single time. 'cannot find module' is not a valid test fail, it's vacuous." Added 6 stubs → 72 behavioral failures + 1 legitimate pass. The corrected RED is a completely different signal quality.

After clearing the lock, generate `tmp/test-review-<feature>.md` for USER's review. This is the artifact he reads and annotates — not the conversation.

```markdown
# Test Review — [Feature Name]

- [ ] Approved
- **Issue:** #NNN
- **Test files:** [list paths]
- **Stub:** [path]
- **Tests passing against stub:** 0 (REQUIRED — if this is not 0 the gate has not passed; do not generate this file)
- **Tests failing against stub:** N (behavioral assertions)
- **Validation-deferred (Gate 2):** K (DB/integration tests that only skip locally — unvalidated until run RED→GREEN+mutation against <resource>)

---

## Validation-Deferred (Gate 2) — NOT yet proven
> These N tests skip without <resource> and have demonstrated nothing. They become trustworthy only after a RED→GREEN+mutation run against <resource>. No PR before that. List them so the deferral is explicit, not silent.

---

## Unit Tests

### [Group Name] ([B# references])

| # | Test | What it proves |
|---|------|---------------|
| 1 | [test name from describe > it] | [one-line plain-language explanation] |
| 2 | ... | ... |

**Comments:**

### [Next Group]
...

---

## E2E Tests

### [Group Name]

| # | Test | What it proves |
|---|------|---------------|
| 1 | [test name] | [one-line explanation] |

**Comments:**

---

## Exempt from Automated Testing
- [B# — reason] (verified in manual test plan)

## Product Decisions Reflected
- [Decision and rationale, e.g., "Program-only entries show only Notify button"]

## Review Notes
_USER: add comments inline after each group's table, or here for general feedback._
```

**Guidelines for the review file:**
- Group tests by feature area, not by describe block — USER reads by concept, not code structure
- "What it proves" should be plain language a non-developer can understand — no code, no class names
- Include the behavior map reference (B#) in the group header so USER can cross-reference the brief
- Keep it under 100 lines — this is a checklist, not documentation
- The `Comments:` line after each group is where USER writes feedback
- After USER reviews, incorporate feedback into the tests, then delete the file
