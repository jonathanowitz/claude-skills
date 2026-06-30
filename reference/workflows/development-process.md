# Development Process Workflow

**Example Project Development Guidelines**  
*For Claude Code and Codex CLI*

---

## Core Principles

### Quality Over Speed
We prioritize well-architected, maintainable code over rapid iteration. Every feature should be thoughtfully designed before implementation begins.

### Collaborative Review
Code reviews aren't gatekeeping—they're collaborative quality assurance. Reviews should catch issues early, share knowledge, and improve both the code and the developer.

### Incremental Progress
Complex features are broken into manageable milestones. Each milestone should be completable, reviewable, and mergeable independently when possible.

### Refactor as You Go
Every new feature is an opportunity to improve the code it touches — and the question to ask first is **"should we extract before we add?"** When a plan modifies a god module in 3+ places, when state has multiple owners, or when a fix requires touching N call sites that share a missing abstraction, the right move is to extract the seam first and build the feature on the refactored foundation. The refactor is part of the feature, not a follow-up. Follow-ups never happen.

Default to extraction for new features. Default to in-place patches only for narrow bug fixes. The choice must be explicit, never implicit. See `~/Projects/dev-reference/methodology/refactor-as-mitigation.md` for the diagnostic and decision procedure. Both `/shape-project` and `/pre-mortem` enforce this gate.

### Documentation as Code
Technical plans, architectural decisions, and implementation rationale live alongside the code. Future developers (including our future selves) should understand not just *what* we built, but *why*.

### Fail Fast, Learn Fast
Automated testing and validation should catch issues before human review. CI/CD pipelines are our first line of defense.

### Self-Validate Before Reporting
Always read back modified files, grep for expected changes, verify syntax/logic is correct. Never fail silently — state blockers and recommend solutions. Prefer partial delivery over delay (label clearly as partial).

### Security-First Tool Selection
Vet tools before suggesting. Prefer well-established, widely-used libraries with active maintenance. Flag security considerations explicitly when recommending tools.

---

## Planning Methodology

### Shape Up
- Shape before building: frame the problem, sketch the solution, identify rabbit holes
- Think in scopes (vertical slices) not tasks
- Track as uphill (figuring out) or downhill (executing)
- Breadboard or sketch solutions before coding

### Slice Completeness Rule: Wiring Ships With Proof
A slice that wires an interactive element (button, link, form submission) must **prove the wiring works** before shipping. Never ship wired-but-unverified UI.

**Two layers of proof, different lifespans:**

1. **Browser verification (mandatory, development-time gate):** Click every new/modified interactive element in a real browser via `vercel dev`. This is the primary wiring check — see `self-validation-protocol.md` → "Browser verification gate." Not optional, not replaced by any automated test.

2. **Smoke test (permanent, journey-level):** If the wired element is part of a critical user journey (sign in, subscribe, follow a team, manage account), that journey gets ONE permanent E2E smoke test in the `smoke` suite. The smoke test walks through the full journey, which implicitly verifies every button along the way. One test per journey, not one test per button.

