# Test Plan Conventions

## A human walk contains ONLY what a machine structurally cannot check (HARD RULE)

Before a line goes into a walk or preview doc, ask: **could an automated test assert this?** If yes, it does not go in the doc — no matter how important it is. Cite the test instead.

USER's time is the scarcest input to the project. Asking him to hand-verify a checkbox that `deck.spec.js` already drives is asking him to be a slower, less reliable test runner. It also buries the handful of items that genuinely need him.

What belongs in a walk, and essentially nothing else:

- **Perception** — is the ramp visible, is the animation too fast, is the copy readable at a glance, is the element still on screen when it matters.
- **Ergonomics** — is the control thumb-reachable, does the card feel attached to the cursor.
- **Judgment** — is two clicks enough protection, is this notice reassuring or alarming, is this wording right.
- **Guards the suite structurally cannot reach** — a secure-context throw under Playwright's `http://localhost`, a rule enforced in CSS before the JS branch runs. Name these explicitly as unreachable, and pair them with a mutation check rather than a checkbox.

What never belongs: any assertion about counters, state transitions, error text, storage contents, resume behavior, or refusal of bad input. Those are tests. If one isn't yet, write the test — don't delegate it to USER.

Format follows: **no checkboxes for machine-checkable facts.** A walk is a short list of questions, each with the context needed to answer it, and a closing pointer to the suite that covers everything else. Ten minutes of walking should be ten minutes of judgment, not thirty checkboxes and six questions.

**Evidence:** 2026-07-10, decidr Slice 1 (PR #6). The walk doc opened by declaring "everything below has been executed by a machine — you are checking the parts a machine cannot see," then listed ~30 checkboxes, of which sections 1, 4, 5 and 7 were line-for-line restatements of `deck.spec.js`, `resume.spec.js` and `errors.spec.js`. Every §5 item had a named e2e test driving a real browser. USER stopped partway: *"you put too much stuff in there i don't care about. If you're testing mechanically and can verify/validate, I don't need to manually verify every single thing."* He wrote in the margin of §5: *"I don't want to do all this, can you just prove it works this way somehow."* Both real findings he did produce — witzcraft/decidr#11 and #12 — came from **Judge:** prompts, not from a single checkbox.

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
