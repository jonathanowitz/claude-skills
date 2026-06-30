---
description: Debug and patch application code to satisfy failing E2E or unit tests
argument-hint: [called by /implement during verification loop — no direct args needed]
allowed-tools: [Read, Edit, Write, Grep, Glob, Bash]
user-invocable: false
---

# Implement Fix

Surgical debugging skill. Takes failing test output and patches **application code only** until the tests pass.

**This skill exists because debugging is a different cognitive mode than creation.** The `/implement-slice` and `/implement-wire` skills are designed for clean greenfield work. When tests fail after wiring, the fix often requires reading across multiple files to find a contract mismatch — a different kind of reasoning.

## Inputs

The orchestrator (`/implement`) provides:
- Failing test file path(s)
- Test error output (Playwright trace, assertion messages)
- List of source file paths modified in this implementation

## Rules

1. **NEVER modify test files.** Tests are the spec. If a test seems wrong, report it — don't fix it.
2. **Read the failing test first.** Understand what it expects — which selector, which assertion, which state.
3. **Read the relevant source files.** Focus on the contract boundary: what does the test expect vs. what does the code produce?
4. **Common failure patterns to check:**
   - Selector mismatch: test expects `.delay-indicator`, code creates `.delay-icon` → fix the code
   - Missing `data-test-*` attribute: test waits for an attribute the code doesn't set → add the attribute
   - Event not dispatched: test waits for `delayStatusChanged`, code dispatches `delay-status-changed` → fix the event name
   - Load order: component script loaded after app.js tries to use it → fix script tag order in HTML
   - Missing prop: entry-card.js doesn't receive `hallDelay` because app.js render doesn't pass it → fix the render call
   - Auth gate: test runs as authenticated user but the API call doesn't include the auth token → fix the fetch headers
5. **Make the minimum change.** Don't refactor, don't improve, don't clean up. Patch the specific mismatch.

## Process

1. Read the test error output
2. Identify the failing assertion or timeout
3. Grep the source for the expected selector/value/event
4. Find the mismatch
5. Fix it
6. Run the failing test(s) only — confirm GREEN
7. Run full unit suite — confirm no regressions

## Escalation

If the fix isn't obvious after reading the test + source:
- Run `/second-opinion` with the test file + the 2-3 most relevant source files + the error output
- Gemini is particularly good at spotting contract mismatches across files (e.g., "the test expects `hall` but the API returns `hall_name`")

## Completion Signal

Report: "Fix applied. [description of what was wrong and what changed]. Tests: N passing."