**What does NOT get a permanent E2E test:** Individual button wiring, minor UI interactions, secondary flows. These are verified by the browser gate during development. If they break later, the journey-level smoke test catches it (because the journey can't complete with a broken button). If the interaction isn't part of any critical journey, it doesn't need permanent automated coverage — the browser verification at ship time is sufficient.

**The failure mode this prevents:** Slice 1 builds the API + renders a button. Slice 2 "will write the E2E test later." Between slices, nobody clicks the button. The wiring is broken but invisible — unit tests pass (mocked), integration tests pass (real DB), but the click handler was never connected. The browser verification gate catches this at development time. The smoke test prevents regression.

**Sizing guidance:** The permanent smoke suite should stay at ~10-20 tests total covering critical journeys. If the suite grows past 20, audit for redundancy — multiple tests covering the same journey, or individual-interaction tests that should be journey-level.

(Evidence: 2026-04-14 #598 — Notify Me buttons rendered but click handler not wired; caught by USER in manual testing, not by any test. 2026-04-16 #621 — pricing.html Subscribe button wiring was originally planned for Slice 1 with E2E deferred to Slice 2; caught during test review as a repeat of the same pattern.)

### Prior Art Discovery
Before breadboarding algorithms or complex logic:
- Ask: "Do you have an existing implementation?" (Excel, Notion, paper, code)
- Working prototypes often contain the real algorithm already figured out
- Capture the actual logic — don't assume green field

### Decision Gates
Prevent strategic/tactical context switching:
- **Before building:** Is this feature approved? Is this urgent? If unclear, ask before coding
- **After features:** Feature complete → test → strategic review (ship/defer/pivot)
- **During implementation:** If strategic questions arise, capture for end-of-session discussion

---

## Development Workflow

### Stage 1: Ideation & Capture
**Human-driven**

1. **Capture ideas** in `backlog/ideas.md`
   - One-line description with context
   - No need for full details yet
   - Tag with priority indicators if obvious (High/Medium/Low)

2. **Refine in conversation** when ready to work on an idea
   - Discuss with Claude in terminal/chat
   - Explore edge cases, constraints, user impact
   - Consider technical feasibility

### Stage 2: Frame the Problem
**Collaborative: Human + Claude Code**

1. **Run `/frame`** — explore the problem space conversationally
   - Separate the surface request from the underlying problem
   - Ask one question at a time: who, when, current state, triggers, success criteria, constraints
   - Output: problem brief (problem statement, current state, success criteria, constraints, cost of inaction)
   - No solution language — just the problem

2. **Save problem brief** to `example-context/briefs/` or project ideas file

3. **Brief-vs-shipped audit** (mandatory for any slice past the first in a multi-slice brief)
   - For each file the brief references, diff the current file against the brief's quoted snippets / line numbers / assumed state.
   - One grep per target file: `grep -n "<brief's key identifier>" <file>`. Confirm the identifier still exists and is at the assumed line range.
   - Common drift sources: prior slice shipped and renamed something, an unrelated PR refactored the target area, a hotfix landed on main, a dependency was upgraded.
   - If drift is found, update the brief's quoted snippets and revise any assumption that relied on stale state **before** writing the plan. Don't plan against a fiction.
   - (Evidence: 2026-04-13 competitor-pills-slice2-setup — brief assumed pre-slice-1 state of app.js; slice 1 had shipped the `_af` shim that changed every target line. 2026-04-14 slice-3-ship — brief-vs-shipped reconciliation caught three drift points during planning.)

### Stage 3: Shape the Solution
**Collaborative: Human + Claude Code + Gemini**

1. **Run `/shape-project`** — design the solution against the framed problem
   - Key decisions table (question, decision, rationale)
   - **Breadboard** (mandatory for UI-touching features):
     - UI Affordances table (ID, Place, Affordance, Type)
     - Code Affordances table (ID, Operation, Description)
     - Wiring table (From, To, Condition)
     - Shared State table (State, Storage, Read By, Write By)
     - Visual Wiring Diagram (Mermaid flowchart)
   - Behavior map entries tagged `[untested]`
   - Verification section (unit + e2e test specs)
   - Reference format: `briefs/schedule-intake-pipeline.md`

2. **Refactor-as-Mitigation pass** (mandatory, before Gemini)
   - Apply the diagnostic from `~/Projects/dev-reference/methodology/refactor-as-mitigation.md` to the technical approach you just drafted.
   - Ask: Does the plan modify a god module in 3+ places? Does any new state have multiple owners? Does a "fix" require touching N call sites that share a missing abstraction? Does the brief introduce a new module *and* require modifications to several existing files?
   - If yes to any: add a **"Pre-Feature Refactor"** section to the brief listing each proposed extraction (module name, what it owns, which risks it eliminates), and update the slice plan so the refactor lands as its own slice(s) **before** the feature slices.
   - Default to recommending extraction for new features. Make the choice explicit in the brief.
   - The `/shape-project` skill enforces this as Step 7.

3. **Gemini cross-model review** (mandatory)
   - Run `/second-opinion` with the shaped brief (now including any refactor pass output) — use the brief/design review role prime and `gemini-3.1-pro-preview`
   - Review for: completeness, breadboard quality, risks, behavioral gaps, copy/UX
   - Incorporate feedback before presenting to USER
   - Document what changed in a "Cross-Model Review" section

4. **Pre-mortem** (mandatory for non-trivial features)
   - Run `/pre-mortem` against the brief. 7 expert personas surface failure modes in parallel.
   - The pre-mortem orchestrator runs a second Refactor-as-Mitigation pass during synthesis (Step 5 of the skill) — for every HIGH risk surfaced by the personas, evaluate whether the right mitigation is "extract a seam" rather than "patch in place." Group risks by the extraction that would eliminate them.
   - The pre-mortem report ends with an explicit (a) patch / (b) refactor choice — there is no default.
   - If significant findings emerge, return to step 1 of Stage 3 and reshape.

5. **USER reviews and approves the brief**
   - Iterate on design decisions, copy, and UX
   - Re-send to Gemini after significant reshaping

6. **Create GitHub issue** with the finalized brief content

7. **Create worktree + feature branch** — implementation begins here, not before

### Stage 4: Test Specs (Red/Green TDD)
**Claude Code writes, Human reviews**

This is the gate between "brief approved" and "start writing implementation code." The brief's Verification section defines *what* to test. This step turns those descriptions into actual test files with real, failing assertions.

**`test.todo()` and `test.skip()` are not test cases.** They are outlines. This stage requires executable tests that run, fail with assertion errors, and will pass once the implementation is correct.

#### Red/Green Mechanical Checkpoints

These are machine-verifiable gates — not process suggestions. The test runner's exit code is the proof.

**RED checkpoint (before implementation begins):**

> **Hard rule** — Tests that fail with `Cannot find module` / `ENOENT` / `ReferenceError` are NOT in valid RED state. The test bodies never ran; the assertions never executed. Create stub modules at the canonical import paths (minimal exports, no behavior — API handlers return 501, pure functions return `null`) and re-run. Every failure must cite an assertion. Each test that passes against the stub must be individually justified or deleted. Full pattern + stub template: `~/Projects/dev-reference/patterns/red-state-must-be-behavioral.md`. (Evidence: 2026-05-19 #795 Slice 2 — declared RED with 16 module-resolution failures; corrected to 72 behavioral failures + 0 stub passes after adding stubs.)

- All test files import and run successfully (no `ENOENT`, `ReferenceError`, `SyntaxError`)
- Every test for NEW behavior FAILS with a behavioral assertion error:
  - **Unit tests:** GOOD: `expected fn to be called 1 times, got 0` — behavior missing. GOOD: `expected true to be false` — wrong return value. BAD: `ENOENT`, `ReferenceError` — structural, proves nothing.
  - **E2e tests (refactor):** GOOD: test asserts new interaction, old UI doesn't match (e.g., clicks pill, app has dropdown). This is the strongest RED — catches both absence and regression.
  - **E2e tests (new feature):** GOOD: test asserts behavior that doesn't exist yet (e.g., taps card, no expand). The app loads, the test engages, but the spec doesn't match reality.
  - **Both e2e types:** BAD: test can't navigate to the page, dev server not running, `net::ERR_CONNECTION_REFUSED` — structural, proves nothing.
- `npx vitest run <file>` or `npx playwright test <spec>` exits non-zero
- **Capture the failing output** — this is the deliverable, not just the test file

**GREEN checkpoint (after implementation, before PR):**
- The same tests that were RED now PASS — no test modifications allowed to achieve this
- Full test suite passes (no regressions): `npm test` exits zero
- If a test had to be modified to pass, that's a signal: either the test was wrong (fix and re-RED) or the implementation deviated from the spec (fix the implementation)

**The Red/Green contract applies everywhere:** Stage 4 test specs, bug fix agents, night-shift tasks, and any autonomous agent that writes tests. The test runner's exit code is the only authority — not an agent's self-report, not a comment saying "tests written."

**Size doesn't bypass test-first.** A "simple bug squash," a one-line fix, or a quick logic correction still needs: worktree, failing test that reproduces the bug, subagent for the test (so the agent writing the test isn't biased by the implementation). The 30 seconds saved by skipping setup is paid back 10× during regression debugging. If the bug feels too small to test, write the test anyway — it's the regression guard. (Evidence: 2026-05-12 #544/#785 — bug squash session jumped to code without worktree, test-first, or subagent; corrected after USER flagged it. Independent test-writer subagent pattern then worked cleanly. The "small task" framing was the failure mode.)

**The inverse is also true: match ceremony to risk-class.** Personal-productivity scripts and one-off tooling do NOT need vitest + 36 RED-state tests + worktree + PR ceremony. The development-process gates above target *product code that ships to users*. For personal scripts (consulting tools, log enrichers, throwaway analyses), the ceremony tax exceeds the regression-prevention value. **Heuristic:** if the script lives in `~/Projects/<personal-thing>/scripts/` or `tmp/` and isn't deployed, skip the test-first ceremony — but add a smoke check (does it run? does the output look right?) before considering it done. (Evidence: 2026-05-13 consulting-launch — set up vitest with 44 deps + 36 RED-state tests for personal-productivity scripts; USER pushed back. Production-grade ceremony for non-production code is its own anti-pattern.)

#### Sequence (each step is a hard gate — do not skip or reorder):

1. **Start the dev server** (`vercel dev --listen 8765`) if writing e2e tests
   - E2E tests need a running app. Skipping this step is what causes placeholder tests.
   - Unit tests that don't need a server can proceed without this.

2. **Write ALL test files — unit, integration, AND e2e — with real `expect()` assertions**
   - Unit tests → `tests/<area>/<feature>.test.js` with real assertions against the module's API.
   - **Integration tests → `tests/api-integration/<feature>.test.js`** for any endpoint that reads/writes Supabase. These run against `TEST_BASE_URL` with a real Supabase branch — no mocked clients. They catch RLS failures, missing columns, constraint violations, and query chain errors that unit tests with mocked Supabase hide. **If it touches Supabase, it gets an integration test. Not optional, not deferred to a later slice.** Stripe/external API calls can be skipped (require real credentials), but the Supabase read/write path cannot.
     - (Evidence: 2026-04-16 #621 — shaped brief specified only unit + E2E tests for 5 new API endpoints. Integration test gap caught during review but should have been structural.)
   - E2E specs → `e2e/<feature>.spec.js` with real test cases describing user behavior from the behavior map. E2e tests describe what the user sees and does — "navigate to schedule, tap a card, expect action row to appear." No placeholder selectors.
   - **E2e tests are written BEFORE implementation, not after.** The RED state depends on what's changing:
     - **Refactor existing UI:** The test asserts the new interaction model against the current app. It fails because the UI still uses the old pattern. Example: test clicks an "L1" pill in a filter row, but the app still has a dropdown select — the pill doesn't exist, the interaction model is wrong. This is the strongest RED: it catches both "feature absent" and "regression to old pattern."
     - **Net-new feature:** The test asserts behavior that doesn't exist yet. Example: test taps a card and expects an action row — cards don't expand yet. The app loads, the test engages, but the behavior is absent.
     - Both are behavioral failures — the app works, the test navigates and interacts, but the spec doesn't match reality. This is distinct from structural failures (`ENOENT`, `ReferenceError`) where the test can't even run.
   - If you can't write the e2e test because you don't know what the UI will look like, the brief isn't specific enough — go back to shaping.
   - Each test maps to a behavior map entry from the brief.
   - **Prohibited:** `test.todo()`, `test.skip()` without a specific reason comment, test blocks with no assertions, `expect(true).toBe(true)` or other vacuous assertions, placeholder selectors (e.g., `#TODO-selector`), deferring e2e tests to a later slice.
   - **Refactors where output stays the same:** When the implementation changes but the result doesn't (e.g., sequential to parallel, sync to async), test the *mechanism* — call ordering, timing, concurrency — not just the result. A test that only checks the final output will pass before and after the refactor, proving nothing. (Evidence: 2026-03-20 #388 — 13/13 tests passed before implementation because they only checked output shape.)
   - (Evidence: 2026-04-03 — USER flagged that deferring e2e to later slices defeats Stage 4's purpose. "If you write e2e tests after implementation, you're testing what you built instead of tests for the end result you want." The placeholder selector escape hatch was the mechanism enabling this.)

3. **Run the tests and capture the failing output**
   - Unit: `npx vitest run <test-file>` — expect assertion failures (not import errors or skips)
   - E2E: `npx playwright test <spec-file>` — expect real failures (element not found, wrong text, etc.)
   - **The deliverable to USER is the test run output showing real failures**, not just the test file. This proves the tests are executable and will detect the absence of the feature.

4. **Three-expert stub review** (catches vacuous passes the hook and Gemini miss)
   - Run three parallel expert agents against every test that **passes** against the stub:
     - **Code Expert** — analyzes *why* the test passes mechanically (stub return value, existing code path, assertion logic). Identifies whether the pass depends on real behavior or on the stub doing nothing.
     - **QA Expert** — assesses whether a buggy implementation could still pass the test. Checks assertion depth: does the test verify "something happened" or "the right thing happened"?
     - **Domain Expert** — evaluates whether the test captures the correct business rule. Flags missing edge cases and suggests additional scenarios.
   - Each expert independently classifies the test as **legitimate** or **vacuous**.
   - **If any expert flags a test as vacuous:** add a control assertion that pairs the negative test with its positive counterpart (e.g., before asserting "returns empty for X input," assert "returns non-empty for Y input" — proving the function actually filters, not that the stub returns empty).
   - **If experts disagree:** the most conservative assessment wins. A test flagged vacuous by even one expert must be hardened.
   - **If experts suggest new tests:** add them (domain experts often catch boundary cases the spec missed).
   - Re-run the test suite after fixes. No vacuous passes may remain.
   - (Evidence: 2026-04-01 #381 — 3 of 7 passing tests were vacuous (stub returned `[]`, tests asserted `length === 0`). QA expert caught all 3; code expert missed them. Domain expert suggested 2 additional tests for uncovered boundaries. Fixed by adding contrastive control assertions.)

5. **Run `/review-tests`** — automates steps 4 and this step as a single pipeline:
   - Spawns three parallel agents (QA, Code Expert, Domain Expert) against the test files + stub + brief
   - Synthesizes findings, then triggers Gemini cross-model review via `/second-opinion`
   - Presents unified report with BLOCKER/WARNING/NIT findings and coverage assessment
   - A single BLOCKER = test file must be revised before proceeding
   - Fix all blockers and re-run if needed before presenting to USER
   - (Replaces the manual Gemini pipe: `cat test-review-prompt.md <files> | gemini`. The skill handles prompt construction, parallelism, and synthesis.)

6. **Generate test review file and share with USER**
   - `/review-tests` auto-generates `tmp/test-review-<feature>.md` after fixing blockers
   - Format: test names grouped by feature area, one-line plain-language descriptions, `Comments:` lines after each group
   - USER reads the file, adds inline comments, checks the `- [ ] Approved` box
   - Incorporate feedback into tests, then delete the review file
   - USER approves the test contract before implementation begins

7. **Then proceed to implementation**

#### Why this sequence matters

(Evidence: 2026-03-19 #387 — wrote 15 `test.todo()` stubs, called them "Stage 4 tests," got approval, implemented the feature, and reported "545 tests passing" while fundamental integration bugs went undetected. Manual testing caught two showstopper bugs on first load: `ExampleApp` not assigned yet during init, and `loadData()` continuing after navigation to picker. Both would have been caught by a real e2e test that loaded the app and checked what appeared.)

Tests written after implementation test what was built, not what should have been built. Placeholder tests are worse than no tests — they give false confidence. The test run output is the proof that the contract is real.

#### Never defer e2e tests — not writing, not execution

E2e tests are written at Stage 4 alongside unit tests, before implementation begins. They are run and passing before an implementation session ends. Both halves are mandatory.

**Writing:** E2e tests describe user behavior from the behavior map. They are part of the spec, not a post-implementation validation layer. Deferring e2e tests to a "later slice" or "later session" means those tests will be written to match the implementation rather than the specification. This is the same failure mode as writing unit tests after — you test what you built, not what you should have built.

**Execution:** If an infrastructure blocker prevents running e2e tests (missing env vars, no dev server, missing test accounts), that blocker is the first thing to fix — not the last.

**Hard rule:** Do not checkpoint, session-capture, or report implementation as "complete" with unwritten or unexecuted e2e tests. If the tests can't be written because the UI isn't specified, go back to shaping. If they can't run, fix the infrastructure blocker. The session doesn't end until the e2e suite is green.

**E2e tests require understanding the test user's state.** The deterministic test database gives known users, follows, profiles, and competition data. Tests must be written with full knowledge of that state — not generic "load page, see content" helpers. Before writing any e2e helper function:
1. Read `e2e/test-config.js` for test constants
2. Read `e2e/fixtures/auth.setup.js` for the test user's profile state (home gym, follows, onboarding)
3. Trace the app's initialization flow with that user state (smart defaults, overlays, toasts)
4. Write the helper for the ACTUAL state, not an assumed generic state

(Evidence: 2026-04-02 #518 — wrote 12 e2e tests against the behavior map, deferred execution to "next session" due to missing `.env.test`. Next session spent 90+ minutes debugging: test helper assumed Tier 3 smart default (browse button) but e2e-user has follows triggering Tier 1 (favorites mode); home gym toast overlay blocked clicks; `preserveExpanded` implementation contradicted test expectations. All failures were deterministic and predictable from the test user's known state — not timing or infrastructure issues.)

#### Enforced by three gates

**Gate 1: PostToolUse hook** (`~/.claude/hooks/test-assertion-check.sh`) — fires on every Write/Edit to test files. Catches structural problems:
- `test.todo()` calls → flagged immediately
- Test blocks with zero `expect()` calls → flagged
- Assertion count < half of test count → warned
- Cannot be evaded by renaming — checks for the *absence* of assertions, not the presence of a keyword

**Gate 2: Three-expert stub review** — catches vacuous passes (tests that pass against stubs because they assert on empty/default behavior, not real logic). Three independent perspectives prevent blind spots: code experts miss domain gaps, QA catches assertion weakness, domain experts catch missing scenarios.

**Gate 3: Gemini review** (`~/Projects/dev-reference/prompts/test-review-prompt.md`) — catches semantic problems the other gates can't see:
- Vacuous assertions (`expect(true).toBe(true)`, `expect(body).toBeVisible()`)
- Assertion-behavior mismatches (test name says one thing, assertion checks another)
- Missing negative assertions (only checks what happens, not what shouldn't)
- A single `[BLOCKER]` from Gemini = revise before proceeding

#### Gates for this stage — fire before moving to Stage 5

Stage 4 does not ship until every gate below has fired. Self-trigger each one from context; do not wait to be prompted.

- [ ] PostToolUse assertion hook fired clean on every test file (Gate 1)
- [ ] `/review-tests` run end-to-end (3 Claude agents + Gemini depth+breadth) — produces `tmp/test-review-<feature>.md`
- [ ] All BLOCKERs from `/review-tests` fixed and re-run
- [ ] RED checkpoint captured: failing output saved to `tmp/red-<feature>.txt`, exit code non-zero
- [ ] Test review file shared with USER; his inline comments incorporated before implementation

(Evidence: 2026-04-16 #621 Slice 2 — `/review-tests` was skipped until USER prompted "did you get /second-opinion on the edges of the tests?" The rule existed; compliance was the gap. Self-triggering this list closes the gap.)

### Stage 5: Implementation
**Claude Code executes**

1. **Claude Code implements the approved plan**
   - Follow the technical plan closely
   - Tests already exist from Stage 4 — update selectors as implementation takes shape
   - Keep commits logical and well-messaged
   - Update PR with progress/changes

2. **Browser verification for every interactive element**
   - If the slice adds or modifies any button, link, form, or click handler: start `vercel dev`, navigate to the page, click the element, verify the outcome. This is a hard gate — not "run the tests," but "click the button in a real browser." See `self-validation-protocol.md` → "Browser verification gate."
   - (Evidence: 2026-04-14 #598 — Notify Me buttons rendered but click handler wasn't wired. 2026-04-16 #621 — identified as recurring pattern. Buttons that "look wired" in code but don't work in the browser are invisible to unit tests and often invisible to E2E tests with wrong selectors.)

3. **Self-review before requesting code review**
   - Run all tests locally
   - Check code formatting/linting
   - Verify plan was followed (or document deviations)

#### Gates for this stage — fire before moving to Stage 6

- [ ] Browser click-pass done in `vercel dev` for every new/modified interactive element (see `self-validation-protocol.md` → Browser verification gate)
- [ ] Unit suite green (`npx vitest run`) — no regressions from baseline
- [ ] Integration suite green for any endpoint touched (`npx vitest run tests/api-integration/`)
- [ ] Smoke suite green (`npx playwright test e2e/smoke/`) for the affected journey
- [ ] Deviations from the approved plan documented in the PR description

(Evidence: 2026-04-13 #595, 2026-04-14 #598, 2026-04-16 #621 all shipped rendered-but-inert buttons because the browser click-pass was skipped. Three strikes in four days made this a hard gate.)

### Stage 6: Code Review
**Codex reviews, Claude Code responds**

1. **Codex performs code review**
   - Human triggers review when CC signals implementation complete
   - Codex reviews for:
     - Correctness (does it work as intended?)
     - Code quality (readable, maintainable?)
     - Test coverage (edge cases covered?)
     - Performance (any obvious bottlenecks?)
     - Security (any vulnerabilities?)
     - Consistency (matches codebase patterns?)

2. **Claude Code addresses feedback**
   - Read Codex comments in GitHub PR
   - Make requested changes
   - Push updates to same PR
   - Respond to comments explaining changes

3. **Iterate until approved**
   - Human provides clarification if CC and Codex disagree
   - Repeat review cycle as needed
   - Codex gives final approval

#### Gates for this stage — fire before moving to Stage 7

- [ ] `/second-opinion` on the full branch diff — Gemini cross-model review on implementation, not just tests
- [ ] Pre-PR Validation Agent dispatched and passed (see `~/.claude/rules/hooks-and-agents.md`)
- [ ] All Codex review comments resolved (no open `request-changes`)
- [ ] CI green on the latest push

### Stage 7: Merge & Close
**Claude Code finalizes**

1. **Final checks**
   - All tests passing in CI
   - All review comments resolved
   - PR description accurate to final implementation

2. **Merge to main**
   - Squash commits if appropriate
   - Ensure commit message is descriptive

3. **Update artifacts**
   - Move brief item from `in-progress` to `completed` in backlog
   - Update architecture docs if significant changes were made
   - Add notes to brief about actual implementation vs. plan

4. **Update session context**
   - Update `next-steps.md` with what was completed
   - Note any follow-up work identified

#### Gates for this stage — post-merge

- [ ] `POST_MERGE_HOOK` signal acted on (session capture + background cleanup per `~/.claude/rules/hooks-and-agents.md`)
- [ ] Architecture docs updated in `example-context/` (codebase-map, app-behavior-map, database-schema as applicable)
- [ ] Behavior map entries re-tagged from `[untested]` to `[unit]` / `[e2e]` as tests landed
- [ ] Worktree + local branch removed by the post-merge cleanup agent (runs from main example-app checkout via absolute paths — no deferral)

---

## Tool-Specific Guidelines

### For Claude Code

**When creating PRs:**
- Use PR description as the technical plan
- Include "Relates to: [brief reference]" at top
- Structure description clearly: Overview, Approach, Testing, Open Items
- Draft PRs are okay for work-in-progress

**When reading reviews:**
- Check GitHub PR comments programmatically
- Address each comment with a threaded reply
- Ask human for clarification if review is ambiguous
- Don't mark conversations resolved—let Codex do that

**When blocked:**
- Document the blocker in PR or terminal
- Tag human for input via Obsidian markdown if needed
- Don't make architectural decisions beyond the approved plan without human sign-off

**Sub-agent protocol:**
- When spawning agents that touch the database, pass the schema inline in the prompt — agents start with a blank slate
- Proactively suggest parallel agents when tasks are independent or slow (>30 seconds)
- Run slow operations in background and continue other work

**File creation standards:**
- Create files for outputs >50 lines or reusable content
- Use descriptive filenames: `topic-YYYY-MM-DD.md`
- In new projects, read the README and look for project-specific CLAUDE.md first
- Check for ROADMAP.md before starting work

### For Codex CLI

**When reviewing plans:**
- Focus on architecture, not implementation details
- Call out missing edge cases or error scenarios
- Suggest alternative approaches if current seems problematic
- Be specific: reference architecture docs when relevant

**When reviewing code:**
- Prioritize correctness and security over style
- Be constructive: explain *why* something should change
- Approve when quality bar is met—don't nitpick
- Use GitHub's review features (comment, request changes, approve)

---

## Human Intervention Points

The human (USER) steps in when:

1. **Scope clarification needed** during brief creation
2. **Architectural disagreement** between CC and Codex
3. **External decisions required** (user research, business priorities)
4. **Stuck/blocked** on implementation approach
5. **Final approval** before merge if feature is high-risk

---

## Communication Patterns

### Claude Code ↔ Human
- Terminal for active development
- Obsidian markdown files when async input needed
- Clear, concise questions with context

### Codex ↔ Human  
- GitHub PR comments for reviews
- Human triggers reviews manually at milestones

### Claude Code ↔ Codex
- GitHub PR for all formal communication
- CC reads Codex comments, responds in PR
- No direct tool-to-tool communication—all via GitHub

---

## Quality Standards

### Code Must:
- Pass all existing tests
- Include tests for new functionality
- Follow existing code style/patterns
- Handle errors gracefully
- Include inline comments for complex logic

### PRs Must:
- Have clear, descriptive titles
- Include implementation plan in description
- Reference related brief/issue
- Show passing CI checks
- Have at least one approval (Codex)

### Documentation Must:
- Update architecture docs for significant changes
- Keep README current
- Document API changes
- Explain non-obvious decisions in code comments

### Testing Practices
- **Test with real data early** — Synthetic or filtered data misses edge cases (e.g., team names in multiple gyms, duplicate entries across contexts)
- **Run against actual dataset** (or realistic subset) when validating logic
- **Composite keys for non-unique data** — Use `"gym|team"` format when entity IDs aren't globally unique. Build keys using data's own scope, not the filter's selected scope
- **Run tests selectively** — Specific test files during development; full suite only for final validation

### Test Documentation Format
Use checkboxes for each expected criterion:
```markdown
### TC1: Feature Name
**Steps:**
1. Do action

**Expected:**
- [ ] Criterion 1 happens
- [ ] Criterion 2 visible
- [ ] Criterion 3 works

**Comments:**

```
Never use underscores or brackets as placeholders — just leave the field blank for the tester to fill.

---

## Documentation Standards

- **Keep documentation lean** — Aim for <10 .md files per project
- **Consolidate** related docs instead of fragmenting; delete obsolete docs (git history preserves them)
- **Single source of truth** — If information exists in code/schema/git, don't duplicate in docs; link to canonical sources
- **Evergreen over temporal** — Update existing docs when requirements change; create new ones only when topic is genuinely different
- **Archive** one-time artifacts (audits, reports) — don't leave in project root

---

## UI Patterns

### Mobile-First Controls
- Place toggle/action buttons in always-visible UI areas
- Bad: Toggle button inside a collapsing panel (can't collapse if you can't click it)
- Good: Toggle in sticky header, results bar, or fixed footer
- Avoid multiple sticky elements at same `top` value — they overlap; manage z-index

### Touch & Legibility
- Minimum touch target: 44x44px
- Body text: 16px+ to avoid iOS auto-zoom on input focus
- Design for 375px width (iPhone SE) first
- Favor legibility at distance and at a glance

### Offline-First
- Load data once, filter client-side with zero network dependency
- Every filter interaction should be instant after initial data load
- Competition venues have terrible cell signal — design for it

---

## Emergency Procedures

### If something breaks production:
1. Human creates hotfix brief
2. Skip normal planning—fix first
3. Retrospective after: update brief with what happened and why
4. Update process docs if procedure failed us

### If tools disagree irreconcilably:
1. Human reviews both perspectives
2. Human makes final call
3. Document decision in PR for future reference

### If process feels broken:
1. Stop and discuss with human
2. Update this document
3. Resume with new process

---

**Last Updated:** 2026-04-16
**Version:** 1.4 — Added brief-vs-shipped audit to Stage 2. Added "Gates for this stage" self-trigger checklists to Stages 4, 5, 6, 7 (closes the "proactive gate triggering" gap identified in the 2026-04-16 maintenance report).
**Previous:** 1.3 — Added "Refactor as You Go" core principle. Added Refactor-as-Mitigation pass to Stage 3 (between shape and Gemini) and explicit pre-mortem step (Stage 3 step 4).
**Maintained by:** USER / Claude Code
