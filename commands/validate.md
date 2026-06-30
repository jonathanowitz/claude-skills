---
description: Generate a validation checklist + browser console script for the most recent changes
argument-hint: [optional focus area]
---

# Generate Validation Script

Generate two validation artifacts for the work just completed in this session. Use conversation context to determine what was built/changed.

If $ARGUMENTS is provided, narrow the validation scope to that area.

## 1. Gather Context

Review the current conversation to identify:
- What files were modified and why
- What the acceptance criteria are (from plan file, task list, or discussion)
- What UI elements, API endpoints, and data flows were affected
- What the user would need to manually verify in a browser

Do NOT re-read files or do additional exploration. Use what's already in context.

## 2. Determine Output Location

Check the current working directory to determine the project:
- If in an `example-*` directory (example-app, example-context, etc.) → save to `~/Projects/example-context/tmp/`
- Otherwise → save to a `tmp/` folder in the project root (create if needed)

## 3. Generate Manual Test Checklist

Create a markdown file following the test plan conventions:

**Filename:** `validate-<feature-slug>-YYYY-MM-DD.md`

**Format:**
- `- [ ] Done` checkbox at top
- Group by auth state (unauth first, then auth)
- Within groups, order for efficient walkthrough (no backtracking between views)
- Each test case uses this format:

```
### TC1: Feature Name
**Steps:**
1. Do action

**Expected:**
- [ ] Criterion 1
- [ ] Criterion 2

**Comments:**

```

- Focus on what changed — don't test unrelated features
- Include edge cases: empty state, error state, refresh persistence

## 4. Generate Browser Console Script

Create a JavaScript file that can be pasted into DevTools console.

**Filename:** `validate-<feature-slug>-YYYY-MM-DD.js`

**The script should:**
- Run non-destructively (read-only checks, no mutations)
- Print a clear pass/fail summary using `console.group` and styled `console.log`
- Check three layers:
  1. **DOM:** Expected elements exist, have correct text/classes, are visible
  2. **API:** Verify recent fetch calls hit the right endpoints (intercept `fetch` or check network state)
  3. **Data integrity:** Check in-memory state (`window.currentUser`, `window.Follows`, profile data, etc.) matches what the UI shows
- Use green checkmark for pass, red X for fail
- End with a summary line: "X/Y checks passed"
- Be self-contained (no dependencies)
- Include a header comment explaining what it validates

**Example output style:**
```javascript
// Validation: Name Unification (2026-02-25)
// Paste into DevTools console on the Account page
(() => {
  let pass = 0, fail = 0;
  function check(label, condition) {
    if (condition) { console.log('%c✓ ' + label, 'color:green'); pass++; }
    else { console.log('%c✗ ' + label, 'color:red'); fail++; }
  }
  console.group('Name Unification Validation');
  // ... checks ...
  console.groupEnd();
  console.log(`\n${pass}/${pass+fail} checks passed`);
})();
```

## 5. Output

1. Write both files to the determined output location
2. Show a brief summary:

```
Validation files created:
  Checklist: <path>
  Console:   <path>

<count> test cases, <count> automated checks
```

Do not add extra commentary. Keep it quick.
