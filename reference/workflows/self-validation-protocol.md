# Self-Validation Protocol

**Hard gate:** Do not report work as complete until every applicable step below is done.

## Instrument First, Always

**When any test fails, bug is reported, or behavior is unexpected, the FIRST action is adding a diagnostic.** Never read source code, form theories, spawn Explore agents, or try speculative fixes before seeing the actual error output. This is a hard gate — not a suggestion.

The sequence is:
1. **Add instrumentation** — `console.log`, `page.evaluate(() => console.log(...))`, `curl`, or a diagnostic dump. One targeted diagnostic at the failure point.
2. **Read the output** — the diagnostic tells you what's wrong. Most root causes are immediately visible.
3. **Fix based on evidence** — now you know the actual state, fix it.

**What NOT to do first:**
- Read source code to "understand the flow" (you'll form a theory and test it — that's guessing)
- Spawn Explore agents to investigate (they form theories too)
- Try a speculative fix ("maybe it's X") without confirming X is the problem
- Blame infrastructure (Docker, vercel dev, race conditions) without isolating individual failures

**For multiple test failures:** Run the first 3 failing tests individually before theorizing about infrastructure. Individual failures reveal specific root causes; batch failures hide them behind infrastructure noise.

**For UI / layout bugs:** Layout and visual bugs count as "unexpected behavior" for Rule #1. Before patching CSS, run a diagnostic in the browser: `page.evaluate(() => el.getBoundingClientRect())`, inspect `getComputedStyle(el)`, or log the actual parent width that's driving the child. Three surface-patch CSS changes in a row without instrumenting the real computed values is a rule violation — the second failed patch is the escalation trigger, not the third. (Evidence: 2026-04-22 #685 Slice 3 — mobile layout rendered 2× too wide. Three surface CSS patches targeting adjacent symptoms before instrumenting actual computed widths. One `getBoundingClientRect` call would have named the real parent.)

(Evidence: 6+ sessions in April 2026 window. 04-07-15-30: 15 min reading source before instrumenting, 3 lines of console.log immediately revealed root cause. 04-07-16-27: 3 Docker runs guessing at env vars, one console.log showed the problem. 04-07-22-04: 4 Explore agents rejected by USER — "no guessing, use /debug." 04-08-20-14: 2+ hours blaming vercel dev before checking individual test errors. Every session that instrumented early had 1-2 fix iterations; sessions that theorized first had 4-8.)

**Measurement (next maintenance check):** Count sessions where diagnostics were added BEFORE the second theory. Target: 100%. Current baseline: ~30%.

## Before Every Edit

### Check git history before rewriting
Before rewriting or making large changes to any file:
1. `git log -p --follow -1 <filename>` — see what was recently added
2. Look for features, imports, or logic that could be accidentally removed
3. If the file was modified in the last 1-2 sessions, be extra careful not to clobber recent work

**Why:** This is the exact failure mode behind "edits didn't persist" — rewriting content without checking what had been recently added by another session or branch merge.

## Before Writing New Code

### Product intent check (what should this do, not what does this do)
Before writing or modifying tests, accepting merged behavior, or shipping a fix for user-facing code, ask: **what is the intended user experience?** — not "what does the code currently do?"

The trap: reading existing code, inferring intent from its behavior, and writing tests / accepting that behavior as correct. Merged code is not automatically right. Tests written this way *document* current behavior instead of *enforcing* desired behavior — and silently bake in product bugs.

Specifically:
1. **When writing tests for existing code**, also ask: "Does this function actually do what a user would want?" If unclear, ask USER before writing the assertions. Don't assume the test should match the function's current output.
2. **When a user reports unexpected behavior**, treat the report as a *spec*, not a *symptom to explain*. The question is "what should happen?" not "why is the code doing this?" Get the desired behavior first, then implement it.
3. **When test names describe a property** (e.g., "case-insensitive", "preserves casing"), check whether the test name describes the *detection* logic or the *output*. Mismatches between test name and assertion are red flags — they often mean the assertion was written from the implementation, not the spec.
4. **Watch the language gap**: "the function returns X" is implementation language. "the user sees Y" is product language. Use the product language to validate the implementation, not the other way around.

(Evidence: Recurring `redirected:product` pattern across 3+ sessions in 2026-04-08/09 window. Specific instances: `formatHall` test 3 documented "preserve original casing" when the user wanted "always normalize to Hall"; analyzing layered toasts as a regression instead of asking whether they were even the same toast; writing tests for a handler's current 400-response code path instead of asking if that's the right contract.)

**Measurement (next maintenance check):** Count `redirected:product` reflections per session. Target: 0. Current baseline: 1-2 per session in the 04-08/09 window.

### Cardinality: future state is the contract
When reasoning about whether a change is safe for multi-row scenarios, **the relevant question is "what will the row distribution be AFTER this feature is in production?" — NOT "what is the distribution today?"**

Zero rows today is not evidence of safety for a class of operation that will produce multiple rows. Build and test for the future state.

Common failure form: "0 users currently have >1 row of X, so this is safe." This argument fails the moment the first user triggers the new multi-row path — and no unit test with a single-row seed catches it.

**Required check:** Before shipping any code that touches a table where one-per-user will become many-per-user, write at least one test with a 2+ row fixture and confirm the behavior is correct under that condition.

