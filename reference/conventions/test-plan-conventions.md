# Test Plan Conventions

## Structure

1. **Group by auth state** — Put all unauthenticated tests first, then authenticated tests. This minimizes sign-in/sign-out cycles during manual testing.
   - Unauthenticated flows
   - Authenticated flows (empty state / new user)
   - Authenticated flows (with data)

2. **Within auth groups, organize by feature area** — Group related test cases together (e.g., all visual checks, all interaction tests, all edge cases).

3. **Order for efficient walkthrough** — Arrange tests so the tester can move through them sequentially without backtracking between views or states.

## Per-Test-Case Format

```markdown
### TC1: Feature Name
**Steps:**
1. Do action

**Expected:**
- [ ] Criterion 1 happens
- [ ] Criterion 2 visible

**Comments:**

```

- Each expected criterion gets its own checkbox
- Add a "Comments:" section after each test case
- No underscores or brackets as placeholders

## File Conventions

- Test plans go in `tmp/` (gitignored)
- Add `- [ ] Done` checkbox at the top
- Include a `**Login:**` line with e2e test account credentials (email + password) so the tester doesn't have to look them up
- Name: `test-plan-<feature>.md`

## Interaction-gate assertions — pair every negative with a positive (HARD RULE)

A guard / failure / blocked branch of an interactive element must assert the **user-visible positive**, not just the absent negative. A test asserting only `not.toHaveBeenCalled()` / "no navigation" / "no mutation" is satisfied **equally by the correct behavior AND by a silent dead button** — it proves the wrong thing didn't happen, never that the user knows what did.

When testing any interactive element, enumerate FOUR branches, each with a user-visible-state assertion:
- **success** → the expected transition renders
- **transport failure** → an error is shown (never silently swallowed)
- **validation-blocked** (gate not satisfied) → the user is TOLD why (not a no-op)
- **in-flight** → a busy/disabled state

"Wired" is not done until all four produce a visible change. A button with no press/feedback state reads as broken on tap — use the project's shadcn `Button` primitive so hover/focus/`active:` press aren't hand-omitted.

**Evidence:** S2a.2 (#886) shipped two perceived dead buttons in one slice — a `catch`-less submit that swallowed a 400, and a silent attestation no-op. Both passed CI because the specs asserted only the negative ("transport not called", happy-path only); both were caught by the human on the preview walk, not by the suite. This is the skips-are-red principle ("a test that didn't fail-then-pass proved nothing; pair every negative with a positive") applied to UI interaction. Proposed enforcement: a `/review-tests` check flagging negative-only interaction assertions.
