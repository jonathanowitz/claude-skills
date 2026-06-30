---
description: Decompose a shaped brief into an atomic implementation plan with vertical slices
argument-hint: <path to shaped brief>
allowed-tools: [Read, Grep, Glob, Bash, Write, Agent, AskUserQuestion]
---

# Implementation Plan

Decompose a shaped brief into an atomic, phase-by-phase implementation plan.

**Input:** A shaped, approved brief at $ARGUMENTS (or prompt USER to specify one).

**Output:** `tmp/implement-plan-<feature>.md` — a file that `/implement` reads to execute autonomously.

## Prerequisites

Before starting, verify:
1. The brief exists and has `Status: Shaped — approved` (or equivalent)
2. A pre-mortem has been run on the brief (check for pre-mortem file or section)
3. If either is missing, stop and tell USER what's needed first

## Step 1: Read the Brief

Read the full brief. Extract:
- **Database changes** — tables, indexes, RLS policies, migrations
- **API endpoints** — routes, request/response shapes, auth requirements
- **New frontend modules** — IIFEs, components, their public API surfaces
- **Modified files** — which existing files change and how
- **Verification section** — what tests the brief specifies

## Step 2: Read Codebase Patterns

Read existing code to understand patterns the implementation must follow. At minimum:
- One existing API handler (for handler pattern, error shape, auth usage)
- The API router file (for route wiring pattern)
- One existing IIFE component (for window.* export pattern)
- The existing test files in the same directories where new tests will go
- `app.html` (for script load order)
- `CODEBASE-MAP.md` if it exists

Report what patterns Claude found in 3-5 bullet points.

## Step 3: Decompose into Phases

Build the phase breakdown following this structure:

### Phase 0: Foundation (always present)
- Migration files (DDL — no tests needed)
- Stub files with JSDoc signatures and empty/501 implementations
- Route wiring for stubs
- Any bug fixes bundled in the brief
- **Gate:** run full test suite, confirm no regressions

### Vertical Slices (one per logical layer)
For each slice:
- **Name** and what it covers
- **RED:** which test files to write, what they assert, expected failure pattern
- **GREEN:** which files to implement
- **Gate:** run targeted tests (GREEN), then full suite (no regressions)

Typical slice ordering:
1. Backend (API handlers)
2. Client logic modules (new IIFEs — polling, state, reporting)
3. Pure function changes (filters, utils)

### Integration Phase
- Modifications to existing complex files (app.js, entry-card.js)
- HTML script tags, CSS styles
- **Gate:** full test suite

### E2E Phase
- E2E spec files
- Use route interception to mock API responses where needed
- **Gate:** unit suite still green

### Ship Phase
- Stage, commit, push, create PR

## Step 4: Map Dependencies

For each phase, list:
- What it depends on (which prior phases must be complete)
- What context the implementer needs from prior phases (specific function signatures, API contracts, etc.)

## Step 5: Write Test-Ready Behavior Map Entries

This is the critical output that enables autonomous test generation. For each user-facing behavior in the feature, write a behavior map entry at this level of detail:

```markdown
#### 32.1 "Performing Now" Button [web] [untested]
- **Trigger:** User taps `[data-test="performing-now-btn"]` inside expanded `.entry-card.entry-past`
- **Preconditions:** Card expanded, entry has class `.entry-past`, user authenticated
- **API call:** POST `/api/v1/delay-report` with `{ competition_id, schedule_entry_id }`
- **Success (200):** Button gets class `.reported`, text becomes "✓ Reported", disabled=true. Toast contains "Delay reported for Hall"
- **Duplicate (409):** Same as success — button shows reported state
- **Unauth (401):** Sign-in prompt shown (`.auth-modal` visible)
- **Already reported (client):** Button renders with `.reported` class and disabled on initial render. No API call.
```

Each entry must include:
- **Trigger** — what the user does, with the exact `data-test-*` selector
- **Preconditions** — DOM state and auth state required (CSS classes, attributes)
- **API call** (if any) — method, URL, request body shape
- **Expected outcomes** — exact DOM changes (class additions, text content, visibility) for each response code
- **Edge cases** — what happens on error, duplicate, or missing precondition

These entries serve two purposes:
1. USER reviews them as the behavior spec (plain English, no Playwright syntax)
2. `/implement-e2e` mechanically translates each one into test cases

Write entries for both E2E-testable behaviors (UI interactions) and unit-testable behaviors (API handlers, filter logic, polling). Group by the slice they belong to.

## Step 6: Get a Second Opinion

Run `/second-opinion` on the plan. Use the architecture role prime and ask Gemini to review:
- Are stubs sufficient for meaningful RED tests?
- Are any tasks still too large for one pass?
- Are dependencies between phases correctly identified?
- Are behavior map entries specific enough for mechanical test generation?
- What implementation risks does this decomposition create?

Incorporate findings into the plan.

## Step 7: Write the Plan File

Write `tmp/implement-plan-<feature>.md` with this structure:

```markdown
# Implementation Plan — <Feature Name>

**Brief:** <path to brief>
**Date:** YYYY-MM-DD
**Phases:** N
**Estimated slices:** N

## Pre-autonomy: USER applies migration
- Migration file: `supabase/migrations/<timestamp>_<name>.sql`
- Command: `supabase db push` (or apply to e2e branch)

## Phase 0: Foundation (Stubs)
- [ ] <stub file>: <what it exports>
- [ ] <route wiring>
- [ ] <bug fixes>
- Gate: full suite green, no regressions

## Behavior Map Entries (Test-Ready)

### E2E Behaviors
#### N.1 <Behavior name> [web] [untested]
- **Trigger:** <user action + `data-test-*` selector>
- **Preconditions:** <DOM state, auth state>
- **API call:** <method, URL, body shape>
- **Success:** <exact DOM changes — classes, text, visibility>
- **Error states:** <each error code + expected UI response>

#### N.2 ...

### Unit-Testable Behaviors
#### N.X <Handler/module name>
- **Input:** <params/body shape>
- **Logic:** <what it computes>
- **Output:** <response shape or return value>
- **Edge cases:** <boundary conditions, error codes>

## E2E Spec Files (generated from behavior map)
- [ ] `e2e/<feature>.spec.js`: covers behaviors N.1, N.2, N.3
- [ ] `e2e/<feature>-display.spec.js`: covers behaviors N.4, N.5

## Slice 1: <Name>
### RED
- File: <test file path>
- Asserts: <what the tests check, referencing behavior map entries>
- Expected failure: <behavioral, not structural>
### GREEN
- File: <implementation file path>
- Changes: <what to implement>
- Gate: targeted tests green, full suite green

## Slice 2: <Name>
...

## Integration
- [ ] <file>: <what changes>
- Gate: full suite green, E2E specs turning GREEN

## Ship
- Commit message template
- PR description template

## Gemini Review Findings
- <finding and resolution>

## Context for /implement
<Codebase-specific notes — patterns, gotchas, load order constraints>
```

## Step 8: Present to USER

Show the plan summary (phases, slice count, behavior map entry count) and ask for approval. Highlight:
- **The behavior map entries** — these ARE the test spec. USER should review them for correctness and completeness. Each entry becomes one or more E2E/unit test cases during autonomous execution.
- Anything where Claude made a judgment call
- Anything Gemini flagged as a risk

**After approval:** USER applies the migration to the database, then runs `/implement` to kick off autonomous execution. Everything from stubs through PR is autonomous.

**Do NOT start implementation.** The plan is the deliverable. `/implement` is a separate step.