(Evidence: 2026-05-28 PR #828 — subscription-renewals bug: "0 users have >1 subscription row today" used as a safety argument; `lookupUserByCustomer` + affiliate promo lookup both used `.maybeSingle()` which errors on 2+ rows — caught by Gemini cross-check before migration applied. 2026-06-01 slice-1a review — same "0 rows today" reasoning class used to argue no cardinality regression.)

### Match existing patterns (convention check)
Before introducing a new route, CSS class, file, or API endpoint:
1. **Check the naming convention** — look at 3+ existing examples of the same type
   - Routes: Are they flat (`my-teams`) or nested (`notifications/read`)? Match the pattern.
   - CSS classes: What's the naming scheme? BEM? Flat? Match it.
   - Files: What's the directory structure? Handler per file? Catch-all router?
2. **Check the hosting/deployment context** — Vercel, Netlify, etc. have routing quirks
   - Vercel + `cleanUrls` can interfere with nested catch-all paths
   - Serverless function cold starts affect testing (don't assume instant responses)
3. **Check parent container constraints** — before adding visual CSS (borders, shadows, outlines):
   - Does the parent have `overflow: hidden`? Borders at container edges will be clipped.
   - Does the parent have `position: relative`? Absolute children will be scoped to it.
   - Use `Grep` for the parent class and read its styles before choosing an approach.
   - **Safe alternatives when overflow clips:** Use `background: linear-gradient(...)` or `box-shadow: inset ...` instead of `border-left/right`.

### Sync-to-async is a breaking change
Before adding `await` to a previously-synchronous function:
1. **List everything that happens after the new `await`** — all of it now runs later. Anything that callers or DOM events relied on completing synchronously will race.
2. **Grep for all call sites** — callers that fire-and-forget (`initAuth()` from `DOMContentLoaded`) won't await the result. Code after the call continues immediately, but the function's post-`await` work hasn't run yet.
3. **Split sync from async** — extract the parts that MUST be synchronous (event listener wiring, DOM setup, guard initialization) into a separate synchronous function. Call it before the async function.
4. **Add null guards** — if the async function initializes a client/resource that handlers depend on, every handler must check for null and show a user-friendly message, not crash silently.
5. **Write a test** — "handler works correctly when called before async init completes." This test defines the contract and prevents the regression from being introduced.

(Evidence: 2026-04-01 #381 — added `await fetch('/api/config')` to `initAuth()` in auth.js. Event listener wiring moved behind the await. Form submit handlers weren't attached for 1-3 seconds after page load. 48 E2E tests broke. Fix: split into `wireEventListeners()` (sync) + `initAuth()` (async). Root cause: no test spec written before the change, no scope enforcement.)

### New browser-loaded JS files
Before reporting a new `.js` file as working:
1. **Check the script tag type matches the file's syntax** — `<script defer>` cannot contain `export` or `import` statements. `<script type="module">` can, but executes after all `defer` scripts. If other `defer` scripts depend on this file's `window.*` globals, it must be `defer`, not `module`.
2. **Check execution order** — `defer` scripts execute in document order. If `app.js` depends on `window.CompetitionCache`, the script that sets it must appear before `app.js` in the HTML.
3. **Verify in the browser** — Open the page, check the console for syntax errors, and verify `window.YourGlobal` is defined. A file that passes unit tests can still fail in the browser if the module system doesn't match.

(Evidence: 2026-03-19 #387 — `competition-cache.js` had ESM `export` statement but loaded via `<script defer>`. Browser threw syntax error, `window.CompetitionCache` never set, all downstream logic silently failed. 19 unit tests passed because vitest imports ESM fine. Caught only by manual testing.)

### CSS rendering preflight
Before pushing any CSS change involving scroll-snap, overflow, safe areas, or positioning:
1. **Write out the rendering math** — viewport height, safe area insets, nav height, scroll-padding offset, section padding. Verify they sum to the expected content position. Don't push until the math checks out.
2. **Grep for all selectors targeting the same element** — shorthand properties (`margin`, `padding`) in higher-specificity rules reset individual sides. Check for `.foo.bar` compound selectors that might override your `.foo` rule.
3. **If the fix has required >2 iterations, stop** — change the HTML structure instead. Inline wrapping of mixed content (text + pills + separators) is inherently fragile. Split into separate elements.
4. **Test locally first** — run `vercel dev --listen 8765`, verify visually, get approval, then push once. Never use main as a CSS scratch pad.

(Evidence: 9 CSS iteration redirections across 4 sessions — specificity overrides, overflow clipping, scroll-padding double-counting, safe area env() failures. Each session burned 3-7 fix iterations.)

### localStorage and configuration value contracts
Before debugging why a localStorage-based flag isn't working:
1. **Read the consumer code first** — grep for the key, find the comparison. Is it `=== 'true'`, `=== '1'`, or `=== true`? The consumer defines the contract.
2. **Match the value exactly** — If the consumer checks `=== 'true'`, the setter must write the string `'true'`, not `'1'` or a boolean.
3. **Test the check in isolation** — Before building workarounds (DOM removal, route interception, MutationObservers), verify the basic contract: `localStorage.setItem('key', 'true'); console.log(localStorage.getItem('key') === 'true')`.

(Evidence: 2026-03-17 home gym recovery — 47 minutes debugging overlay suppression. Built 7 workarounds (addInitScript, CSS injection, MutationObserver, route interception, DOM removal). Root cause: auth setup wrote `'1'` but `theme.js` checked `=== 'true'`. Gemini found it in seconds by reading the comparison.)

**Measurement (next maintenance check):** Count fix iterations on config/flag debugging. Target: 0 sessions with >2 iterations before reading consumer code. Current baseline: 1 session with 7 iterations.

### When facing multiple test failures: triage before fixing
If >2 tests fail simultaneously:
1. **Cluster by symptom** — Group failures by what's wrong (missing element, wrong state, timing), not by test name. Read all error messages and screenshots first.
2. **Fix the simplest cluster first** — A single-line bug (like async-without-await) often clears 3+ tests at once.
3. **Escalate on remaining clusters** — Once easy wins are fixed, run `/second-opinion` on the remaining failures before attempting complex debugging. Do not serial-theorize through multiple clusters solo.

(Evidence: 2026-03-19 #387 — 7 failing e2e tests had 5 root causes across 4 clusters. Fixing the simplest (async-without-await) cleared 3 tests. Solo theorizing on the banner cluster burned 15 minutes; Gemini identified the root cause (`clearStaleAppCache` interference) in one pass.)

### When stuck debugging: escalate to cross-model review
If a bug has resisted >2 fix attempts:
1. **Stop adding workarounds** — each one adds complexity without addressing the root cause.
2. **Build a context file** with: the code that should work, the code that checks the value, what you've tried, and the error output.
3. **Get a second opinion** — run `/second-opinion` with the context file. Use the debugging role prime and `gemini-3.1-pro-preview` for root cause analysis. A fresh model reading the actual code catches type mismatches, wrong assumptions, and contract violations that you've been staring past.

**Two-Cycle Escalation Rule:** If a hypothesis fails, that's one cycle. After **2 failed cycles on the same failure cluster**, escalate immediately. Do not attempt a third solo theory. This applies to **all debugging** — application code, infrastructure, env vars, Docker, CI, config, auth — not just bug fixes. If 2 approaches to a parser/extraction/calibration problem fail, stop and reassess the fundamental approach before trying a third. For infrastructure/config issues specifically, "escalate" means **instrument** (console.log, echo, env debug output) — don't guess at a 3rd fix.

(Evidence: 2026-04-07 — 3 Docker test runs (~10 min) guessing at env var routing. One `console.log` of the Supabase URL would have shown the problem immediately.)

**Contested visual/design CHOICE: render the alternatives, don't describe them.** The Two-Cycle Escalation Rule's "instrument harder / second-opinion" branch is for *broken behavior*. For a contested *design choice* — which layout, which color treatment, which differentiation, which spacing, "which of these" — the escalation is different: **render the alternatives side-by-side and let USER look.** Prose descriptions of visual options reliably fail to resolve the disagreement; the deadlock breaks the moment the options are rendered. Trigger on your **2nd prose description of a visual**: stop and produce a headless-chromium screenshot, a standalone HTML with both options, or an ASCII mock for layout — before writing another word of description. This is the visual-problem form of "instrument first." (Evidence: 2026-07-16 — dark-card "hole punch" argued in color-values when it was a structural problem, resolved only by rendering options side by side; same session hours later, row layouts described in prose for three exchanges until USER asked for an ASCII preview — the lesson "did not transfer." 2026-07-10 card differentiation and 2026-07-16 brand contrast both reasoned in numbers instead of shown. See memory `feedback_render_alternatives_for_design`.)

**For parser/extraction work specifically:** See `~/Projects/dev-reference/conventions/parser-session-scoping.md` — one goal per session, concrete pass/fail test, 2-failure stop rule, no "CLEAN" declarations without full test suite, data-driven fixes only.

(Evidence: 2026-03-17 — 7 workaround attempts in 47 minutes. Gemini identified `'1'` vs `'true'` mismatch in one pass. 2026-03-19 #387 — 3 solo cycles on banner issue before escalation; Gemini found `clearStaleAppCache` interference immediately.)

**Measurement (next maintenance check):** Count sessions where >2 fix iterations occurred before escalating. Target: escalate by iteration 2 every time. Current baseline: 3 cycles before escalation (improved from 7).

### Verify external claims before acting
Before acting on any data from a tool, model, or agent — **grep the source to confirm**. This is a hard gate.

| Claim type | Verify with |
|------------|-------------|
| Element selector / DOM ID | `grep` the project's markup source (e.g. `web/*.html` in example-app's vanilla stack) — component/JS references can be stale |
| File existence or structure | `ls` or `Glob` — don't trust agent directory listings |
| Data counts or DB state | `SELECT count(*) FROM ...` — agent-reported counts are often wrong |
| Code pattern or feature presence | `Grep` the source — tool output (WebFetch, model analysis) hallucinates |
| Config value or env var name | `Grep` the consumer code — match what it actually checks |
| Issue status | `gh issue view #NN` — cached state drifts |
| API response shape | **Inspect one real response** (curl, console.log, REPL) — don't trust your mental model |
| Internal artifact (code comment, test label, session note, dev-reference file, next-steps entry, LB ledger entry) | **Verify the real-world claim independently** — internal docs are external claims. They were true when written; code, files, and state have moved since. Before designing on top of any claim from an internal doc (session note says file X exists; ledger says RPC Y is locked; next-steps says "Z is done"), grep the current codebase or read the current file to confirm. A `MANUAL_ONLY` label doesn't mean the org has no scrapable site; a session note about `.env.test` doesn't mean the file is still missing; a brief citing `scripts/check-external-integrations.sh` doesn't mean the file exists. |
| Session resume prompt | **Verify key assertions before acting** — resume prompts describe state at session end, not current state. Check: are files in the claimed state? Are tests written/passing? Is the branch current? Treat resume prompts as external claims, not verified facts. |

**The rule:** If you didn't grep it, you don't know it. Tool/model/agent output is a hypothesis, not a fact. One `Grep` call takes seconds; acting on a wrong assumption burns minutes to hours.

**Verify before writing a claim into a deliverable — not "verify-later":** When a brief, plan, PR description, or any deliverable would assert a technical fact (precedence rules, API behavior, config effects, "X overrides Y"), verify it *before* writing it down. Do not write it as fact and flag "verify later" — either verify now, or label it honestly as unverified. A claim that carries a "verified" label but came from a misread is worse than no claim: the reader trusts it and builds on it. If the verification inverts your assumption (it often does), the deliverable's design may need to change — which is exactly why it has to happen before, not after, the brief is written.

**Never conclude from unreliable terminal output — funnel to a labeled file and read it:** When tool output can interleave or garble — parallel Bash calls, hot-reload servers, background processes, long boots — do NOT draw a conclusion from the inline output you can't cleanly attribute to a specific command. Write the result to ONE labeled file (`echo "== test N ==" >> result.txt; <cmd> >> result.txt`) and `Read` that file literally. After the FIRST misread, change the *method* — re-running the same flaky parallel approach is the verification-mechanics version of serial-theorizing, and the Two-Cycle Escalation Rule applies. (Evidence: 2026-05-31 #832 — published a `vercel dev` env-precedence conclusion to a brief and the issue, in the WRONG direction, twice, from garbled parallel-Bash output. The truth — local `.env` > process env/`op run` > cloud Development — only surfaced once results were funneled to a single labeled file and read directly. The wrong claim would have shipped an `op run -- vercel dev` wrapper that silently used stale `.env` values. USER: "you should be verifying all claims before writing the brief anyway.")

**Grep before hardcoding identifiers:** Any app ID, App Store URL, API route, feature flag name, CSS token, or environment-specific constant that already exists in the codebase must be grepped before being written fresh. "Half-remembered from memory" is not a verified source. If the codebase has 7 copies of the right value and you guess an 8th, you are creating divergence. (Evidence: 2026-04-14 #598 — hardcoded App Store ID `id6741016389` from memory; the correct value `id6759681982` sat in 7 other places. `grep -rn "apps.apple.com" web/` would have found it in one call.)

**Pattern-match audit before reusing a precedent:** When reaching for an existing test, module, or helper as a template, state the precedent's key assumption in one sentence and confirm it applies to the new case. "The precedent assumes X — does X hold here?" If yes, use it. If no, fresh-derive. The cost is 10 seconds of thinking; the cost of a template that doesn't apply is rewriting the work after review. (Evidence: 2026-04-13 #595 Stage 4 — copied the "vacuous-pass control" pattern from `filter-summary.test.js` without checking whether the precedent applied. Filter-summary tests dereference return values so they fail against an empty stub; the copied tests used `typeof fn === 'function'` checks that pass against `function fn() {}` unconditionally. 8 vacuous passes landed in RED. 2026-04-16 #621 — accepted a reviewer's `signup_source`/`campaign` concern as a blocker without greping the codebase to confirm the claim applied.)

**Subagent output read-back:** After spawning a subagent that writes or modifies files, `ls` the claimed paths and `cat` each file before reporting the subagent's work as done. The subagent's return message is a claim — the files on disk are the verification. Trusting the claim without reading the files means the "work" can be invisible to the rest of the session. (Evidence: 2026-04-22 #685 Slice 3 — delegated implementation to 3 parallel Sonnet subagents; reported subagent work as complete without listing written files. USER: "the subagent work was invisible." Several files the subagent claimed to write did not exist on disk.)

**External help-agent claims need cross-check:** When an external help agent (Customer.io, Stripe, Vercel docs agent, any third-party assistant, **any background review or analyst agent**) returns an identifier, column name, field name, config value, **severity assessment, or blocker classification**, cross-check it against the existing working config or the actual evidence in the repo *before* acting on it. Help agents can be wrong — and iterating on a wrong claim wastes multiple tool calls. One read of the original working file (or one independent reading of the underlying evidence for severity claims) catches it. (Evidence: 2026-04-23 #699 — CIO help agent returned `id` as the identifier column, then `userId` after pushback. Both were wrong; the original working `customerio.users_vw` used `user_id`. Four migration iterations on one column before checking what the old working config actually had. 2026-05-12 #778 — background review agent flagged a real BLOCKER as "minor quirk"; USER pushed back. Severity classification accepted without checking the underlying evidence.)

**"I thought you fixed this" → git log first:** When the user signals surprise that a prior-session fix didn't stick ("I thought you fixed this already", "didn't we ship this?"), the first action is `git log --oneline -10 <file>` and `gh pr list --state merged --search <keyword>`. Re-diagnosing from scratch is option three, not option one. The user's signal means the fix landed in *some* form; find that form first, then diagnose why the effect isn't present. (Evidence: 2026-04-22 #673 — "I thought you fixed this" on promo attribution; re-diagnosed from scratch instead of checking git log and open PRs. Cost ~3 extra tool calls to re-derive what `git log --oneline -10` would have shown.)

**"Pre-existing" / "flaky" / "not my change" is a CAUSAL claim — establish the real baseline before making it.** Before dismissing a failing test or red CI check as pre-existing, flaky, or unrelated to the current work, confirm the failure reproduces on the **true baseline: the merge-base with main** (`git merge-base origin/main HEAD`), not on the first commit of the current branch. **"It fails on every commit of this PR/branch" does NOT mean pre-existing when every one of those commits *is* the work in question** — the first commit of a feature branch is still the feature. The branch point is the baseline; a commit on the branch is not. Cheapest verifications, in order: (1) check whether the same check/test was green on a recent `main` run or on the merge-base commit (`gh api repos/<owner>/<repo>/commits/<merge-base-sha>/check-runs`); (2) if CI only runs on PRs/previews, find the last green run of that exact check before the branch existed; (3) if neither is available, reproduce against the pre-change code (`git stash` / check out the merge-base) before attributing the failure away. A "flaky" label is earned by a rerun passing on the *same* commit — not assumed. Misattributing a real regression as "flaky/pre-existing" ships the regression: this is a hard gate, not a judgment call. When the user pushes back on a too-quick dismissal, treat it as a near-miss and re-baseline immediately. (Evidence: 2026-06-21 PR #923 — dismissed a failing S2a claim journey as "pre-existing/flaky" because it failed on all 4 PR commits. But all 4 commits *were* the S3 work; the first (`0dba46d`) was the S3a.0 spine itself, so I never checked the pre-S3 baseline. It was a real regression: the S3a.0 `ProgramSearch` extraction hardcoded `aria-label="Search"`, dropping the claim flow's "Search for your program" accessible name that the journey's `getByRole('searchbox', { name })` matches on. USER: "not acceptable — if the journey suite is failing now when it was passing before we did S3 work, there's a chance you broke something." Unit suites missed it because they matched on role only, not name — see the accessible-name guard note in `conventions/e2e-test-conventions.md`.)

**"X doesn't exist / isn't built" is an absence-claim — confirm the checkout is current FIRST.** Before asserting that a file, route, surface, RPC, or feature does not exist in the codebase — and *especially* before building a plan, brief, or reshape proposal on top of that absence — run `git -C <repo> fetch origin` and confirm local `main` (or the branch you searched) is not behind `origin/main`. A stale checkout makes every negative search a false negative: `grep` finds nothing because the code was merged after your checkout, not because it isn't there. This is the design-time face of the session-start stale-context gate; it also governs **reuse-audit dispatches** — an Explore/reuse agent searching a stale local tree will report "Build-new" for something that already exists on `origin/main`. When in doubt, search against `origin/main` (`git grep <pat> origin/main`), not the working tree. (Evidence: 2026-07-06 — asserted "/my-results and /account don't exist in the rebuild" and built a 4-fork reshape proposal on it; both exist on `origin/main` — the local checkout was 9 commits stale. 2026-06-29 — reuse-audit Explore agent returned "none found, Build-new" for an S4.0 results surface because it searched a tree 4 commits behind origin.)

**Rule #3 applies to your OWN claims most of all — absence-claims, infra/hook forensics, and inferences about human-observed state.** The rule reads as though the unreliable claims come from *others* (agents, models, tools, docs); the highest-risk case is first-person. Before asserting any of these, check the primary source THIS turn (grep / read / `gh` / read the actual transcript or log): an absence-claim ("X doesn't exist", "that isn't a convention", "the hook didn't fire"), a scheduling claim ("queued behind Y"), a technical fact you're writing into a resume prompt / session summary / code comment ("verified unused"), or a claim about what the human saw or did. Two specific traps: (1) **reasoning backward from an absent artifact** — "no lock file on disk, so the hook didn't fire" is a guess; read the log/transcript to see whether it actually fired. (2) **a tool call returning success is never evidence about what the human observed or had to do** — that state is structurally invisible to you; you cannot report it without asking or watching. Reflex: when you catch yourself about to write **"doesn't exist / never / isn't a / didn't fire / already verified"** about something you have not checked this turn, that phrase itself is the trigger to check. (Evidence: 2026-07-16 — told USER the merge-approval token "isn't a convention"; it has been one since 2026-04-29, asserted from absence-of-memory. 2026-07-17 — "POST_MERGE_HOOK didn't fire" reasoned from an absent lock file; it had fired ["first be sure the hook didn't fire and figure out why"]. 2026-07-13 — "#1078 is queued behind S4" asserted twice without checking, gate already closed ["you told me this incorrectly before once already"]. 2026-07-17 — a code comment claimed a constant was "verified unused across the repo" without running the grep. 2026-07-15 — "auto-mode approved it without interrupting you" inferred from a tool-call success alone.)

**Prior-art-first for matcher/parser/admin bugs:** Before deep-diagnosing any bug in `matching.js`, `publish-core.js`, `pending-reviews.js`, `schedule-core.js`, `division-parser.js`, or any routing/matching component — run `gh issue list --state open` and `gh pr list --state merged --search <keyword>` first. These components have prior fix history; treating a recurrence as a green-field investigation wastes the first 10–20 minutes of every incident session. The scan takes 30 seconds. (Evidence: 2026-04-30 #752 — USER: "we figured ALL OF THIS OUT THE OTHER DAY." Issue #725 was already open and described the same multi-location collapse class. Reading it first would have named the alias short-circuit as the gap immediately, vs. narrating a full root-cause trace from scratch.)

**API-specific rule:** Before writing filter, transform, or assertion code against any external API (Supabase, Capacitor, Vercel, etc.), **inspect one real response first**. `console.log` the response, `curl` the endpoint, or run one call in a REPL. Never write `response.identities.filter(...)` without first confirming the response has an `identities` field. This applies to your own assumptions about API behavior, not just external claims.

**Third-party library mocks must match the real contract, not your memory of it:** Before writing a mock for any third-party function (Capacitor plugins, npm packages, native bridges) in a test file, grep the actual source in `node_modules/` for the function's resolve/return shape. Read the TypeScript defs (`*.d.ts`), the native source (`*.swift`/`*.kt`), or the JS implementation — match the mock byte-for-byte to what the function actually returns. Mock-against-fiction is the most expensive form of unverified-claim failure: mock matches impl (because the same wrong shape was confabulated for both halves), CI passes, bug ships to users. Subagents writing tests are especially prone to this — call it out in their prompts. (Evidence: 2026-04-14 PR #598 — Live Activities test file mocked `listActivities()` as `{ activities: [...] }` while the real `capacitor-live-activity` plugin returns `{ items: [...] }` per `node_modules/capacitor-live-activity/dist/esm/definitions.d.ts:290` and `LiveActivityPlugin.swift:163`. Implementation read the same fictional shape, so syncActiveState silently no-op'd, wiping the in-memory dedup map every visibilitychange. Result: 2 weeks of duplicate Live Activities on the lock screen for any followed team in the 30-min window — discovered by USER at a competition. Fixed in #716/PR #717.)

(Evidence: 2026-03-30 — Supabase `listUsers` doesn't populate `identities` array, `updateUserById` doesn't create email identity. 2026-03-26 — ApiClient `_intercept` fires signout on 401. 2026-03-23 — Capacitor `registerPlugin` doesn't exist, `packageClassList` overwritten by `cap sync`. 2026-03-24 — Stitch MCP requires `STITCH_ACCESS_TOKEN` not `STITCH_API_KEY`. 15 assumption events across 10 sessions in one maintenance window.)

(Evidence: 4+ sessions in 03-14 to 03-17 window — 5 wrong e2e selectors from JS-not-HTML, OG tags claimed missing when recently shipped, 12/21 hallucinated audit findings on large bundles, 47-minute overlay debugging from not reading `isAnnounced()`. Avg cost: 20+ minutes per incident.)

**Measurement (next maintenance check):** Count `assumption` reflections tagged "trusted external data." Target: 0 instances of acting on unverified tool/model/agent output. Current baseline: 4+ per maintenance window.

### Validate the full request path
For API changes, mentally walk through: **browser → edge/CDN → router → handler → DB → response**
- Does the route actually get matched by the router? (Check the router file, not just the handler)
- Does the DB table/column exist? (Check the migration was applied)
- Does the response shape match what the frontend expects?

### Display-layer contract check (data shape ↔ formatter)
When writing data that will pass through a formatter or display layer, grep the formatter *first* and derive the stored data shape from what the formatter expects. Do not pick a data shape based on how it "should" look in the DB and expect the formatter to adapt.

Example: if `formatHall("West Hall")` exists and returns `"West"` (stripping the "Hall" suffix), then the DB should store `"West Hall"`, not `"West"`. Writing `"West"` to bypass the formatter breaks every other call site that relies on the stripping behavior, and creates divergence between records.

Apply this to any display helper: `formatX`, `prettyX`, `displayX`, `normalizeX`, any `<formatter>.js` module. Read it once; then choose the data shape to feed it.

(Evidence: 2026-04-23 youth-summit parser — proposed storing `"West"` (post-strip value) in the hall column. `formatHall` in `tools/parsers/field_normalization.py` expects the pre-strip form. One grep of `formatHall` would have named the contract. Same failure shape in 2026-04-21 Worlds PO — stripped city/state before checking whether the display layer re-added them.)

## After Every Edit

### Single-file edit
1. `Read` the file back
2. Confirm the edit appears at the expected line
3. Confirm surrounding context wasn't corrupted

### Multi-file changes
1. `Read` each modified file back
2. `Grep` for the expected pattern across all affected files
3. Verify consistency (e.g., renamed function is updated in all call sites)
4. **When modifying a parameter's default value or renaming a function**, grep for ALL usages and verify each call site — don't assume the "other" usage is unrelated. (Evidence: favorites filter #107 missed `getCompetitorCount`, show-past toggle missed second `showPastEvents: false`)

### Deleting code
1. `Grep` for the old pattern — confirm zero matches
2. Check imports/references that depended on the deleted code

### API or logic changes
1. State what changed and why
2. **Run the smoke test yourself before asking USER** — for any API endpoint change, use the Vercel preview URL + e2e credentials to verify the live response rather than handing USER a curl command. The pattern:
   a. `gh pr view <N> --json statusCheckRollup` → extract the Vercel preview URL from PR comments (`gh api repos/<owner>/<repo>/issues/<N>/comments --jq '.[].body' | grep -o 'https://<project-preview-host>[^)]*'`, where `<owner>/<repo>` resolves via `resolve_product_field issue_tracker` / `git remote get-url origin`, and `<project-preview-host>` is the project's own preview host, e.g. example-app's is `example-app.vercel.app`)
   b. For a Supabase-backed repo like example-app, sign in via Supabase auth using creds from `<repo-root>/.env.test` — load with `source .env.test` (never inline secrets), POST to `$TEST_SUPABASE_URL/auth/v1/token?grant_type=password`
   c. Hit the endpoint with the returned `access_token` and inspect the response JSON
   d. Only ask USER to manually test if the verification requires a real paid/production user that doesn't exist in e2e seed data, or requires iOS device interaction.
   (Evidence: 2026-05-11 #772 — asked USER to run a curl command for the smoke test; he pointed out the preview URL + e2e environment made this automatable. Ran it programmatically, confirmed `teamLimit: null` live without USER touching a terminal.)
3. If testable via existing test suite, run the relevant tests
4. **Verify output format matches consumer** — for any function that produces output consumed by another system (API response → frontend, CLI output → admin portal, parser → JSON file), verify the shape matches what the consumer expects. (Evidence: parser `-o` wrote `{entries: [...]}` but admin portal expected a bare array)

### E2E test changes
When writing or modifying Playwright e2e tests, validate against `~/Projects/dev-reference/conventions/e2e-test-conventions.md`:
1. **Verify every selector against the project's markup source** — `grep` it for each element ID used in the test (e.g. `web/*.html` in example-app's vanilla stack). Don't trust JS/component code that references IDs.
2. **Check form validation layer** — if a form input has `required` or `type="email"`, test with `checkValidity()`, not JS error elements.
3. **Auth pattern** — if the test needs a fully functional app (API calls, event handlers), sign in via UI, not storageState. StorageState JWTs expire between fixture and test.
(Evidence: all 3 issues hit in 2026-03-16 auth e2e session — wrong IDs from JS recon, browser validation blocking JS, stale storageState breaking sign-out tests)

### Creating new files
1. `Read` the file back to confirm it was written correctly
2. Verify it's in the right directory (`ls` parent)
3. If it needs to be imported/referenced elsewhere, confirm those references exist

## Before Reporting "Done"

### E2e tests must be green (not "written") — and written before implementation (not after)
E2e tests are part of the Stage 4 spec, written before implementation alongside unit tests. They must then be **executed and passing** before reporting done. "Tests written" is not "tests passing," and "tests written after implementation" is not testing the spec — it's testing what you built. Run the full e2e suite, fix all failures, run again to confirm stability. If an infrastructure blocker prevents execution (missing env vars, no dev server), fix the blocker first — it is part of the implementation, not a separate task.

(Evidence: 2026-04-02 #518 — reported implementation "complete" with 12 unexecuted e2e tests. Next session spent 90+ minutes debugging failures that were all predictable from the test user's known state.)

### Script/tool runnability gate
If the work is a script or CLI tool (anything in `tools/`, `scripts/`, or any file meant to be executed directly rather than imported), **run it with a safe flag before reporting done.** Unit tests passing is not sufficient — unit tests mock the dependencies that have the bug.

The check:
1. Run the script: `node tools/script.mjs --dry-run` (or equivalent safe flag)
2. Confirm output makes sense — not just "no crash"
3. If there's no dry-run flag, verify the script can at least parse args and load env without error

**The test:** "I ran this script and it produced expected output." If you can't say that sentence truthfully, the work is not done.

(Evidence: 2026-05-13 — Affiliate Commission Slice 1 required 4 PRs (#798, #799, #800, #802) because PR #798 shipped a function with no CLI entrypoint, #799 shipped the entrypoint with broken env handling, #800 fixed the env bug. Running `node tools/backfill-affiliate-commissions.mjs --dry-run` before #798 would have prevented all three follow-on PRs. USER: "the 4 PR thing was really really really bad. like, first day working with claude code bad.")

### Browser verification gate (interactive elements)
If the work adds or modifies any interactive element (button, link, form, click handler), **open the dev server in a browser and click it** before reporting done. Rendering a button is not wiring it. The verification sequence:

1. **Start `vercel dev`** if not already running
2. **Navigate to the page** with the new/modified interactive element
3. **Click/tap the element** and verify the expected outcome occurs (redirect, modal, state change, API call)
4. **Check the browser console** for errors — a silent JS error means the handler crashed without user feedback
5. **Test on the platform that matters** — if the element behaves differently on iOS (e.g., `Browser.open()` vs `window.open()`), verify both paths

**The test:** "I clicked the button and [expected thing] happened." If you can't say that sentence truthfully, the work is not done.

This is NOT replaced by E2E tests. E2E tests automate this check for regression prevention, but the manual click is the primary verification during development. E2E tests can have wrong selectors, stale state, or mock-masked failures. The browser doesn't lie.

(Evidence: 2026-04-14 #598 — Notify Me buttons rendered but click handler wasn't wired; caught by USER, not by tests. 2026-04-16 #621 — flagged as recurring pattern during test review: "the last two things we've delivered, when you've supposedly wired buttons up, it hasn't actually worked.")

### Rendered-surface gate (LOOK at it — styling, not just wiring)
Green tests + green CI say the logic is right; they do **not** say a human can see or use the surface. Before calling ANY UI slice done, actually **look at the rendered output** — a preview screenshot, the deployed preview, or a browser render. A unit/integration test on a hook's return value or a component's props does not exercise the render path a real composition takes, and it never sees a stylesheet.

Two failure shapes this catches:
1. **Unstyled / broken layout shipped on green tests.** (2026-06-24 — the S3b.2 followed-schedule card shipped with zero styling and was declared done on green tests/CI; nobody had looked at the screen.)
2. **Renderer-specific bugs invisible to jsdom/chromium.** WebKit's focus/tap semantics differ; a "tap does nothing" bug shipped twice because coverage was chromium-only. (2026-07-05 — FS-1; led to #1008 + a `webkit-journey` Playwright project.) For a Capacitor/iOS surface, the render check must include a WebKit/device pass, not just chromium.

**The test:** "I looked at the rendered surface and it shows [expected] and is styled correctly." If the only evidence is a passing test, the render gate has not been satisfied.

### Three-Scenario Check (UI features)
If the work includes any user-facing UI, walk through these three scenarios before declaring done:
1. **Happy path** — the primary use case works as designed
2. **"Everything is bad" path** — junk data, empty states, errors, zero results. What does the user see?
3. **"I made a mistake" path** — undo, dismiss, redo, back button. Can the user recover?

If any scenario reveals a missing feature (no delete button, no undo, no loading indicator, no empty state), add it before reporting done. (Evidence: 6 redirections in gym cleanup session, 4 in admin dashboard — all missing unhappy paths discovered by USER during testing)

### Pattern fix: grep the entire diff for siblings
When a bug is fixed by identifying a code pattern (e.g., "missing `.select()` after `.insert()`", "wrong error status code", "unguarded null"), **grep the entire branch diff for the same pattern before closing:**

```
git diff main...HEAD | grep -n "<pattern>"
```

Sibling instances of the same bug are highly probable — the same author wrote them under the same mental model. Fixing one instance without scanning for siblings ships a partial fix.

**The check:** After identifying the root pattern of any bug fix, grep `git diff main...HEAD` for it. If there are multiple matches, fix all of them in the same PR.

(Evidence: 2026-06-01 — fixed `expenses` POST missing `.select()` but not `contributions` POST (same pattern, same commit); caught by PR_CREATE_HOOK background agent. Would have shipped undetected without the hook.)

### Scope audit (fix all instances, not just the reported one)
Before committing a fix for any user-facing element (button color, tooltip, search bar, focus state, clear button), grep app-wide for all instances of the same pattern:
1. `Grep` for the CSS class, component name, or DOM pattern across all HTML/JS files
2. Apply the fix to **every instance**, not just the one that was reported or tested
3. If you're adding a new interactive element (e.g., search clear button), check every search input in the app — not just the one in the current view

(Evidence: 7 "incomplete fix" redirections — fixed 3 tooltips but not all 5, added clear button to one search bar but not the other, changed focus color on one input but not all. USER consistently had to say "what about the other ones?")

### Batch work: verify after each chunk, not at the end
When applying the same pattern across many entries (enriching docs, renaming across files, adding metadata):
1. **Do 3-5 entries first, then stop and verify** — read them back, check each claim against the source. If any are wrong, identify the failure pattern before continuing.
2. **When a spot-check or review finds ANY error, the next step is "grep for this pattern across all entries"** — never dismiss as minor. One wrong entry in a batch means the pattern may be systematically wrong.
3. **Agent prompts for batch work must enforce output structure** — if the task requires a distinction (e.g., caller vs callee), the agent prompt must require that distinction in the output format. Ambiguous agent output produces ambiguous results.

(Evidence: 2026-04-03 — 6 of 101 behavior map preconditions conflated caller checks with callee guards. The error was systematic: agents reported "conditions for behavior to fire" without distinguishing where each was checked. Spot-check found it on entry 4 of 5 but it was dismissed as "minor precision point" instead of investigated as a pattern.)

### Verify agent-reported data
When agents report data counts, table states, file existence, or issue statuses, verify against the live source before using in deliverables:
- Data counts → `SELECT count(*) FROM ...`
- Issue status → `gh issue view #NN`
- File existence → `ls` or `Glob`
- Test coverage → run the actual tests, don't trust directory listings

(Evidence: agents reported 368 gyms (actual ~900), empty tests/ directory (tests existed), stale issue #13 as open (was closed) — 4+ sessions affected)

### Verification summary
Provide a **verification summary** that includes:
- Each file changed (path + what changed)
- How each change was verified (read-back, grep, test run)
- What USER should manually test, if anything

### Preview actual output (data processing)
If the work involves data processing (parser, filter, transform), **preview real output entries** before reporting done — not just audit metrics (counts, percentages, pass/fail). Audit metrics catch structural issues but miss content pollution.

1. Preview the first 5 + last 3 entries from each input file showing ALL fields
2. Check for field pollution: timestamps in city, division text in program, team-size numbers in wrong columns
3. If publishing to a database, verify the database state after publish — not just the parser output

(Evidence: 2026-03-25 — reported "0% empty city" but published data had timezone strings leaking into city/team fields. 2026-03-26 — reported "CLEAN" from narrow audit script, but actual output had gym names crossing column boundaries, team-size numbers in city, and division fragments in program.)

### Test against all inputs
If the fix involves data processing (parser, filter, transform), test against the full input set — not just the file or scenario where the bug was found. A fix that works for Sunday's PDF may break Saturday's. A filter fix for one team may strip another. (Evidence: state bleed fix only handled 3-char values, missed 4-char; favorites pre-filter worked but downstream `filterEntries` still stripped them)

### Failure modes to avoid
- "I've made the changes" — without showing evidence
- "The edit is applied" — without reading the file back
- Reporting completion after a tool error without retrying
- Assuming an edit persisted without confirmation (especially on Windows where file locks can interfere)
