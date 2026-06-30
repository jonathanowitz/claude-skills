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
