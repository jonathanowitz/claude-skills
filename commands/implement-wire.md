---
description: Integration wiring — modify existing files, add script tags, write CSS (Integration phase of /implement)
argument-hint: [called by /implement — no direct args needed]
allowed-tools: [Read, Edit, Write, Grep, Glob, Bash]
user-invocable: false
---

# Implement Wire (Integration Phase)

Wire the new modules built in prior slices into the existing application. This is the phase that requires holding the full picture — it modifies existing complex files where new code must interleave with existing logic.

## Why This Phase Exists Separately

New modules (handlers, IIFEs) are self-contained files. But the app only works when they're connected:
- `app.html` needs `<script>` tags in the right load order
- `app.js` needs to call the new modules, pass them data, and handle their events
- `entry-card.js` needs new props and conditional rendering
- `style.css` needs styles for new DOM elements
- Existing functions may need refactoring to accept new parameters

This work touches the app's most complex files and can't be parallelized or delegated safely.

## Process

### 1. Read What Was Actually Built

Read every file created in prior phases. Note:
- Exact `window.*` names and function signatures
- Events dispatched (event name, detail shape)
- DOM elements created (class names, IDs, data attributes)
- API contracts (request/response shapes)

Do NOT use the brief or plan — use the actual code.

### 2. HTML Script Tags

Read `app.html`. Add `<script defer>` tags for new component files. Placement rules:
- After the components they depend on
- Before `app.js` (which orchestrates everything)
- Check the existing load order for the right insertion point

### 3. CSS Styles

Write styles for all new DOM elements. Read the existing `style.css` for:
- Design token usage (`var(--token-name)`)
- Naming conventions (BEM, flat classes, etc.)
- Media query breakpoints
- Existing patterns for similar UI (buttons, badges, overlays)

Group new CSS logically with a section comment.

### 4. Modify Existing Files

For each existing file that needs changes:

1. **Read the full function** being modified (not just the line)
2. **Understand the control flow** — what happens before and after the change point
3. **Make the minimum change** — don't refactor surrounding code unless the plan specifically calls for it
4. **Grep for all call sites** if changing a function signature — update every caller

Common wiring tasks:
- Pass new props to component `.create()` calls
- Add event listeners for new custom events
- Start/stop module lifecycle on view changes
- Expose state for other modules (`window._currentCompetitionId`, etc.)
- Refactor parameter objects to include new fields

### 5. Self-Validation

After all changes:
- Read back every modified file section
- Grep for the new module names to confirm they're referenced correctly
- Verify no orphaned references to old code remain
- Run the full test suite

## Quality Checks

- No `console.log` debug statements in production code
- All CSS uses existing design tokens where applicable (don't hardcode colors)
- Script tags are in the correct load order
- Event listeners are cleaned up on view change (no leaks)
- Existing test suite passes with zero regressions

## Completion Signal

Report: "Integration complete. N files modified. Suite: X tests passing. New DOM elements: [list class names]."
