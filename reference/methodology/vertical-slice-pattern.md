# Vertical Slice Architecture Pattern

For multi-day projects, use vertical slices to maintain momentum and testability.

See also: `conventions/build-project-principles.md` for slice ordering and what to defer.

## When to Use
- Projects spanning 3+ sessions
- Features with multiple independent components
- When parallel work is possible

## Process

### 1. Create `build-slices.md` Before Building
Define all slices upfront with:
- Slice name and purpose
- Files to create
- Dependencies on other slices
- Test coverage expectations
- Acceptance criteria

### 2. Slice Principles
- Each slice is independently testable — **"independently testable" means the feature works for a user, not just that the code compiles.** A slice includes: implementation, integration wiring into the app, and one full user-path test. Library code that passes unit tests but isn't wired into the app is not a completed slice.
- Slices should be small enough to complete in one session
- Identify which slices can be built in parallel
- Integration slice comes last

### 3. Per-Slice Deliverables
- Implementation code
- Unit tests (aim for high coverage)
- Narrative test report explaining what tests validate in plain language

### 4. Narrative Test Reports
Create `tests/reports/slice-N-name-report.md` for each slice:
- Explain what the component does
- Describe what each test validates (not just "test passed")
- Document edge cases and why they matter
- These serve as documentation and validation

## Completeness Backstop — build plans need a BACKWARD pass (not just forward decomposition)

A slice plan built *forward* from domain regions / architecture will leave coverage holes. Building forward answers "what's the next chunk to build?" — it never answers "is every surface the product needs actually assigned to a slice?" Those are different questions, and only the second one catches misses.

**Rule 1 — Run an explicit backward pass against the full surface/feature inventory before calling a build plan done.** Every item in the inventory must map to exactly one of: SHIPPED / ASSIGNED-to-slice-N / DROPPED-with-reason / DESIGN-LOCKED-but-needs-a-slice. Anything with no mapping is a hole. Keep this as a living parity-coverage tracker and make "check off your rows" a slice close-out step (alongside the narrative test report).

**Rule 2 — "design-locked" ≠ "has a build slice." Track them separately.** A region/ledger can fully specify a surface's design while no slice builds it. If you only track design-completeness, it masquerades as build-completeness and the gap stays invisible. The backward pass keys on *build* status, not *design* status.

**Rule 3 — When you split a planned slice into sub-slices during execution, re-verify the union still covers the parent's promised scope.** Decomposition is where scope silently evaporates: Slice N promised {A, B, C}; it ships as Na + Nb covering {A, B}; C disappears with nothing flagging it. Do a coverage re-check at every decomposition, not just at plan time.

**Rule 4 — Cross-cutting NON-visual parity is what a forward plan forgets first.** Analytics/instrumentation, error tracking, PII-sanitizing wrappers, feature-flag/telemetry hooks — none of these are a "surface" you'd naturally decompose into, so they fall off a features-first plan. Put them on the backward-pass checklist explicitly.

**Why this matters:** without the backward pass, the *core* feature can be the one that's missing — the thing so obvious nobody wrote a slice for it — and it stays missing until someone's gut flags it late.

**Evidence:**
- 2026-07-01 — Example Project rebuild. Two weeks of rigorous experience-*design* (regions R2–R11 all locked; the schedule filter-algebra even got a 107KB prove-or-kill ledger), but the design was never reconciled backward against the old-app surface inventory. The slice plan was organized by domain region + GTM priority; its one surface-inventory table (the intended completeness check) was left half-filled and marked "superseded." Then "Slice 3" (nominally *fan discovery + filter/search + example*) was executed as S3a (find-my-team-follow) + S3b (your-world home) and the **filter/search + example** portion — the product's core fan surface and literal namesake — evaporated with no build slice, undetected across 8 shipped slices until USER's instinct flagged it. Same audit found instrumentation parity (PostHog/telemetry, AS-4-mandated) absent from all 8 slices. Fix = a parity-coverage audit reconciling all 24 surfaces; adopted as a living backstop. (example-app #999/#1000/#1001; `example-context/architecture/rebuild-parity-coverage-audit.md`.)

## Example Structure

```
project/
├── build-slices.md              # Slice plan (create first)
├── src/
│   ├── component1/              # Slice 1
│   ├── component2/              # Slice 2
│   └── ...
└── tests/
    ├── test_component1.py
    ├── test_component2.py
    └── reports/
        ├── slice1-component1-report.md
        └── slice2-component2-report.md
```
