# Pre-PR Checklist

> Hard gate: Complete every applicable step before creating a PR. Do not skip steps without explicit justification noted in the PR description.

## 1. Test Coverage

### New API endpoints/handlers
- [ ] Unit test exists in `tests/api/` covering happy path and primary error cases
- [ ] Test file named to match handler: `tests/api/<handler-name>.test.js`

### New user-facing flows
- [ ] E2E spec exists in `e2e/` covering the core flow
- [ ] If E2E is impractical (e.g., third-party auth, native-only), document why in PR description

### Modified logic
- [ ] Existing tests updated to reflect the change
- [ ] Edge cases from the brief or issue are covered

### New build-time env var (`VITE_*` / `NEXT_PUBLIC_*`)
- [ ] If this PR adds or newly depends on a build-time-inlined env var AND it deploys to a real environment, the var is set in Vercel **for that environment BEFORE merge** (`vercel env ls <environment>` to confirm). These are baked into the bundle at build — setting them after the merge means the deployed build shipped without them, and only a fresh rebuild fixes it. See `patterns/vite-build-time-env-vars.md`. (Evidence: 2026-06-15 #882 — `/app2/` shipped to prod built without `VITE_SUPABASE_*`; looked fine on Preview, where the vars were set.)

### Skip justification
If skipping test coverage, note the reason in the PR description. Valid reasons:
- Pure CSS/visual change (covered by manual test plan)
- Config-only change (env vars, Vercel settings)
- Documentation-only change

## 2. Tests Pass

- [ ] `npm test` passes (all unit tests)
- [ ] Relevant E2E specs pass: `npx playwright test e2e/<spec>.spec.js`
- [ ] **If shared init code changed (app.js, auth.js, router.js, theme.js), run ALL e2e specs** — not just the spec you added. Changes to shared code can break any spec. (Evidence: 2026-03-19 #387 — app.js init change broke 5 specs; only the new spec was run until USER prompted "run the full suite")
- [ ] If no E2E specs are affected, confirm with `npm run e2e` (full suite)

## 3. Self-Validation

- [ ] Completed per `self-validation-protocol.md` — all edits read back, greps confirmed, no orphaned references
- [ ] **Brief-to-implementation transfer check:** Re-read the brief/issue and verify every requirement was addressed. Check especially for: inactive/archived data exclusion, limits/caps, loading states, empty states. (Evidence: admin dashboard missed inactive competition exclusion and top-10 limit despite both being in the shaped brief)
- [ ] **Pre-PR cross-model review:** Run `/second-opinion` on the key changed files before creating the PR. Feed Gemini the full file context (not just the diff) so it can catch contract mismatches, race conditions, and edge cases that read-back validation misses. Fix any blockers before proceeding to step 4.

> This is distinct from step 5 (post-PR hook review). The hook reviews a diff after the PR exists — this reviews full files before the PR is created. Catching issues here means cleaner PRs with fewer follow-up commits. (Evidence: 2026-03-19 #387 — Gemini caught `clearStaleAppCache` interference and `'1'` vs `'true'` localStorage mismatch during debugging, saving ~45 minutes each time. Moving this earlier prevents those bugs from reaching the PR at all.)

## 4. Manual Test Plan

- [ ] **Any UI change going to a preview walk / PR approval → run `/walk`.** This is unconditional and unprompted: if the PR touches a user-facing surface, USER validates it by walking it, and the walk doc is the artifact he follows. Do not hand him a bare preview URL + steps-in-chat. `/walk` (`~/Projects/claude-config/commands/walk.md`) is the formalized procedure — a checklist bullet alone kept getting skipped (USER, 2026-07-28: "you don't do it consistently every time. I want to formalize it").
  - The skill covers, in order: verify the preview is live and serving HEAD, resolve which database it was built against by reading the baked `*.supabase.co` ref out of the deployed JS bundle (not a config file — e.g. example-app's Vite build emits `/app2/assets/index-*.js`, so `curl <preview>/app2/assets/index-*.js | grep -oE 'https://[a-z0-9]+\.supabase\.co'`), confirm the needed migration is applied to that database, seed the fixture into the durable refresh (a `seedXxxFixture()` in `refreshE2EData`, rebuilt from clean each run — never a wipe exemption / a fragment left in place), and traverse the critical path yourself before writing a word of the doc.
  - **Walk accounts are dedicated, not the journey cast.** Sign in as an `e2e-walk-*@test.example.com` role account — never a normal `e2e/test-config.js` journey-cast account (its account-wide CI wipe destroys a walk fixture riding it mid-walk) and never an invented ticket-named one-off. `/walk` names this as a hard rule; `e2e/test-config.js` is the live authority for the current roster.
  - Doc goes to `tmp/preview-walk-<feature>.md` at the worktree root with the `- [ ] Done` header — full structure and `[USER]{}` slot conventions are in `walk.md`, not duplicated here.
  - (Evidence: 2026-06-22 #931 S3a.2 — recommended "walk on the preview" and handed a URL + chat steps; USER had to say twice that writing the walk doc is the agent's job for any UI preview/approval. A feedback memory was tried first and rejected — "feedback memories do not work, put it on a checklist instead." 2026-07-28 #1224 — walk fixture seeded onto a journey-cast account got wiped by CI mid-walk twice in one day, which is what drove the dedicated walk-account rule and the move from checklist bullet to skill.)
- [ ] Written to `tmp/test-plan-<feature>.md` per `test-plan-conventions.md`
- [ ] Includes steps USER can follow to verify the change
- [ ] Covers mobile viewport if UI is affected
- [ ] **Execute the test plan yourself** — the test plan is self-validation, not just documentation for the reviewer. If the steps are runnable, run them. (Evidence: 2026-03-19 #378 — wrote test plan items in the PR but didn't run them. USER said "those are all runnable — run them.")
- [ ] **Manual verification is load-bearing, not polish.** When a slice ships with a deliberately narrow test suite — vitest-with-mocked-window instead of JSDOM integration, no visual regression coverage, no full render-cycle integration tests — the unit suite has *known* coverage gaps that were accepted in exchange for speed. The manual browser pass is the **compensator** for those gaps, not an extra courtesy on top of them. Skipping it doesn't move faster; it silently converts an accepted tradeoff into uncovered risk.
  - **The rule:** if the slice relies on a narrow test suite (the default for this codebase), the manual pass is a hard gate. No "ready for PR" claim without at least TC1 + the happy-path TC executed in a real browser on the dev server. Playwright spot-checks don't count — Playwright can't see visual affordances (cursor, hover, active-state background, contrast).
  - **If you genuinely can't run it:** escalate explicitly. Tell USER "I'm skipping the manual pass, here's what's uncovered, do you still want me to ship?" — do not skip silently. Silent skipping is the thing that's off the table. The accepted tradeoff is "narrow tests + manual compensator," not "narrow tests alone."
  - (Evidence: 2026-04-13 #595 Slice 2 — reported "ready for PR" with 1134 unit tests green; USER's first manual test caught four bugs in TC1-TC2: disabled-looking cursor, silent-no-op click (`UpgradePrompt` phantom), missing `.comp-btn.active` background, highlight disappears on refocus. Three of the four were in the accepted-gap category — visual state + render-cycle integration — and would have been caught by a 60-second happy-path tap in Chrome. The fourth was a mirror-test gap. The tests weren't wrong; the compensator was skipped.)

## 5. Cross-Model Code Review

- [ ] **Confirm the review already ran — do not run it.** `bash-post-hook.sh` fires `run-code-review.sh --pr <N>` automatically on `gh pr create`. The authoritative check is the **posted comment for the current HEAD sha**, which the script writes only after it finishes: `gh pr view <N> --json comments -q '.comments[].body' | grep -c "<!-- code-review:$(git rev-parse HEAD)"` — expect `1`. This is a *verification* step, not an action step. **Do not close the pattern with `-->`** — the marker carries a trailing ` repo=<name>` field (added with #1201), so an anchored form returns `0` against a perfectly healthy review and reports the exact "looks unreviewed" state this check exists to detect. Match the prefix only, as the scripts themselves do (`run-code-review.sh:46`).
- [ ] **Do NOT treat `ls /tmp/code-review-pr-<N>.log` as that confirmation.** The log file is created when the run *starts*, so it exists just the same when the run dies one line later — the two states are indistinguishable by `ls`. Its only use is diagnostic: when the comment is missing, read the log to find out why. (Evidence: 2026-07-22, claude-config PR #12 — the review died instantly on `fatal: ambiguous argument 'main...HEAD'` (#1187), both log files existed, this checklist passed, and the PR sat with zero review comments looking exactly like one whose reviews hadn't finished. Both reviews had to be re-run by hand.)
- [ ] **Only if that check shows the hook did not fire** (manual PR, draft PR) run it by hand: `~/Projects/dev-reference/agents/run-code-review.sh --pr <N>`. Each run is a Claude fan-out plus two Gemini calls and several minutes of wall clock; the script now refuses to post twice for the same HEAD sha, but treat that guard as a backstop, not permission to skip the check. (Evidence: 2026-07-09, decidr PR #2 — hook posted at 14:52, checklist-driven manual re-run posted a duplicate at 15:06.)
- [ ] **If you pushed ANY commit after `gh pr create`, re-run the sha check before merging — the hook does not fire on push.** `bash-post-hook.sh` keys off the created-PR URL, which happens exactly once per PR, so review fixes / CI fixes / rebases ship unreviewed while the PR still displays the comments from the original commit. Re-run the §5 grep against the *new* HEAD: `0` means this diff has had no cross-model pass. Then either run `~/Projects/dev-reference/agents/run-code-review.sh --pr <N>` by hand (a moved sha is a real un-reviewed diff, not a duplicate — the same-sha refusal makes this safe) or tell USER plainly that you're merging a delta without a fresh pass and why. This is the one case where the "do not re-run" rule above does not apply. **At most ONCE per PR, after the last push** — a fix is itself a push, so re-running on every stale marker never terminates; a round with no blockers ends it and you merge on that round, and a round that finds something is fixed, pushed, and merged with the disclosure above. Never a third round unless USER asks. (Evidence: 2026-07-30, claude-config PR #21 — seven rounds, round 13 clean and round 14 run anyway; ended by USER, not by the rule. Full stop condition: `claude-config/references/hooks-and-agents-detail.md` § PR_CREATE_HOOK.) (Evidence: 2026-07-28, example-app PR #1236 — reviews ran clean on `573fc37`, then five review-note fixes were pushed as `5324668` and merged with no reviewer having seen them; noticed only by accident during `/session-capture`. Same mechanism had hit PR #1235 the session before.)
- [ ] Review any **Disagreements** section — the dissenting opinion is often right
- [ ] Skim the **Filtered** section — findings the verify-audit pass removed as false-positive / by-design / pre-existing. Sanity-check that nothing real was filtered away (each entry must cite a file:line; an uncited filter is suspect)
- [ ] Address all **Blockers** before merging

> This step catches bugs that single-model review misses. Gemini's structural focus has caught data-loss bugs that Claude's runtime focus missed (2026-03-15). The synthesis stage now also runs a verify-audit pass that greps each finding against the code to filter false positives before they reach the PR — see `patterns/adversarial-debate-verify-review.md`.

## 5b. Cross-Model Test Coverage Review

- [ ] **Confirm it already ran** — `bash-post-hook.sh` fires `run-test-coverage-review.sh --pr <N>` alongside the code review. Same rule as §5: the authoritative check is the sha-pinned comment, `gh pr view <N> --json comments -q '.comments[].body' | grep -c "<!-- test-coverage-review:$(git rev-parse HEAD)"` — expect `1`. Prefix only, no closing `-->`, for the reason given in §5. `ls /tmp/test-coverage-pr-<N>.log` proves the run *started*, never that it finished. Verification step, not an action step.
- [ ] **Only if the hook did not fire**, run by hand: `~/Projects/dev-reference/agents/run-test-coverage-review.sh --pr <N>`
- [ ] Address all **Unit Test Gaps** for API routes and auth flows before merging
- [ ] Address or justify all **E2E Test Gaps** for user-facing changes

## 6. Behavior Map

- [ ] If new user-facing flows were added: new entries added to `app-behavior-map.md`
- [ ] If existing flows changed: entries updated in `app-behavior-map.md`
- [ ] New entries tagged `[untested]` (or `[unit]`/`[E2E]` if tests were added in this PR)
- [ ] If PR added/modified test files: update tags on covered entries (`[untested]` → `[unit]`/`[E2E]`)
- [ ] Skip if: pure backend/config change with no user-facing behavior change

> This was previously in the post-merge checklist where it kept getting skipped. It belongs in the PR so the behavior map ships with the code change.

## 7. Clean Up

- [ ] **UI primitive check (rebuild stack):** For each new raw `<button>`, `<input>`, overlay, or pull-to-refresh in the diff — does a `components/ui/*` primitive (or a `npx shadcn add <x>` one-liner) already cover it? If yes, use the primitive; don't ship bespoke Tailwind copies of what shadcn provides. (Evidence: #960 — ~19 raw `<button>` + 8 raw `<input>` hand-rolled after shadcn foundation was installed but unused.) This is an advisory check; the wiring-check is the blocking gate.
- [ ] No `console.log` debug statements left in production code
- [ ] No temp/scratch files outside `tmp/`
- [ ] No commented-out code blocks added by this PR
- [ ] `git diff` reviewed — no unintended changes
- [ ] **The next two checks apply only to a no-build-step stack** (`stack: vanilla-web` in the repo's `product.json` — static HTML/JS served directly, no bundler). A repo that builds with Vite/webpack/etc. already gets cache-busting for free from the bundler's content-hashed output filenames — skip both items below for that stack. example-app's current shipped stack is the vanilla-web case these two items exist for:
- [ ] **Any new local JS/CSS file added to the app's static entry HTML (example-app: `app.html`) has a `?v=YYYYMMDD` cache-bust param.** Files added without one are a latent Sentry error waiting for their first API change. (Evidence: 2026-04-15 — `live-activities.js` shipped without a version param; stale cached copies caused `loadQueue is not a function` in production after #598. See `patterns/no-build-cache-busting.md`)
- [ ] **Any JS/CSS file modified in this branch has its `?v=` bumped in the static entry HTML to today's date.** Run: `git diff <resolved-base>...HEAD --name-only | grep "^<frontend-dir>/"` (example-app: `grep "^web/"`) and cross-check every result against the script tags in the entry HTML (example-app: `app.html`). If the file is listed there and its `?v=` predates the most recent commit touching it, bump it. (Evidence: 2026-04-30 — 17 stale entries found across files modified over 14 days; `time-classification.js` and `entry-card.js` were 14 days stale, causing a Sentry TypeError on the slice-2 preview when browsers served cached copies without `findPerformingEntries`.)

## Shortcut: Trivial Changes

For single-line fixes, typo corrections, or dependency bumps, only steps 2, 3, and 7 are required.

## 8. gh pr create — always pass `--head` explicitly

- [ ] **The `gh pr create` command MUST include `--head <branch-name>`** whenever the session cwd is not on the branch being PR'd. With the worktree-first workflow (sessions run from the main repo checkout and operate on worktrees via absolute paths), this is always.

> Why: `gh pr create` silently defaults to the session cwd's current branch, not the branch you just pushed. If your session cwd is on `feature/A` but you just pushed `feature/B` from a worktree, `gh pr create` opens the PR from `feature/A`. The PR will list whatever happens to be on cwd's branch — sometimes nothing (no-op merge), sometimes another team's in-flight work shipped under the wrong title.
>
> (Evidence: 2026-05-06 — pushed `chore/cleanup-untracked-2026-05-06` from a worktree, ran `gh pr create` from main session (cwd on `feature/review-queue-team-breakdown`). gh opened PR #779 from `feature/review-queue-team-breakdown`. Merged 5 days later as a no-op; the intended screenshot + gitignore content never shipped. Required redo as PR #788.)
>
> **Verification:** After `gh pr create` returns a URL, run `gh pr view <N> --json headRefName -q .headRefName` and confirm it matches the branch you pushed. If it doesn't, close the PR and re-open with `--head`.

## 9. PR Body — Review Guide (always include)

- [ ] **The PR body MUST include a `## Review Guide` section** that orients the reviewer: where to look, in what order, what to skip, and where the risk is. This is not the same as the "what changed" summary — it is a *reading order* tuned to the reviewer's finite attention. (USER, 2026-06-12: "start writing review guides for every PR and putting it in the body.")

> Why: a raw diff forces the reviewer to discover the important 200 lines among the generated/boilerplate/already-vetted thousands. The review guide front-loads that triage so the human spends judgment where it's actually needed. Get the accurate diffstat first — `git show <sha> --stat` or `git diff <base>...<head> --stat` against the **current** base (a stale local `main` inflates the diff with already-merged work).

**Template** (drop sections that don't apply; keep it scannable — this is a map, not an essay):

```markdown
## Review Guide

**30-second summary:** [plain-language what this does + the net, 1-2 sentences]

### Review in this order
**① The real review — [N lines]**
- `path/to/core.ts` (NN) — [the load-bearing logic]. Focus: [the specific thing to judge].
- `path/to/next.ts` (NN) — Focus: [...]

### Skip / skim (generated or pre-vetted)
- `path/to/bundle.js` (NNN) — generated build output, don't read.
- `*.test.*` — already reviewed (3-agent + Gemini) and green in CI; skim for intent.

### Judgment calls embedded
1. [a tunable constant / a product decision / an infra tradeoff the reviewer should actively bless]

### Already validated — don't re-verify
- [unit/typecheck/gate/integration results, with numbers]

### Risk to weigh
- [the one or two things genuinely worth a human's worry, + the proposed disposition]
```

- [ ] Got the **accurate** diffstat (against the current base, not a stale local `main`) before writing the guide.
- [ ] If a background code-review agent / `run-code-review.sh` posts findings, the Review Guide's "Risk to weigh" stays consistent with them (update the body if a real risk surfaces).

---

*Last Updated: 2026-07-28 (§4 — point at the new `/walk` skill instead of carrying the full walk-doc procedure inline; add the dedicated walk-account rule)*
