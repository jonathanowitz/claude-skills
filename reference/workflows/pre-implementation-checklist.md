# Pre-Implementation Checklist

Run through this checklist before starting any feature or non-trivial task. Every item should be checked or explicitly marked N/A.

## Before You Build

- [ ] **Shaped brief exists:** Does a shaped brief exist for this work in `briefs/`? The brief must have: problem statement, breadboard (affordance tables + wiring + shared state + mermaid diagram), behavior map entries, verification section, and a Gemini cross-model review. If no brief exists, run `/frame` then `/shape-project` first. Exception: trivial bug fixes and single-line changes.

- [ ] **Reuse Audit present:** Does the brief carry a non-empty `## Reuse & Adaptation <!-- reuse-audit-section -->` section (Reuse/Adapt/Build-new per capability, with justification for every Build-new)? If it's missing or rubber-stamped, the Reuse Audit was skipped — send the brief back through `/shape-project` step 6 before building. See `~/Projects/dev-reference/conventions/reuse-audit.md`. (Lever 2 of the reuse-audit guardrail; rebuild stack only.)

- [ ] **UI primitive check (rebuild stack):** For every interactive or visual element in this slice, confirm the brief ran the UI sub-check on the MVS ladder (`conventions/minimum-viable-solution-ladder.md` rung 2): (a) `components/ui/*` already has it? (b) native HTML covers it (`<dialog>`, `<details>`, `<input type="search|date|range|...">`)?  (c) `npx shadcn add <x>` adds it? Hand-roll only if all three fail. A brief that classifies a button, input, overlay, or pull-to-refresh as Build-new without checking these rungs is incomplete.

- [ ] **Prior art check:** Asked USER if he has an existing implementation — Excel, Notion, paper, working prototype, or code? He often has the actual algorithm figured out. Capture the real logic, don't assume green field.

- [ ] **Code recon:** Checked `git branch | grep <feature>` and `git log` for existing work? Docs can be stale — the code repo is the source of truth.

- [ ] **Grep prior art before proposing structural change:** Before proposing a new schema, new feature flag, new DB convention, new retry/park mechanism, or new branching logic — grep the codebase for the analogous case. If a prior instance exists, extend the pattern; don't parallel-implement. The goal is one mechanism for each concept, not N. Applies especially to proposals that start "I'll add a new X to handle Y" — stop and check whether Y is already handled somewhere.
  - (Evidence: 2026-04-21 — generated city-only SQL for Tampa schedule; prior art in `gyms` table used `- <City>` suffix convention that a grep of `gyms.name` would have shown. 2026-04-21 — proposed new alias schema for Worlds PO; `gym_aliases` table already existed. 2026-04-22 — proposed new park-feature flag + delete options; `failure_count:3` pattern was already the established park mechanism. Three instances in four days.)

- [ ] **Issue exists:** Is this work tracked in a GitHub Issue? If not, create one first using the appropriate template. Add it to the project board. **Also update all related existing issues** — when a new plan affects existing issues (changed scope, new dependencies, revised approach), update those issues with a comment or body edit. Don't just create the new issue. (Evidence: 3 redirections in iOS reframing session — missed updating #42-#46 after creating #145)

- [ ] **Product solution first:** Before specifying a technical approach, ask: "Is there a product-level solution that's simpler or avoids the technical risk?" Data migrations, automation gates, and error handling patterns are especially prone to over-engineering when a user-facing solution (campaign, partial delivery, self-service) would be better. (Evidence: SQL migration vs user campaign, threshold gate vs partial publish, client-side fixes vs API contract — 5 instances where USER redirected toward product thinking)

- [ ] **Product intent validated:** Before implementing any UI, ask USER: "In one sentence, what should the user experience be?" Don't start from the technical spec or breadboard — start from the user's perspective. Before designing for any data model edge case, verify it exists in real data (`SELECT`, `grep`, sample). Don't build for hypotheticals.
  - (Evidence: 8 product-intent redirections across 4 sessions over 3 maintenance windows. Season-based vs date-based split, two-container vs inline chronological, separate picker vs reuse competitions view, fill-down for non-existent edge case, mockup from scratch vs real HTML/CSS.)

- [ ] **Scope is clear:** What's in? What's explicitly out? What rabbit holes should be avoided? If scope isn't clear, ask — don't assume.

- [ ] **Clickable prototype validated:** For any feature with new UI or changed UI patterns, generate a clickable prototype in a clickable-prototype tool (`~/Projects/example-d`) from the breadboard's UI affordances. Click through the flow, verify transitions make sense, and screenshot for the brief. If comparing approaches, build both as `/v1/` and `/v2/`. Skip for: pure backend changes, bug fixes to existing UI, config changes. See `~/Projects/dev-reference/guides/example-d-prototyping.md`.

