---
description: Generate E2E test specs from behavior map entries — mechanical translation, called by /implement
argument-hint: [called by /implement — no direct args needed]
allowed-tools: [Read, Edit, Write, Grep, Glob, Bash]
user-invocable: false
---

# Implement E2E (Spec Generation — RED)

Generate Playwright E2E test specs by mechanically translating the plan's test-ready behavior map entries into test code. This runs inside `/implement`, AFTER stubs but BEFORE implementation.

**The behavior map entries are the human-reviewed spec.** USER approved them during `/implement-plan`. This skill does not make judgment calls about what to test — it translates each entry's trigger, preconditions, API call, and expected outcomes into Playwright assertions.

**E2E specs become IMMUTABLE after this phase.** All subsequent phases may only modify application code to satisfy them.

The specs will fail (RED) against stubs because the features don't exist yet. They turn GREEN after `/implement-wire` connects everything.

Use route interception to control API responses where needed (e.g., injecting mock data to test display behavior).

**Stack scope.** The selectors, `data-*` attributes, API routes, and ready-signals shown throughout this skill (`.entry-card`, `data-app-ready`, `/api/v1/*`, `?comp=`) are example-app **worked examples**. Learn the actual conventions from the repo under review — its `CLAUDE.md`, its e2e-conventions doc, and its existing test files — and translate the same *detail*, not these literal names.

## Before Writing Any Test

Follow `~/Projects/dev-reference/conventions/e2e-test-conventions.md` strictly. In particular:

1. **Verify selectors against source.** For existing elements (filter inputs, interactive cards, etc.), grep the HTML/JS to confirm. For new elements that don't exist yet (indicators, action buttons), use the class names specified in the brief's UI affordances and the stub JSDoc. These become the contract — implementation must match.

2. **Check the auth requirement.** Authenticated tests need `storageState` from the auth fixture. Use the `@auth` tag.

3. **Handle overlay suppression.** Auth setup handles standard overlays. If the test navigates without auth, add `data-test-suppress-overlays`.

4. **Wait for `data-app-ready`.** Clear it before navigation, wait for it after:
   ```javascript
   await page.evaluate(() => document.body.removeAttribute('data-app-ready'));
   await page.goto(`/?id=${SOME_ID}`);
   await page.waitForSelector('body[data-app-ready="true"]', { timeout: 30000 });
   ```

5. **Use route interception for controlled tests.** When testing display behavior that depends on API responses (e.g., indicators), intercept the API route and return mock data:
   ```javascript
   await page.route('**/api/v1/some-endpoint*', async (route) => {
     await route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({...}) });
   });
   ```

## Selector Contract: `data-test-*` Attributes

For all NEW interactive elements created by this feature, use `data-test-*` attributes as the primary E2E selector. This decouples tests from CSS class names (which may change for styling reasons) and creates a hard contract between the E2E spec and the implementation.

```javascript
// E2E test — selects by contract attribute
const submitBtn = card.locator('[data-test="submit-btn"]');

// Implementation must add: data-test="submit-btn"
```

For existing elements (existing class names or IDs), continue using the existing selectors — don't refactor them.

The `data-test-*` attributes used in E2E specs become part of the implementation contract. `/implement-slice` and `/implement-wire` must produce elements with matching attributes, or `/implement-fix` will catch the mismatch.

## E2E Execution

E2E specs require a running dev server. Two modes:

1. **Docker (preferred):** If Docker infrastructure is available (`docker-compose.yml` exists in the project), use `docker compose up -d` to start the dev server container, then run Playwright against it. This provides deterministic, isolated test execution.
2. **Local fallback:** If Docker is not available, note in the completion signal that E2E execution requires `vercel dev`. The specs are still the spec — they'll be validated during the verification loop or manually.

## Test Structure

Read the brief's Verification section for the E2E test list. For each spec:

1. **Use test-config.js imports** for IDs, user IDs, names — never hardcode
2. **Skip gracefully** when preconditions aren't met (e.g., preconditions not met):
   ```javascript
   if (await someCard.count() === 0) {
     test.skip(true, 'Preconditions not met at current time');
     return;
   }
   ```
3. **Intercept API calls** to verify payloads when testing reporting flows
4. **Test the three scenarios** where applicable: happy path, error state, recovery

## Spec File Naming

- `e2e/<feature>.spec.js` for the main feature flow
- `e2e/<feature>-display.spec.js` for display/indicator tests
- `e2e/<feature>-regression.spec.js` for bug fix regressions

## Quality Checks

- Every selector verified against actual source (grep output as evidence)
- No `waitForTimeout` for initialization (use `data-app-ready`)
- Auto-retrying assertions (`expect().toBeVisible()`) instead of one-shot checks (`isVisible()`)
- Position-based locators (`.first()`, `.nth()`) instead of state-filtered (`:not(.active)`)
- Tests import from `test-config.js`, not hardcoded values

## Completion Signal

Run the full unit test suite (not E2E — that requires a live server). Confirm no regressions.

Report: "E2E specs written. N spec files, M test cases. Unit suite: X tests passing. E2E execution requires `vercel dev` — not run in this phase."
