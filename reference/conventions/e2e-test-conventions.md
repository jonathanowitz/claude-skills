# E2E Test Conventions (Playwright)

## Hard rule: behavioral RED only

**Tests that fail with `Cannot find module`, `ENOENT`, or any other import-resolution error are NOT in valid RED state.** The test bodies never executed; the assertions never ran. A GREEN that follows could pass for the wrong reason.

Before declaring RED:
1. Create stub modules at every canonical import path (minimal exports, no behavior — e.g. handlers return 501)
2. Run the suite
3. Every failure message must cite an assertion (`expected X to be Y`, `expected promise to reject`, status mismatch). Zero `Cannot find module` failures.
4. Tests passing against the stub are suspect — each one must be justified (legitimate cases: stub body matches v1 final form). If you can't justify a stub-pass, the test is vacuous — fix or delete it.

This is universal — applies to unit, integration, and E2E. Full pattern + stub template: [`patterns/red-state-must-be-behavioral.md`](../patterns/red-state-must-be-behavioral.md).

## When to Write E2E Tests

**Before implementation, not after.** E2e tests are written at Stage 4 alongside unit tests, as part of the spec. They describe user behavior from the behavior map. Their RED state depends on what's changing:

- **Refactor existing UI:** Test asserts the new interaction model against the current app. Fails because the UI still uses the old pattern. Example: test clicks "L1" pill in a filter row → fails because the app still has a dropdown select. This is the strongest RED — catches both "feature absent" and "regression to old pattern."
- **Net-new feature:** Test asserts behavior that doesn't exist yet. Example: test taps a card and expects an action row → cards don't expand yet. The app loads and the test engages, but the behavior is absent.

Both are behavioral failures: the app works, the test navigates, but the spec doesn't match reality. This is distinct from structural failures (`ENOENT`, `ReferenceError`) where the test can't run at all.

If you can't write the e2e test because you don't know what the UI will look like, the brief isn't specific enough — go back to shaping. Never defer e2e tests to a "later slice" or "later session." Tests written after implementation validate what was built, not what should have been built.

(Evidence: 2026-04-03 — deferring e2e to later slices was identified as a process gap. The "placeholder selectors" escape hatch in Stage 4 was enabling post-implementation test writing.)

## Keep What's Valuable, Drop What's Disposable

Not every RED-GREEN gate test deserves a permanent slot in the suite. After a test goes GREEN, classify it:

- **Keep permanently** — tests with asymmetric value. The clearest example: a Capacitor-stubbed iOS branch test. iOS behavior is otherwise unverifiable without a device, and one stubbed-Capacitor spec establishes a reusable pattern (stub `window.Capacitor.isNativePlatform` in `addInitScript` before boot).
- **Keep permanently** — tests that guard a non-obvious invariant (platform forks, error paths, edge cases, concurrency, ordering).
- **Drop after ship** — tests that only prove the current implementation works. Typical signals: asserts a specific DOM element is absent, checks a copy string, or duplicates what the code itself guards. Copy tests especially will be noisy under iteration.
- **Drop after ship** — XS/S changes rarely need more than one permanent test. Default to 0–1 permanent tests for trivial UI changes.

When writing the spec, ask: *"Will this test catch a real regression six months from now, or is it only proving the current change works?"* If the latter, flag it as disposable in the PR description so it gets stripped post-merge. Update behavior-map `[untested]` tags to reflect what's **actually** kept tested — don't promote tags for tests that will be deleted.

