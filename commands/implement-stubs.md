---
description: Create migration, stub files, route wiring, and bug fixes (Phase 0 of /implement)
argument-hint: [called by /implement — no direct args needed]
allowed-tools: [Read, Edit, Write, Grep, Glob, Bash]
user-invocable: false
---

# Implement Stubs (Phase 0)

Create the foundation that enables meaningful RED tests in subsequent phases. This phase produces no testable behavior — it creates the skeleton that test files can import without structural errors.

## What This Phase Produces

1. **Migration file(s)** — DDL from the brief's database section. Exact SQL, no interpretation needed. **Note:** Migrations should be applied to the database (e.g., `supabase db push`) BEFORE running `/implement`. This is USER's responsibility as a pre-step, not automated by the pipeline.

2. **Stub API handlers** — One file per endpoint. Each:
   - Has the correct imports (`requireUser`, `createServiceClient`, etc.)
   - Has a JSDoc comment documenting the full API contract (request shape, response shape, error codes)
   - Returns `501 Not Implemented` for all requests
   - Is wired into the API router (`api/v1/[...path].js`)

3. **Stub IIFE components** — One file per new frontend module. Each:
   - Has a JSDoc comment documenting the full public API (function signatures, return types, events dispatched)
   - Assigns to `window.<ModuleName>`
   - Exports all public functions with minimal stub behavior:
     - Functions that return data: return the correct type but empty/default (empty Map, null, false)
     - Functions that perform actions: no-op (empty body)
     - **API handlers return 501** (not default values) so tests fail with "expected 200, got 501"
   - Will be loaded via `<script defer>` tag (do NOT add the tag yet — that's the wire phase)
   - **Add `data-test-*` attributes** to the JSDoc for any DOM elements the component will create — these become the E2E selector contract

4. **Bug fixes** — Any bug fixes bundled in the brief that are simple enough to do now (1-3 line changes to existing files). These clear the path for the main implementation.

5. **Dead code removal** — Any deprecated code the brief identifies for removal.

## Process

1. Read the plan file for Phase 0 tasks
2. Read existing patterns:
   - One existing handler for import/export pattern
   - One existing IIFE component for window.* pattern
   - The API router for route wiring pattern
3. Create each file
4. For bug fixes: read the specific lines, make the change, grep to verify
5. Run full test suite — must match baseline count with zero regressions

## Quality Checks

- Every stub file must be importable without errors (verify with a quick `import` in the test runner if unsure)
- JSDoc contracts must match the brief exactly — downstream test writers will use these as their spec
- Bug fixes must be verified by reading back the changed lines
- No `console.log` debug statements

## Completion Signal

Report: "Phase 0 complete. N files created, N files modified. Suite: X tests passing."
