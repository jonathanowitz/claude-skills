# Debug

Diagnose and fix a bug using instrument-first debugging. This skill enforces the sequence mechanically — no theorizing until instrumentation data is in hand.

**Input:** A description of the failing behavior (test output, error message, symptom).

---

## Step 1: Describe the Symptom

State clearly:
- **What failed:** (test name, user action, error message)
- **What was expected:** (the correct behavior)
- **What actually happened:** (the observed behavior)

Do NOT read code, form hypotheses, or spawn research agents yet. Just state the facts from the error output.

---

## Step 2: Instrument (MANDATORY FIRST)

This is a hard gate. You MUST add instrumentation before doing anything else. No reading source code to "understand the flow." No hypothesis generation. No Gemini. No explore agents.

Choose the right instrumentation for the context:

### For failing e2e tests:
Add a diagnostic dump to the test that captures actual DOM/app state at failure time:
```javascript
// In the test, wrap the failing assertion:
try {
  await expect(locator).toBeVisible({ timeout: 10000 });
} catch (e) {
  const state = await page.evaluate(() => ({
    // Capture the 3-5 values most likely to explain the failure
    elementClass: document.querySelector('#target')?.className,
    elementText: document.querySelector('#target')?.textContent?.slice(0, 100),
    errorText: document.querySelector('.error')?.textContent,
    appReady: document.body.dataset.appReady,
    // Add context-specific values
  }));
  console.log('=== DIAGNOSTIC ===', JSON.stringify(state, null, 2));
  throw e;
}
```

### For failing unit tests:
Add `console.log` of actual values at the failure point. Capture inputs AND outputs.

### For API/backend bugs:
`curl` the endpoint and log the full response (status, headers, body).

### For state bugs (localStorage, DB, etc.):
Add a proxy/interceptor per the e2e conventions (localStorage proxy via `addInitScript`).

**Run the test with instrumentation and read the output before proceeding.**

---

## Step 3: Read the Instrument Output

Report what the instrumentation revealed. State:
- **What the actual values were** (from the diagnostic dump)
- **Which value is wrong** (compared to expected)
- **What this rules out** (which hypotheses are now impossible)

This step often reveals the root cause immediately. If it does, go to Step 5.

---

## Step 4: Hypothesize and Test (max 2 cycles)

Now you may form ONE hypothesis based on the instrument data. Not based on code reading — based on what the instrument told you.

- State the hypothesis
- State what you'll change to test it
- Make the change and run the test

If hypothesis 1 fails:
- State why it was wrong (what the test output showed)
- Form hypothesis 2 from the NEW data
- Test it

**After 2 failed hypotheses: STOP.** Run `/second-opinion` with:
- The original symptom
- The instrumentation output
- Both failed hypotheses and why they were wrong

Do not attempt hypothesis 3 solo.

---

## Step 5: Fix and Verify

Apply the fix. Then:
1. Run the failing test — confirm GREEN
2. Run the full spec file — confirm no regressions
3. Remove diagnostic instrumentation code
4. Commit with issue reference

---

## Anti-Patterns This Skill Prevents

- Reading 5 source files to "understand the flow" before testing
- Spawning explore agents or Gemini before having instrument data
- Forming hypotheses from code reading instead of runtime state
- Serial theorizing through 3+ hypotheses without escalating
- Fixing based on what the code "should" do instead of what it actually does