- [ ] **Behavior map + test specs written:** Before any implementation code:
  1. Write behavior map entries for the feature — plain-language "when user does X, Y happens" descriptions including edge cases. Add to `app-behavior-map.md` tagged `[untested]`.
  2. Write test expectations in the brief's `## Verification` section — what unit tests and e2e tests should exist, what they verify, and which behavior map entries they cover.
  3. **Write ALL test files** from the Verification section — both `e2e/<feature>.spec.js` AND `tests/<area>/<feature>.test.js`. No placeholder selectors, no deferring e2e to later slices. E2e tests describe user behavior from the behavior map; their RED state is "feature doesn't exist yet." If the e2e test can't be written because the UI isn't specified, the brief isn't specific enough — go back to shaping. Share with USER for review before writing implementation code. See Stage 4 of `development-process.md`. **Use behavior map preconditions** (`app-behavior-map.md`) to determine test setup — `*Preconditions:*` specifies what the caller checks (auth, view, state); `*Callee guards:*` specifies what the called function checks internally (localStorage flags, server state). Tests must satisfy both layers.
  4. **Apply the stub-failure filter as you write each assertion.** Before writing any test assertion, mentally run it against `function fn() {}` (or the actual empty-stub form). If the assertion passes against the empty stub, don't write it — or rewrite it into a positive form that cannot pass. This is a pre-write check, not a post-hoc audit. Failure modes this catches:
      - **Shape tests:** `expect(typeof Mod.fn).toBe('function')` — stub has the function → vacuous → delete (every behavioral test that calls `Mod.fn` implicitly asserts the export surface; a dedicated shape test adds no signal).
      - **Bare resilience tests:** `expect(() => Mod.fn(bad)).not.toThrow()` — empty stub doesn't throw → vacuous → merge with a positive assertion in the same `it()` so the stub fails on the positive half.
      - **Negative-only pair tests:** `expect(calls).toBe(0)` after subscribing to a stubbed module → stub never fires subs → fold into the positive pair test (e.g., `expect(calls).toBe(1)` after one real fire + one idempotent no-op).
      - **Pattern-matching from precedent files:** existing test files in the repo may have legacy "vacuous-pass control" comments that are misleading — those tests sometimes dereference the return value and fail structurally against a true empty stub, but the comment makes it look like shape tests are OK. Re-derive the filter for every imported pattern; don't trust the comment.
      - **Mental test:** write out the expected failure message for each assertion. If no failure message can be produced against `function fn() {}`, the test is vacuous.
  4b. **Apply the mirror-test filter as a companion check.** The stub-failure filter catches tests that pass against an empty implementation. The mirror-test filter catches the opposite failure mode: **tests that pass *only* against one specific implementation and fail against valid alternatives**. These tests encode your implementation, not the product contract — they rot instantly when the impl legitimately changes, and they're blind to wrong impls that happen to match the asserted shape.
      - **The filter:** For each assertion, ask *"if I replaced the production code with a different but spec-correct implementation, would this test still pass?"*
        - **Yes → the test is a spec.** Ship it.
        - **No → the test is a mirror.** Rewrite it to assert a user-observable outcome instead of an internal helper call, or delete it and rely on an outcome-based test elsewhere.
      - **Red-flag shapes:**
        - `expect(SomeHelper.method).toHaveBeenCalled()` when `SomeHelper` is an internal or mocked module the production code calls conditionally. The test asserts "I wrote code that calls this helper"; it doesn't assert the user got what they wanted. Rewrite to assert the observable outcome (DOM state, emitted event, returned value, side effect on a real global).
        - `expect(privateState.foo).toBe(bar)` — reaching into module internals. The test is fragile to refactors that preserve behavior.
        - Any assertion against a `vi.fn()` mock of a dependency you *invented* for the test. If you mocked it into existence, you're testing the fiction, not the reality. Grep the production codebase for the mocked module before the test is accepted — if it doesn't exist, either build it as part of the slice or rewrite the test against the real dependency.
      - **Outcome-based rewrite pattern:** "the user tapped X" → assert what changed in the DOM, what was added to a real state container, what event was dispatched on `window`/`document`, or what was written to a real global like `localStorage`. Implementation-agnostic. Survives refactors. Catches alternative-valid-impl divergence AND wrong-impl-that-matches-shape simultaneously.
      - (Evidence: 2026-04-13 #595 Slice 2 — `entry-card-comp-btn.test.js` asserted `expect(UpgradePrompt.open).toHaveBeenCalledTimes(1)` for the non-Plus path. The module `UpgradePrompt` was invented during test-writing and did not exist in production. The implementation called `window.UpgradePrompt?.open()` guarded with optional chaining → silent no-op in the real browser → test stayed green. USER caught the phantom via manual testing. The test should have asserted the outcome: "non-Plus tap does not add a context AND surfaces a user-visible upsell affordance" — implementation-agnostic, would have failed regardless of which mock I injected. The mirror-test filter would have flagged the `.toHaveBeenCalled` assertion at write time.)
  5. **Create a stub module** with the correct API surface but empty implementations (functions return undefined, don't call callbacks). Tests must import and run against the stub — failing with **behavioral** assertion messages (`expected fn to be called 1 times, got 0`), NOT structural errors (`ENOENT`, `ReferenceError`). A test that fails on import proves nothing — it's equivalent to `assert(false)`.
  6. **RED checkpoint verified:** Run all tests against the stub. Every test for new behavior must FAIL with behavioral assertion errors. Target: **0 passing tests**. The test runner's exit code (non-zero) is the proof. Capture the output — this is the deliverable to USER alongside the test files.
  7. **Audit for vacuous passes (backup check).** Step 4's pre-write filter is the primary defense; this step is the last line. Any test that passes against the stub after step 6 is suspect and indicates the filter missed something. Either the test is a legitimate no-op paired with a positive assertion it needs to be merged with, or it's vacuous and should be deleted or rewritten. Explain every passing test or fix it.
  8. **Send tests to Gemini for cross-model review** before sharing with USER. Fix any blockers (coverage gaps, flaky patterns, convention violations).
  9. These become the contract the test coverage agent verifies against post-PR. After implementation, the **GREEN checkpoint** is verified: the same tests now pass, test runner exits zero.
  - This is a hard gate. Code written without test specs tends to have tests bolted on after, if at all. The brief's verification section is the **floor**, not the ceiling — it defines the minimum. The test coverage agent will independently analyze the diff and flag "discovery gaps" (tests the spec didn't predict but the implementation requires). Both layers matter: the spec catches known requirements, the agent catches blind spots.
  - (Evidence: 2026-03-17 home gym recovery toast — implementation completed before test files were written, tests ended up validating what was built rather than what should have been built.)
  - (Evidence: 2026-03-20 #364 — unit tests initially failed with ENOENT (no stub), used wrong test environment (jsdom vs project's sandboxed eval pattern), and 2 tests passed vacuously against stub. All caught by USER during review, none by the writing process.)
  - (Evidence: 2026-04-13 #595 Slice 2 — initial RED had 8 vacuous passes out of 48 tests (5 API-surface shape tests + 3 negative-only pair tests). Root cause was pattern-matching from `filter-summary.test.js` without re-deriving whether the precedent applied. After rewrite: 43/43 failed, 0 passed. Then 2 MORE vacuous passes on newly-added tests in the same session — the rule was stated but not applied at write-time. The pre-write filter in step 4 is the fix; post-hoc audit is too late.)

- [ ] **Cross-model code review:** After plan approval, run `/second-opinion` with the plan + all relevant source files. Use the architecture role prime and `gemini-3.1-pro-preview`. Build a temp file with plan + source (don't use heredocs with LLM output). Gemini should flag issues as `[BLOCKER]`, `[WARNING]`, or `[SUGGESTION]` with specific line numbers. Incorporate findings into the plan before implementation.
  - A prose-only description gets a prose-only answer. The value comes from Gemini seeing the actual code alongside the plan.
  - **Also use for debugging** — when stuck for >2 iterations on infrastructure/config issues, run `/second-opinion` with the failing code + consumer code. Use the debugging role prime. It catches type mismatches and contract violations that runtime debugging misses.
  - Evidence: Gemini caught an event listener leak (handler wired inside a re-rendering function) that Claude missed (2026-03-17, #61). Same session: Gemini identified a `'1'` vs `'true'` localStorage string mismatch after 47 minutes of failed workarounds.

- [ ] **Session capture checkpoint:** Run `/session-capture` after plan approval, before writing any implementation code. This persists plan decisions, cross-model review findings, and the reasoning behind architectural choices while they're fresh. Implementation sessions can then start clean with a resume prompt.

- [ ] **Context freshness check:** If shaping happened in this same session, check: has it been >3 hours or >5 files modified? If yes, capture the session and start implementation fresh — either `/clear` + resume prompt, or launch a subagent with `isolation: "worktree"`. Degraded context causes circular debugging, contradictions, and missed integration bugs. (Evidence: 2026-03-19 #387 — 5-hour session, final hour produced 3 circular attempts at a module loading bug, forgot the test runner name, wrote ESM exports in a non-module script tag.)

- [ ] **Scope file created:** Create `tmp/scope.txt` listing every file the brief says will be modified (one path per line, relative to project root). The `scope-drift-check.sh` hook blocks edits to files not in this list. When implementation requires touching an unplanned file, the hook forces a stop: write a test spec for the new change, add the file to `tmp/scope.txt`, then proceed. This is not optional — the hook enforces it automatically.
  - Test files (`tests/`, `e2e/`, `tmp/`, `.claude/`) are always allowed.
  - The scope file is gitignored and cleaned up after merge.
  - (Evidence: 2026-04-01 #381 — unplanned `auth.js` async change broke 48 E2E tests. The file wasn't in the brief, had no test spec. The hook would have blocked the edit and forced a test-first approach.)

- [ ] **Branch + worktree:** Plan-mode work → create a worktree with a feature branch. Quick fixes → commit to current working branch. If it goes through plan mode, it gets a worktree.
  - `git -C <repo-root> worktree add ../<repo-name>-<short-description> -b feature/<short-description>` (or `fix/` for bug fixes) — e.g. `git -C $HOME/Projects/example-app worktree add ...` in example-app.
  - Session cwd stays on the main checkout; address worktree files by absolute path (`<repo-root>-<short-description>/...`). Do not `cd` into the worktree.
  - **Copy code-bound formative artifacts into the worktree.** If the formative phase produced a code-bound artifact — test plan, walk doc, migration draft — it was born in `<context_repo>/tmp/` (per `conventions/formative-artifact-routing.md`). Copy just those into `<worktree>/tmp/` now so they get committed with the code. Copy ONLY the code-bound set — never the thinking artifacts (pre-mortems, mockups); those stay in the context repo and must never enter the code repo's git history.
  - Post-merge cleanup agent removes the worktree and local branch automatically (see `~/.claude/rules/hooks-and-agents.md` § POST_MERGE_HOOK).

- [ ] **Dependencies identified:** Does this block or get blocked by other issues? Set up links in GitHub. Check if migrations, API changes, or shared components are affected.

- [ ] **One question at a time:** If clarification is needed, ask one focused question and wait for the answer. Don't dump 5 questions at once — it splits attention and leads to partial answers.

## Debugging Protocol: Search First, Read Later

### Before Investigating
- [ ] **Ask first:** "Which page/view? What do you see?" — start at the symptom, not the pipeline. (Evidence: 3 sessions wasted time investigating admin upload/parser when the bug was in rendering)
- [ ] **Check for existing tools:** Is there an admin page, test script, reference doc, or runbook that already covers this? Check `~/Projects/dev-reference/` and `gh issue list` before building from scratch. (Evidence: 5 sessions where existing infrastructure was missed)
- [ ] **Try the obvious fix first:** If something "doesn't work," try install/restart/config change before researching alternatives. (Evidence: Playwright needed `playwright install chromium`, not a rewrite)

### When Investigating
1. **For small files (< 200 lines), just read the whole file** — don't grep-then-hypothesize. Tiny files don't justify the search-first optimization. Reading 41 lines takes 2 seconds; theorizing about what those 41 lines might contain takes 5 minutes. (Evidence: 2026-03-21 — spent 5 minutes hypothesizing about router behavior before reading the 41-line router.js file, which immediately revealed the answer.)
2. **For larger files, start with `Grep`** for the error message, function name, or key pattern
3. **Read only the matched files** — don't speculatively read adjacent files
4. **Understand the interface** — read type definitions or function signatures if needed
5. **Assume the producer is broken** — when infrastructure exists but doesn't work, the generator is usually broken, not the consumer

**Anti-pattern to avoid:**
```
BAD: Read file A → Read file B → Read file C → finally find the bug in file C
GOOD: Grep for the function/error → Read only the file containing the match → fix
```

If you've read 3+ files without finding what you're looking for, stop and search instead.

## Planning Protocol (Shape Up)

- **Frame before shape, shape before code** — this is the sequence. Don't skip steps.
  1. `/frame` — define the problem (no solutions). Output: problem brief.
  2. `/shape-project` — design the solution with a breadboard. Output: shaped brief with affordance tables, wiring, shared state, and mermaid diagram.
  3. **Gemini review** — run `/second-opinion` on the shaped brief before presenting to user. This is mandatory, not optional.
  4. **User sign-off** — user approves the brief.
  5. **Then implement.**

- **A breadboard is not a mockup.** A breadboard is structured text: UI affordance table (ID, place, affordance, type), code affordance table (ID, operation, description), wiring table (from, to, condition), shared state table (state, storage, read by, write by), and a mermaid diagram. See `briefs/schedule-intake-pipeline.md` for the reference format. An HTML file is a mockup — different artifact, different purpose.

- Think in scopes (vertical slices), not tasks
- Track progress as uphill (figuring out) or downhill (executing)
- Multi-level planning: high level (project goals) → task level (specific files/features) → implement only after both levels are approved

## Decision Gates

Before building:
- Is this feature approved?
- Is this urgent, or should it wait?
- If unclear, ask before coding

After features:
- Feature complete → test → strategic review (ship/defer/pivot)

During implementation:
- If USER asks strategic questions mid-build, capture them for end-of-session discussion
- Don't context-switch between building and big-picture thinking