(Evidence: 2026-04-17 #631 — initial spec had 3 tests (checkbox absence, web upgrade-slide copy, iOS-stubbed branch); USER flagged them as "temporary for dev only." Dropped the first two, kept the iOS-stubbed one. The copy test would have been noisy under copy iteration; the DOM-absence test offered no asymmetric value vs. the code itself.)

## Before Writing Any E2E Test

0. **Check behavior map preconditions** — Read the entry in `example-context/architecture/app-behavior-map.md` for the feature you're testing. Each entry has two layers:
   - `*Preconditions:*` — what the **caller** checks (auth level, view, state). This determines your test setup: auth fixture, navigation target, and state seeding.
   - `*Callee guards:*` — what the **called function** checks internally (localStorage flags, server state). Your test must satisfy these too, or the behavior silently no-ops. Seed these via `addInitScript`, `page.evaluate`, or database setup.

1. **Verify element selectors against the HTML** — grep `web/*.html` for the actual element IDs. Never trust JS code that references them — `getElementById` calls for removed IDs silently return `null`. The JS and HTML can drift apart without errors.

2. **Check form validation layer** — HTML `required` and `type="email"` attributes prevent form submission at the browser level, before JS validation runs. If a form input has these attributes, test with `el.checkValidity()`, not by checking for JS error elements.

3. **Check how the element becomes visible** — Before writing `await page.locator('#foo').click()`, understand the mechanism: Is it a CSS class toggle? A JS event handler? An HTML attribute? Check that the handler is actually bound by the time your test clicks.

## Authentication in Tests

- **Auth fixture** (`e2e/fixtures/auth.setup.js`) creates storageState for user + admin via Supabase `signInWithPassword`
- **StorageState tokens expire** — Supabase JWTs are short-lived. If a test needs a fully functional app (API calls, component init), sign in via the UI within the test rather than relying on storageState. The app may render in a broken state with an expired token.
- **StorageState is reliable for** — skipping the login modal, checking page renders, testing UI elements that don't need live API data
- **Test user credentials** are in `.env` (local) and GitHub secrets (CI). Never hardcode them.

## Test Organization

- **Tag tests by auth requirement:** `@auth` for authenticated user, `@admin` for admin user
- Playwright config routes tagged tests to the right storageState project
- Untagged tests run without auth (unauthenticated flows)
- Tests that sign in via UI within the test body don't need tags

## Env Vars

- Playwright config loads `.env` via an inline parser (no `dotenv` dependency)
- CI injects env vars via GitHub secrets — no `.env` needed
- Required test env vars: `TEST_USER_EMAIL`, `TEST_USER_PASSWORD`, `TEST_ADMIN_EMAIL`, `TEST_ADMIN_PASSWORD`

## Running Tests Efficiently

- **Always capture full output (HARD RULE)** — Never pipe e2e output through `grep`, `tail`, or `head`. Never kill a run mid-way. Capture complete stdout on every run. Each re-run to see what failed costs 1-3 minutes. If the output is long, read it — don't truncate it.
  (Evidence: 2026-04-07 — 5+ re-runs just to get failure details that would have been visible in full output. Burned 30+ minutes. 2026-04-08 — multiple runs killed mid-way, then re-run to see details.)
- **Zero failures is the only acceptable state** — Never dismiss failures as "pre-existing" or "not caused by this PR." If tests fail, either fix them or prove they fail on main AND file an issue. 190 failures is not "clean for our change."
  (Evidence: 2026-04-07 — called 190 failures "pre-existing" without verifying. USER: "in what world would you call 8 skips and 190 failures a clean full suite?")
- **Run failing tests individually before blaming infrastructure** — When multiple tests fail, run the first 3 individually before theorizing about infrastructure (Docker, vercel dev, race conditions). Individual failures reveal specific root causes; batch failures hide them behind infrastructure noise. Do NOT assume all failures share a single cause.
  (Evidence: 2026-04-08-00-14 — 83 failures blamed on auth race conditions, actual causes were diverse. 2026-04-08-20-14 — all failures blamed on vercel dev degradation, individual tests revealed unrelated bugs.)
- **Target specific tests with `-g`** — Use `npx playwright test <file> -g "test name pattern"` to run only failing tests. Full suite runs take 4-7 minutes; targeted runs take 30-60 seconds.
- **Auth setup always runs** — it's a dependency of `chromium-auth` project, so it runs even when targeting specific tests. Keep auth setup fast.
- **Don't re-run the full suite on every iteration** — Run failing tests only until they pass, then do one final full-suite run to confirm no regressions.
- **Run ONE spec file at a time** — Never run multiple spec files in a single `npx playwright test` command during development. Multiple specs share one `vercel dev` instance and cause intermittent failures from port/state conflicts. Run specs individually, then do one final combined run to check for interactions.
- **Never run Playwright from background `cd && npx` commands** — The shell resets cwd after `cd`. Background Bash commands that chain `cd /worktree && npx playwright` will silently fail or run in the wrong directory. Use absolute paths or run foreground.
- **Each Playwright run = 1-3 minutes** — Auth setup + cold start + test execution. Budget for this when iterating on failures. 5 iterations = 10-15 minutes of waiting. Minimize iterations by reading error messages carefully before retrying.
- **Always check the summary report after a full suite run** — The JSON reporter writes `tmp/e2e-results.json` and `globalTeardown` generates `tmp/e2e-summary.txt` with skip/fail/fixme breakdown. Run `node e2e/summarize-results.js` if the teardown didn't fire. Never rely on the tail of Playwright's list output to count skips — read the summary.
  (Evidence: 2026-04-03 #526 — 5+ full suite re-runs just to grep for skip counts, wasting ~45 minutes. The JSON summary would have shown the breakdown immediately.)

## Overlay/Backdrop Blocking

- **Centralized kill switch (#377):** All three overlay systems (theme announcement, onboarding modal, guided tour) check for `data-test-suppress-overlays` on `document.body` and return immediately if present. Use this instead of per-overlay localStorage flags.
- **Auth setup handles standard overlay suppression** — `auth.setup.js` sets `od_theme_announced`, `has_seen_onboarding`, and `od_tour` in localStorage during storageState capture. All `@auth` tests inherit these flags automatically.
- **For tests that need additional suppression** (e.g., custom storageState or unauthenticated tests that interact with overlay-prone views):
  ```javascript
  await page.addInitScript(() => {
    document.addEventListener('DOMContentLoaded', () => {
      document.body.setAttribute('data-test-suppress-overlays', 'true');
    });
  });
  ```
- **"intercepts pointer events" = overlay blocking** — When `locator.click()` times out with this message, read the intercepting element name in the call log. If it's `onboarding-modal`, `theme-announce-backdrop`, or `od-tour-backdrop`, the overlay suppression didn't work. Check: (1) is the storageState from auth setup being used? (2) does the test need `data-test-suppress-overlays`?
- **Don't layer workarounds** — If the kill switch doesn't work, investigate why. Don't stack localStorage flags + route interception + DOM removal. That's how the old `suppressOverlays()` function grew to 18 lines. The root cause is almost always a missing localStorage flag in auth setup.

## Scenario-Based Test Users

- **Create dedicated e2e accounts per scenario** — don't reuse manual test accounts (`test1-5@test.com`). Dedicated accounts prevent state pollution between manual testing and e2e runs.
- **One-time setup script** (`e2e/setup-e2e-users.js`) creates accounts via Supabase admin API. Idempotent — safe to re-run.
- **State reset in auth setup** — use the Supabase service role client to reset profiles and follows to known state before saving storageState. This ensures tests start from a deterministic baseline.
- **`test.use({ storageState })` per describe block** — override the project-level storageState within a spec file to test different user states without adding Playwright projects.
- **Always keep a profile row** — deleting `user_profiles` entirely breaks auth detection. Reset to `{ home_gym: null, has_seen_onboarding: true }` for "fresh" users (set `has_seen_onboarding: true` to avoid onboarding modal interference in tests).
- **Tests that mutate DB state need `beforeEach` reset** — if a test saves a gym or creates follows, subsequent tests in the same suite will see stale DB state. Add a `beforeEach` that resets the user's profile via the Supabase service role client.

## Testability Hooks

- **Wait for `data-app-ready` (#377)** — The app sets `document.body.setAttribute('data-app-ready', 'true')` when all initialization is complete (data loaded, filters restored, smart defaults evaluated, overlays decided). Use this as the single wait before interacting with the UI.
- **Clear `data-app-ready` before navigation (#383)** — The app sets `data-app-ready` TWICE: once after initial data load (before auth resolves), once after the auth callback completes. If a test waits for the first signal, it acts on a premature render. Always clear the attribute before navigating to a competition:
  ```javascript
  await page.evaluate(() => document.body.removeAttribute('data-app-ready'));
  await page.locator('.comp-card').first().click();
  await page.waitForSelector('body[data-app-ready="true"]', { timeout: 30000 });
  ```
- **`data-profile-fetched` still exists** for backward compatibility but `data-app-ready` is a superset — it signals that profile, follows, AND schedule are all ready.
- **Prefer data attributes over content checks** — waiting for `#result-count` text or `.day-group` elements fails when the user sees an empty state or smart default. Data attributes signal "the operation completed" regardless of what the UI renders.

## Smart Default Handling

- **Always handle the empty state** — When an authenticated user navigates to a competition with no favorites or home gym match, the app shows "X performances ready" + a "Browse Full Schedule" button instead of entry cards. Tests that wait for `.entry-card` will time out.
  ```javascript
  const browseBtn = page.locator('#browse-full-btn');
  if (await browseBtn.isVisible()) {
    await browseBtn.click();
  }
  ```
- **Filter to a gym after getting entries on screen** — Follow/unfollow actions trigger a full DOM re-render via the `followsChanged` event. Without a filter active, entry card elements get replaced and locator references break. Filtering to a gym keeps the entry set stable:
  ```javascript
  const gymName = await page.locator('.fav-star').first().getAttribute('data-program');
  if (gymName) {
    await page.locator('#gym-input').fill(gymName);
    const gymResult = page.locator('#gym-list li:not(.search-category)').first();
    await expect(gymResult).toBeVisible({ timeout: 3000 });
    await gymResult.click();
    await expect(page.locator('.entry-card').first()).toBeVisible({ timeout: 10000 });
  }
  ```
  (Evidence: #383 — all 6 follows.spec.js tests failed because DOM re-renders replaced entry cards mid-assertion)

## Locator Stability

- **Use position-based locators, not state-filtered locators** — Locators like `.fav-star:not(.active).first()` are "live" in Playwright — they re-evaluate on every action. After clicking adds the `active` class, the locator re-resolves to a *different* element (the next inactive star). Use `.fav-star.first()` or `.nth(N)` instead.
  ```javascript
  // BAD — re-resolves to a different element after click
  const star = page.locator('.fav-star:not(.active)').first();
  await star.click();
  await expect(star).toHaveClass(/active/); // checks the WRONG element

  // GOOD — position-based, stable across re-renders
  const star = page.locator('.fav-star').first();
  await star.click();
  await expect(star).toHaveClass(/active/); // checks the element you clicked
  ```
- **To find an element by state, use a loop with `.nth()`:**
  ```javascript
  const stars = page.locator('.fav-star');
  let targetIdx = -1;
  for (let i = 0; i < Math.min(await stars.count(), 10); i++) {
    if (!(await stars.nth(i).evaluate(el => el.classList.contains('active')))) {
      targetIdx = i; break;
    }
  }
  const star = stars.nth(targetIdx);
  ```
  (Evidence: #383 — `.fav-star:not(.active)` assertions checked wrong element in 3 tests)

- **Assert on the accessible NAME, not just the role, when a component owns user-facing affordance copy** — `getByRole('searchbox')` / `getByRole('button')` with no `{ name }` filter passes for *any* element of that role. If a refactor changes the element's accessible name (aria-label, associated `<label>`, or placeholder), a role-only locator stays green while the journey that *does* filter by name breaks. When the element's name is meaningful to the user (a search box's prompt, a button's label), scope the locator: `getByRole('searchbox', { name: /search for your program/i })`. Mirror this in the unit/component test so the fast suite catches name drift too — a unit test that queries role-only is the gap that lets the regression reach the slow journey suite. (Evidence: 2026-06-21 PR #923 — the S3a.0 `ProgramSearch` extraction changed the claim search box's accessible name from "Search for your program" to a generic "Search". The S2a claim journey filtered by name and went red; both `ProgramSearch.test.tsx` and `ClaimFunnel.test.tsx` queried `getByRole('searchbox')` with no name and stayed green, so the regression was invisible to the unit suite. Fix: made the accessible name a required prop and name-scoped the unit guards. See the baseline-attribution rule in `workflows/self-validation-protocol.md`.)

## Timing and Waits

- **Wait for `data-app-ready`, not individual signals** — one wait replaces the old chain of `#schedule` visible + `data-profile-fetched` + `waitForTimeout`. See Testability Hooks section.
- **Profile fetch + data load takes 10-15s on cold vercel dev** — use generous timeouts (30s for `data-app-ready`, 15s for individual elements).
- **Always use auto-retrying assertions** — `await expect(locator).toHaveClass(/pattern/)` retries until timeout. Never use `evaluate()` + `expect()` for DOM state checks — that takes a one-time snapshot that can be stale:
  ```javascript
  // BAD — static snapshot, no retry
  const val = await el.evaluate(el => el.classList.contains('active'));
  expect(val).toBe(true);

  // GOOD — auto-retries until timeout
  await expect(el).toHaveClass(/active/, { timeout: 5000 });
  ```
- **`isVisible()` is a one-shot check — `expect().toBeVisible()` auto-retries** — `locator.isVisible({ timeout })` does NOT wait for the element to become visible. The timeout only controls selector resolution, not visibility polling. If an element appears after an async operation (API fetch, render cycle), `isVisible()` returns `false` immediately. Use `expect(locator).toBeVisible({ timeout })` instead, which auto-retries until the timeout expires. This is especially important for "skip if not visible" patterns:
  ```javascript
  // BAD — one-shot, misses elements that appear after async work
  if (await btn.isVisible({ timeout: 5000 }).catch(() => false)) { ... }

  // GOOD — auto-retries, catches async-rendered elements
  try {
    await expect(btn).toBeVisible({ timeout: 5000 });
    // proceed
  } catch {
    test.skip(true, 'Element not available');
  }
  ```
  (Evidence: 2026-04-03 #526 — mark-all-read button was present in DOM (diagnostic confirmed `markBtnHidden: false`) but `isVisible()` returned false because `renderMarkAllBtn()` ran after an async fetch inside `openDropdown()`. Switching to `expect().toBeVisible()` fixed the flake.)
- **For custom async checks, use `toPass()`:**
  ```javascript
  await expect(async () => {
    const fired = await page.evaluate(() => window._someFlagSet);
    expect(fired).toBe(true);
  }).toPass({ timeout: 5000 });
  ```
- **Never use `waitForTimeout` for init synchronization** — if you're adding `waitForTimeout` to wait for the app to be ready, you're working around a missing testability hook. Use `data-app-ready` instead. `waitForTimeout` is only acceptable for debounce waits after user input (e.g., 500ms after typing in a search field).

## Common Gotchas

- **`vercel dev` must be the web server** — the app depends on Vercel routing (`cleanUrls`, API catch-all). `npx serve` won't work.
- **localStorage gets reinitialized on navigation** — sign-out clears user keys, but the app immediately resets some (like `active_filters`) when it navigates to the schedule view. Test for competition-scoped keys that don't auto-recreate.
- **Worktrees need `.env` and `.vercel/`** — copied from the main repo. Playwright's `vercel dev` web server won't start without the Vercel project link.
- **`vercel dev` only reads `.env` — not `.env.local`** — Despite Vercel docs and conventions suggesting `.env.local` overrides `.env`, `vercel dev` ignores `.env.local` entirely (vercel/next.js#17338, open since 2020). It also ignores inline shell env vars (`FOO=bar vercel dev`) and does NOT pull env vars from the Vercel dashboard at runtime. The only file it loads is `.env`. To use a separate Supabase branch for E2E testing, use `TEST_SUPABASE_*` env var names in `.env` (which is gitignored) and resolve them first in server code: `process.env.TEST_SUPABASE_URL || process.env.SUPABASE_URL`. Production never sets `TEST_*`, so it falls through safely.
  (Evidence: 2026-04-01 #381 — Gemini's second opinion incorrectly stated `.env.local` > `.env` priority. Inline env vars, `.env.local`, `.vercel/.env.development.local`, and dashboard vars all failed. Only `.env` is read.)
- **Teams can compete multiple times** — a team_id may appear in multiple schedule entries. Use `.first()` when locating by `data-team-id` to avoid strict mode violations.
- **"intercepts pointer events" means something is on top** — Read the element name in the Playwright call log. Common culprits: `version-update-banner` (STATE_VERSION mismatch), `onboarding-modal`, `theme-announce-backdrop`, `od-tour-backdrop`. Don't guess — the call log tells you exactly what's blocking.
- **Fixed-position elements block all clicks** — Any `position: fixed` element with high z-index will intercept Playwright clicks on the entire page. If you add a new fixed element, make sure tests suppress or dismiss it.

## Vanilla JS Initialization & State Gotchas

- **Startup cleanup functions sabotage test fixtures** — Any code that clears localStorage at parse time (e.g., `clearStaleAppCache` checking STATE_VERSION) will destroy values set via `addInitScript`. Always set guard keys (like STATE_VERSION) in test setup so cleanup functions see a matching version and skip deletion.
  (Evidence: 2026-03-19 #387 — `clearStaleAppCache` deleted expired cache and old-format cache test fixtures before `initializeCompetition` could read them. 2 tests failed for 15+ minutes.)

- **`addInitScript` is NOT run-once** — It re-executes on page creation events within the browser context, including on `page.reload()`. For one-shot localStorage setup that the app will delete during init, use `page.evaluate()` after navigating to the origin, then `page.reload()` so the app sees the value on the second load.
  (Evidence: 2026-03-19 #387 — `addInitScript` re-set a bare UUID in localStorage after `migrateOldCache` deleted it. 3 debugging iterations to identify.)

- **"View visible" does not mean "async operation complete"** — In vanilla JS without framework batching, `Router.navigate()` shows the target view instantly. Any async work triggered by the action (API calls, cache writes) may still be in-flight. Use `toPass()` for assertions on state that depends on async operations.

- **Async dropdowns: wait for content, not the container** — UI patterns like `openDropdown()` show the container immediately (`classList.remove('hidden')`) but fetch data asynchronously. Buttons or state that depend on the fetched data (like a "mark all read" button that checks `is_read`) won't render until after the fetch. Wait for the data-dependent child element first, then assert on the conditional UI:
  ```javascript
  // BAD — container opens instantly, but items haven't loaded yet
  await page.locator('#bell-btn').click();
  await expect(dropdown).not.toHaveClass(/hidden/);
  await expect(markAllBtn).toBeVisible(); // fails — fetch hasn't completed

  // GOOD — wait for content to prove the fetch is done
  await page.locator('#bell-btn').click();
  await expect(dropdown).not.toHaveClass(/hidden/);
  await expect(page.locator('.notif-item').first()).toBeVisible({ timeout: 10000 });
  await expect(markAllBtn).toBeVisible({ timeout: 5000 });
  ```
  (Evidence: 2026-04-03 #526 — `openDropdown()` shows dropdown, calls `fetchNotifications()` async, then `renderMarkAllBtn()`. Test checked button before fetch completed.)
  (Evidence: 2026-03-19 #387 — test asserted cache was written immediately after schedule view appeared, but `switchCompetition()` was still fetching metadata.)

- **Guard async render functions against re-entrancy** — Without framework reconciliation, multiple event sources (hashchange, routeChange, authStateChange) can trigger overlapping async renders. A second render during the first render's `await` overwrites the DOM. Use a `_renderInProgress` lock.
  (Evidence: 2026-03-19 #387 — queued `hashchange` triggered a second `CompetitionsView.render()` during the first render's `await fetch()`, wiping the contextual banner.)

- **Async functions without await return Promises (always truthy)** — `!!someAsyncFn()` is always `true`. When checking auth state synchronously in render functions, use `window.currentUser` (set synchronously by auth.js), not `Auth.getSession()` (async).
  (Evidence: 2026-03-19 #387 — locked cards never rendered because `Auth.getSession()` returned a Promise, making `isAuth` always `true`.)

## Seed Data & Global Setup

- **Seed `now()` timestamps drift** — SQL `now()` evaluates once at seed time. If the e2e branch seed is older than any API time filter (e.g., "last 14 days" for notifications), the seeded rows silently disappear from API responses. Add timestamp refresh logic in `globalSetup` for any table with time-based API filters, same as competition date refresh.
  (Evidence: 2026-04-03 #526 — notification `created_at` was 30+ days old. API's 14-day cutoff excluded all 3 notifications. Mark-all-read test skipped because no unread notifications existed.)

- **Seed data changes cascade through selectors** — Before modifying any seed column that affects CSS classes or element visibility (e.g., `is_active`, `schedule_status`), grep ALL spec files for locators that select the affected elements. A single flag change can break locators across 10+ files. Pattern: `grep -r 'comp-card:not' e2e/` before changing competition seed properties.
  (Evidence: 2026-04-03 #526 — changing `is_active=false` to `true` for the past competition made `.comp-card:not(.unavailable).first()` resolve to a hidden `.comp-ended` card in 11 spec files. Required adding `:not(.comp-ended)` to 28 locators.)

- **Time-relative seed data must be created at test time, not in globalSetup** — `globalSetup` runs once before all tests. A "now + 5 min" entry ages out during a 9+ minute suite run. For tests that depend on time proximity (e.g., "Example Project" badge requires entry within 7 min of now), upsert the entry inside the test body using the Supabase service role client. Use a deterministic UUID so repeated runs update the same row.
  (Evidence: 2026-04-03 #526 — globalSetup inserted entry at now+5min, but the Example Project test ran 9 minutes later → entry was 4 minutes past → outside 7-min threshold → test skipped.)

- **`addInitScript` + localStorage is unreliable for parse-time IIFEs** — Even though Playwright docs say `addInitScript` runs before page scripts, app IIFEs that read localStorage at parse time may not see values set by `addInitScript`. Confirmed by diagnostics: the console showed `[Debug] Fake time enabled` but the render function used real time. Prefer creating real data via Supabase upsert over injecting fake state via localStorage. The app discovers real data naturally through its normal fetch → render path.
  (Evidence: 2026-04-03 #526 — 5 iterations trying `addInitScript`, `page.evaluate` + `reload`, hash navigation. All failed to reliably feed `debugFakeTime` to `getVenueNow()`. Upsert approach worked on first try.)

- **`test.fixme()` for dead tests, `test.skip()` for data-dependent** — When UI is removed and tests reference dead selectors, use `test.fixme('title', fn)` at the declaration level. This separates "known dead, tracked for rewrite" from "conditional skip based on data availability." The JSON reporter distinguishes them via `test.annotations[].type === 'fixme'`, enabling automated tracking of skip categories.

## Debugging E2E State Issues

- **Instrument before theorizing** — When a localStorage/state assertion fails, do NOT guess at the cause. Immediately add a localStorage proxy via `addInitScript` to log all operations on the key:
  ```javascript
  await page.addInitScript(() => {
    const orig = { set: localStorage.setItem.bind(localStorage),
                   rm: localStorage.removeItem.bind(localStorage) };
    window.__lsOps = [];
    localStorage.setItem = (k, v) => {
      if (k === 'YOUR_KEY') window.__lsOps.push({ op: 'set', v: v?.slice(0,40),
        src: new Error().stack.split('\n')[2] });
      return orig.set(k, v);
    };
    localStorage.removeItem = (k) => {
      if (k === 'YOUR_KEY') window.__lsOps.push({ op: 'rm',
        src: new Error().stack.split('\n')[2] });
      return orig.rm(k);
    };
  });
  // After test runs: console.log(await page.evaluate(() => window.__lsOps));
  ```
  (Evidence: 2026-03-19 #387 — this pattern immediately revealed that `migrateOldCache` deleted the key but it was re-set by `addInitScript` persistence.)
