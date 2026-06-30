# RED state must be behavioral, not import-resolution

> Tests that "fail" because `import` can't resolve the module are NOT in a valid RED state. Real RED means the assertions run and report wrong values.

## The trap

After writing tests for a not-yet-implemented module, running the suite returns a long list of failures and a satisfying RED summary line:

```
Test Files  5 failed (5)
     Tests  16 failed (16)
```

Looks like RED. Isn't. Every "failure" is `Cannot find module '/api/_lib/shared/foo.js'` — the import statement at the top of each test file crashes before any test body executes. The assertions never run. There is no evidence that the assertions are correctly written.

The danger isn't in the moment — it's downstream. When impl lands and turns the suite GREEN, the GREEN could be passing for the wrong reason (assertion typo, wrong expected value, mock that always returns truthy). You'll never know, because no failure case ever exercised the assertion logic.

## The fix: minimal stubs, then verify failure type

Before declaring tests RED, create stub modules at the canonical import paths with **empty/no-op export bodies** — just enough so the import resolves and tests load. Then run the suite. Two outcomes are valid:

1. **Test fails with an assertion-level message** (`expected X, got Y`, `expected promise to reject`, status code mismatch, etc.) — this is real RED. The assertion ran. It can distinguish working from broken impl.
2. **Test passes against the stub** — a coincidental stub-pass is a failure, not a justification. **A stub-pass demonstrates nothing: it is the same vacuity class as a skip.** Make the stub more inert until the test goes RED. The only legitimate exception is when the stub body IS the v1 final form (e.g. a stub that correctly throws "not implemented" for a test asserting "throws not implemented"). If the stub-pass is coincidental — the test passes because the stub happened to return null and the assertion was loose — the stub is doing too much or the assertion is wrong. Fix one or the other; never justify coincidental passes. (Evidence: 2026-06-10 — S0.1 /review-tests, 3 stub-passes reported as justified: null session store, children-passthrough view, default-history router all coincidentally satisfied assertions. USER: "coincidental passes are failures." Fixed by making stubs maximally inert: sentinel non-null session, placeholder-rendering view, default-history router — all 3 tests went RED.)

Any test that fails with `Cannot find module`, `TypeError: X is not a function`, or any other load-time error is **not in RED state.** Fix the stub and re-run.

## Stub template

```js
// STUB — replace with real impl. Tests should FAIL on assertions against this.
export async function someFunction() {
  return null;
}

export default async function handler(req, res) {
  return res.status(501).json({ error: 'not implemented' });
}
```

For API handlers, return 501 (Not Implemented) — most tests expect 200/400/etc and will fail loudly. For pure functions, return `null` / empty objects / non-throwing — tests asserting throws will fail, tests asserting values will see `null` vs `expected`.

**Mark stubs explicitly** with a `// STUB` comment on line 1. This is the signal to the impl agent that the file needs full replacement.

## Self-validation checklist

Before declaring `/review-tests` Stage 5 complete:

- [ ] Stub modules exist at every import path referenced by the test files
- [ ] Test suite runs (no top-level crashes)
- [ ] Failure messages cite assertions (`expected X to be Y`, `expected promise to reject`), not module resolution
- [ ] Count: N tests fail on assertions, M tests pass against stub (M should be 0 for any correctly inert stub; each M must be a genuine v1-final-form case — "stub body IS the correct v1 impl" — never a coincidental pass)
- [ ] Zero tests fail on imports
- [ ] `tsc --noEmit` passes on the new test + stub files (every project they live in — app AND api). Vitest's esbuild strips types without checking them, so a clean behavioral RED can still hide type/build errors. See "Extension: a behavioral RED is still type-blind" below.

If any test fails on imports, the stub surface is incomplete. Add the missing export and re-run.

## Why this keeps happening

The fail summary line in vitest/jest output doesn't distinguish failure types. A 16-failure run from missing imports looks identical at a glance to a 16-failure run from real assertion errors. The pattern relies on visually checking every error message for assertion-shape vs import-resolution-shape — which is exactly the kind of detail that gets skipped under time pressure.

## Evidence

- 2026-05-19 — #795 Slice 2 affiliate payout. I declared tests RED with 16 module-resolution failures. USER: "we go through this every single time. 'cannot find module' is not a valid test fail, it's vacuous." Added 6 stubs → re-ran → 72 behavioral failures + 1 legitimate pass (paypal stub's "not implemented" test passes against the v1 stub-form impl). The corrected RED is a completely different signal: 4.5x more tests exercising assertions, and one explicit legitimate pass to justify.

## Extension: integration / DB tests that can't run at review time

The stub-RED method above assumes the test *runs locally*. A whole class doesn't: DB-integration tests gated on `TEST_SUPABASE_URL`, e2e tests gated on `TEST_BASE_URL`, anything wrapped in `conditionalDescribe = HAS_X ? describe : describe.skip`. When the resource is absent these don't fail or pass — they **skip**. A skipped test is the most dangerous state of all, because the unit-RED checklist above ("zero tests fail on imports") is *trivially satisfied* by skipped tests. They parse, they're cross-model reviewed, the gate clears on the unit tests' RED — and the integration tests sail through having **demonstrated nothing.** A test that has only ever skipped is unvalidated scaffolding: it could be vacuous, mis-asserted, or pass against a broken schema, and you have zero evidence either way.

**The principle is unchanged; the "stub" is different.** For a migration test the RED-producing "stub" is the schema in its **un-migrated or deliberately-incomplete state.** For an API integration test it's the endpoint not yet deployed. RED has to come from running against a real resource where the asserted thing is *absent*.

