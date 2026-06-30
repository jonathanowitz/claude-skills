# Browser-QA Gate (Pre-PR)

Dynamic complement to the static wiring check in `rules/hooks-and-agents.md` § Pre-PR Validation Agent. The static check greps the diff for click handlers; the browser-QA gate *actually clicks* the new elements in a real browser and verifies the user-visible state transition happened.

## The Failure Class This Catches

Static wiring passes (handler exists) but the feature is still inert:

1. **Handler throws silently** — console error; UI does nothing; no test covers the flow.
2. **State transition doesn't happen** — click fires, function runs, but the expected class toggle / DOM update / navigation never occurs (wrong selector, race with re-render, no-op guard tripped).
3. **Platform branch silently fails** — `if (isNative) {...} else {...}` with the native branch broken. Web works; iOS ships broken. Capacitor stub tests cover this *if written*, but net-new features often ship without them.
4. **Handler bound to wrong element** — delegation selector is off by one class; click hits a child that doesn't match; `closest()` returns null; nothing happens.

Static grep catches (4a) "no handler at all." It misses 1–4 above. Those require a real click in a real browser.

**Evidence:** 2026-04-13 #595, 2026-04-14 #598, 2026-04-16 #621 — all shipped rendered-but-inert interactive elements *after* the static wiring check landed. Three incidents inside two weeks means the static gate is necessary but not sufficient.

## When the Gate Fires

Pre-PR, same trigger as the static wiring check. Both gates share the diff-analysis step:

1. `git diff main...HEAD` → extract newly-added interactive elements (`<button`, `<a data-action`, `class=".*-btn"`, `addEventListener('click'`, `onclick=`).
2. For each new element: static check verifies a handler exists; browser gate verifies the click does something.
3. If the diff has **no** new interactive elements, both gates pass trivially.

## Implementation — Ephemeral Script, Not a Permanent Spec

This is **not** a new smoke spec. The smoke suite has a hard cap (≤11 specs) and protects permanent invariants. Browser-QA runs are disposable — one shot, pre-PR, then discarded.

Pattern: pre-PR agent writes a throwaway spec to `tmp/pre-pr-qa-<branch>.spec.js`, runs it once with Playwright, captures pass/fail + screenshots, deletes the spec on success. On failure, the file stays for debugging and the gate blocks the PR.

```javascript
// tmp/pre-pr-qa-<branch>.spec.js — ephemeral, deleted on pass
import { test, expect } from '@playwright/test';

test('pre-pr wiring: new-button-class actually navigates', async ({ page }) => {
  await page.goto('/');
  // For each new interactive element in the diff, one small scenario:
  await page.locator('.new-button-class').click();
  // Assert the state transition the element is supposed to cause:
  await expect(page.locator('.expected-panel')).toBeVisible({ timeout: 2000 });
  // Console must be clean — silent handler throws are the most common failure.
  const errors = [];
  page.on('console', m => m.type() === 'error' && errors.push(m.text()));
  expect(errors).toEqual([]);
});
```

Run with the existing Playwright harness:

```bash
npx playwright test tmp/pre-pr-qa-<branch>.spec.js --project=smoke --reporter=list
```

Auth/storageState: reuse `e2e/fixtures/auth.setup.js`. If the new element is behind auth, mark the test with the existing auth pattern (`test.use({ storageState: '...' })`). No new auth machinery.

## What the Scenario Asserts

Each new element gets **one** assertion chain:

1. Click lands.
2. The user-visible state transition happens (class toggle, DOM update, navigation, modal open, etc.) within 2s.
3. Console is clean — no uncaught errors or warnings from the handler path.

That's it. Not a full regression spec — a binary "does clicking this button do the thing it was built to do."

## Platform Branches

If the diff touches a `Capacitor.isNativePlatform()` branch, the ephemeral spec **must** include both a web run and an iOS-stubbed run (`addInitScript` stubbing `window.Capacitor.isNativePlatform = () => true` before boot). Single-platform pass is insufficient — `#621` shipped with a working web path and a broken iOS path.

Reference the stub pattern in `conventions/e2e-test-conventions.md` § Keep What's Valuable.

## Integration With Existing Pre-PR Agent

Update `rules/hooks-and-agents.md` § Pre-PR Validation Agent:

- Static wiring check (current): grep the diff for handlers. Pass/fail per element.
- **Browser-QA gate (new):** for each element that passed the static check, write an ephemeral scenario, run it headless, assert the click → state → clean-console chain.
- Blocking comment on failure: `"BROWSER-QA FAILED: clicking <element> at <file>:<line> produced <failure>. Screenshot: tmp/pre-pr-qa-<branch>-<timestamp>.png. Fix the handler or confirm the element is a placeholder."`
- Same escape hatch as the static check: PR description containing `"button is a placeholder"` near the element bypasses both gates.

## Gotchas

- **vercel dev cold start** — Playwright config has a 60s server boot timeout. The ephemeral spec inherits this; expect a slow first pre-PR run on a cold cache.
- **E2e branch state** — the pre-PR gate runs against the e2e Supabase branch (same as smoke), not prod. If the new element depends on seed data that doesn't exist on the e2e branch, the scenario will false-fail. Seed via `addInitScript` or `page.evaluate`, don't mutate the e2e branch.
- **Don't promote the ephemeral spec to smoke** — resist the urge. Smoke is for permanent invariants; a one-shot wiring check is not an invariant. The diff that added the element already covers "this element exists and is wired" via the commit itself.
- **Rate limit bypass** — the gate must set `E2E_RATELIMIT_BYPASS_SECRET` the same way smoke does. Otherwise middleware rate limits the scripted click storm.

## Non-Goals

- Not a replacement for `/ultrareview` or code review — this catches wiring, not logic bugs.
- Not a replacement for permanent smoke specs — those cover invariants; this covers the *new* delta.
- Not a general-purpose "test every click in the app" — only new interactive elements in the current diff.

## Open Questions

- **Agent vs local script?** First pass: run as part of the background Pre-PR Validation Agent (existing pattern in `rules/hooks-and-agents.md`). Agent model = `haiku` — diff-grep + template-fill + playwright invocation is mechanical. Upgrade to `sonnet` only if haiku produces flaky scenarios.
- **What counts as "state transition"?** Current proposal: visible DOM change within 2s. Too loose catches too little; too strict false-fails on async flows. Iterate on the assertion shape after first 2–3 real runs.