**GREEN-only is the vacuous-pass trap at the integration layer.** "I'll apply the migration and run the suite green" proves nothing — a test that always passes is also green. You must see it RED *first*, for the right reason.

### Two-gate structure for these tests

**Gate 1 — review time (`/review-tests`):** review the integration-test *logic* (mocks, assertions, cleanup) and **catalogue every conditionally-skipped test explicitly as `validation-deferred`, naming the resource it needs.** Do NOT count them toward behavioral-RED clearance. Only unit/pure tests with stub-RED clear Gate 1. The review file must state plainly: "N tests are unvalidated until Gate 2."

**Gate 2 — pre-PR (hard, blocks merge):** the deferred tests must run **RED → GREEN against the real resource**, with a non-vacuousness check:
1. **RED-baseline:** run against the un/incompletely-provisioned resource (migration not applied / endpoint absent). A `relation does not exist` failure is the weak floor — it proves the test references the real object but is the integration-layer equivalent of `Cannot find module`, so it is *not* sufficient alone.
2. **GREEN:** apply the correct migration / deploy → tests pass.
3. **Mutation check (the part that actually matters):** for the highest-risk assertions — CHECK/FK/UNIQUE constraints, RLS policies, seed counts/ordering — break **one** thing in the migration (seed 17 not 18; drop one CHECK; skip one `ENABLE ROW LEVEL SECURITY`), re-run, confirm **only the matching test flips red**, then restore. This proves each test fails for its own reason rather than passing by accident. Without it you have GREEN, not validation.

No PR/merge until Gate 2 is green *with a demonstrated RED*. "Tests written + reviewed + parsing" is not "tests known to work."

### Evidence (integration extension)

- 2026-05-31 — #831 Slice 1a bookkeeping. 27 DB-integration tests written, cross-model reviewed twice, parsing cleanly — but only ever **skipped** locally (no `TEST_SUPABASE_URL`). Gate cleared on the 8 unit tests' RED. USER: *"how do you know the db tests are useful if you have nothing to test them against to show red?"* Correct — unvalidated scaffolding. Fix: the migration-not-applied state is their stub; validate via RED→GREEN+mutation against the test branch before PR. This extension exists so a skip is never again mistaken for a pass.

## Extension: a behavioral RED is still type-blind

Even a properly behavioral RED — assertions running, stub-passes eliminated — proves nothing about whether the test/stub files *compile*. `pnpm test` runs vitest, which transforms via esbuild, and **esbuild strips types without checking them.** So the test-setup phase can write approved test files + stubs, confirm a clean behavioral RED, and *simultaneously* introduce type errors (and the esbuild bundle breaks they cause) that are completely invisible until someone runs `tsc --noEmit` or `pnpm build` by hand.

**RED-confirmation must also typecheck.** Before declaring tests RED (and clearing `/review-tests`), run `tsc --noEmit` for every project the new files live in — app AND api — plus, for esbuild-bundled handlers, the bundle build. A type error caught the day the test is written is a one-line fix; the same error found days later at implementation is a debugging detour, and if it reaches `main` it breaks the Vercel deploy (whose buildCommand runs `tsc && vite build` and the api bundle step).

This is the type-layer twin of the integration extension above: "the test ran and failed an assertion" is necessary but not sufficient — it also has to *compile*.

### Evidence (type-blind extension)

- 2026-06-22 — #926 S3a.1 find-my-team. The approved test-setup confirmed a clean behavioral RED (24 assertion failures, 0 stub-passes) but had silently shipped THREE type errors invisible to vitest: a `ProgramTeamSchema` barrel name-clash (TS2308 + esbuild bundle break), a `delete`-cast TS2790 that broke `app build` → the Vercel deploy, and a stray `@ts-expect-error` (TS2578) breaking `typecheck:api`. All three only surfaced when the implementer ran `tsc`/`build` manually mid-implementation. Fix: #930 added a `tsc --noEmit` (app + api) step to the pr-gate as a backstop; the upstream lever is running the typecheck as part of RED-confirmation so it lands at test-writing time, not implementation time.

## See also

- `~/.claude/commands/review-tests.md` § Stage 5 — has fields for "Tests passing against stub" / "Tests failing against stub" but doesn't enforce stub creation as a hard precondition
- `~/Projects/dev-reference/workflows/self-validation-protocol.md` — general principle that "the test ran" ≠ "the test is correct"

## Corollary — "green in the red state" is vacuous (a test must FLIP)

A test that PASSES against the pre-impl baseline documents no change. USER,
2026-06-11 (S1.0b spine review): *"I fundamentally don't understand how a pass in
the red state could be considered benign — it means it will never be red and is
therefore not actually documenting a change in state."* "Benign green-in-red" is
the same vacuous-pass trap as a skip.

Two forms, both caught on S1.0b:
1. **Forever-green precondition** — asserting something the BASE state already
   satisfies (the admin email was already in `seed.sql` before the slice). It can
   never flip → delete it; this slice's seed adds nothing there.
2. **Wrong-reason green** — passes for an incidental reason that also holds pre-impl.
   An anon-INSERT-rejected RLS probe passed because a *missing table* errors, not
   because grants were REVOKED → stayed green across the migration. Fix: assert the
   DENIAL MECHANISM (Postgres `42501` / "row-level security") AND explicitly reject
   the missing-table error (PostgREST `PGRST205` "could not find the table"). Now
   RED pre-impl (missing table), GREEN post-impl (REVOKE). For any security probe,
   assert the deny code — never bare `error !== null`.

**Check:** at RED-baseline, EVERY test must fail on an assertion. Any test green
pre-impl is either a precondition you don't own (remove) or accepts an incidental
error (tighten to the specific mechanism the change introduces).
