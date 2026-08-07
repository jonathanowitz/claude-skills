---
description: Verify a preview deploy is walkable, seed the walk fixture, and write the followable walk doc USER signs off on
argument-hint: [feature/PR description, or a path to an existing walk doc to re-answer]
allowed-tools: [Read, Edit, Write, Bash, Grep, Glob, AskUserQuestion]
---

# Walk

Produce (or update) the walk doc for: $ARGUMENTS

## Philosophy

USER validates UI work by walking it — signing in as a seeded persona on a Vercel preview and following an ordered set of steps with expected results. That walk, not green CI, is what "done" means for a slice (project principle PS-12). This has existed as a checklist bullet (pre-pr-checklist.md item 4) and gets skipped because a bullet only fires if someone remembers to read it. This skill is the fix: it fires itself.

**The goal is a doc USER can walk without hitting a wall** — a broken preview, a wrong database, a fixture CI already wiped. A walk doc that points at a dead preview costs him more than no doc at all, because he loses the time finding out it's dead. Everything in Step 1 exists to make that impossible.

## When this fires

1. **Unconditionally, unprompted, at PR-open time** — any PR that touches a user-facing surface gets a walk doc as part of opening the PR, not a later favor. If you're about to run `gh pr create` (or just did) and the diff touches UI, markup, client-side behavior, or anything USER will look at in a browser, run this skill before or immediately after — don't wait to be asked.
2. **On demand** — whenever USER asks for a walk, and whenever you're handing him a PR or a completed slice to validate. That handoff IS the trigger: don't announce it and then separately go write the doc.

   **Scoped to handoffs, not to the word "done."** Reporting that a step, a fix, or a piece of work is finished mid-session does NOT summon a walk doc — that would make ordinary progress updates expensive and train you to stop giving them. The trigger is handing over something for USER to validate, not the vocabulary you use to describe your own progress. (USER narrowed this himself, 2026-07-28: the earlier wording made every "this is ready" statement drag a full walk doc behind it.)

If a PR touches only backend/config/tests with no user-facing surface, skip and say so explicitly rather than silently omitting the doc.

## Step 1: Verify before writing a single line of the doc

Do all of these BEFORE drafting anything. A walk doc is a promise that the thing behind the link works — verify the promise first.

1. **The preview URL is live and serving the branch's HEAD.** Hit it. Confirm the deploy corresponds to the current HEAD sha, not a stale build from an earlier push (`gh pr view <N> --json statusCheckRollup` or the deployment comment on the PR; cross-check the sha).
2. **Which database the preview was built against — read it out of the bundle, not a config file.** Config files describe intent; the deployed JS bundle is what actually ships. Grep the baked `*.supabase.co` ref out of the deployed bundle at the repo's actual build-output path (example-app's Vite build emits `/app2/assets/index-*.js`):
   ```bash
   curl -s <preview-url>/app2/assets/index-*.js | grep -oE 'https://[a-z0-9]+\.supabase\.co'
   ```
   Substitute the current repo's own bundle path if it differs. Record the resolved project ref in the doc's header — this is the thing that's actually load-bearing, not "should be the e2e branch."
3. **Any migration the feature needs is applied to THAT database.** `supabase migration list` against the resolved project ref; local list must match remote. Don't assume "I wrote the migration" means "it's applied where the preview points."
4. **The walk account authenticates against that database.** Sign in as the walk account you're about to hand over and confirm the session establishes — not just that the row exists in a table.
5. **The critical path itself works — traverse it yourself at the delivered layer.** Verifying ingredients (DB reachable, migration applied, seed rows present) is NOT verifying the transaction. Actually click/tap through the flow you're about to hand USER, on the preview, as the walk account, before writing the doc that tells him to do the same. If step 5 fails, none of steps 1-4 passing matters — fix it or don't ship the doc yet.

If any of 1-5 fails, stop and fix it (or escalate) before writing the doc. Do not write "should work" language around a step you haven't verified.

## Step 2: Seed the fixture into the durable refresh — never leave a fragment

Automated specs tear their own fixtures down (`afterAll`/`wipeState`) — that's correct for them and useless for a walk. Running a spec seeds nothing walkable. But a standalone seed script whose rows you "leave in place" is just as useless: the shared e2e branch is **wiped and rebuilt on every refresh** (every Preview Tests run, the daily cron), so anything merely left sitting there is gone the next run. Durability comes from being **re-seeded from clean**, not from surviving untouched. So:

- **The fixture DATA lives in the durable refresh seed, not only a one-off script.** Put a `seedXxxFixture(supabase)` in `e2e/lib/refreshE2EData` (called *after* the wipe, rebuilt from clean each run) — the SAME rule as any test fixture (e2e-test-conventions § Seed Data). **Never** make the fixture survive by exempting its ids from the wipe (`.neq`/`.not in` on `clearSpinePublishState`); an exemption is a preserved fragment that drifts and rots the shared DB. The standalone walk script then **imports that shared seeder** (one definition, no drift) and adds only what the refresh deliberately won't: the walk ACCOUNT (`E2E_WALK_*`, which no spec ever touches) and the self-verify. (Evidence: 2026-08-04 #1226 — twice-corrected for reaching for a wipe exemption instead of seeding from clean.)
- **Is idempotent** — re-running it refreshes the fixture in place rather than duplicating rows. USER re-runs walks; a script that fails or drifts on the second run is broken.
- **Refuses to run against production, loudly.** Check the resolved project ref (Step 1.2's technique, not a config assumption) before writing anything; hard-fail with a clear message if it doesn't match the expected walk/e2e branch.
- **Self-verifies the authority the feature rests on before handover.** Don't just insert rows — sign the walk account in against the target database and assert the thing the walk depends on (an RPC returns the right shape, a scope resolves, a count matches) so the fixture is verified at the layer the walk will actually use, not just "insert succeeded."

## Step 3: Use the walk-dedicated accounts — hard rule

The e2e cast is a closed, role-named set (`e2e/test-config.js` is the authority — read it fresh, don't hardcode a roster here, it will go stale). There is now a **parallel set of walk-only accounts** (`E2E_WALK_*` roles, `e2e-walk-*@test.example.com`) that exist for exactly this skill. Walks use those, always — never a normal journey-cast account, never a ticket-named one-off.

Two failure modes have actually happened, both from breaking this rule:

- **Seeding a walk fixture onto a normal cast account.** Journey specs wipe their signed-in actor's memberships account-wide on every CI run (correct and load-bearing for them — a subject-count-sensitive feature can't have its precondition made true by an enumerated wipe). A walk fixture riding that account gets destroyed mid-walk by the next Preview Tests run. This happened twice in one day, 2026-07-28.
- **Inventing a per-walk account** (`walk-1224@…`, ticket-named). The cast is role-named, not ticket-named — a one-off account is drift the moment the next walk needs a similar persona and either duplicates it or reuses it wrong.

Another agent may be actively expanding the walk-cast roster while you run this skill — that's fine, it's why you read `e2e/test-config.js` fresh instead of hardcoding a list here.

## Step 4: Write the doc

Write to `tmp/preview-walk-<feature>.md` at the **worktree root** (not `app/tmp`, not the scratchpad). Structure, mined from a real walked example (`example-app-operator-sidebar/tmp/preview-walk-operator-sidebar-1224.md`):

```markdown
- [ ] Done

# Walk — <feature name> (#NNN)

**READY TO WALK.** <one line: preview is live, migration applied where, fixture seeded and left in place.>

**Walk here:** <preview URL + deep link>

**Database:** <resolved project ref> — confirmed by reading the Supabase URL out of the deployed bundle itself, not a config file. <migration state + how the seed script self-verified.>

---

## What you're validating (~N minutes)

<plain language: what changed, in product terms, and what claims this walk checks. No jargon — see document-drafting-conventions.md plain-language-first.>

**Sign in as:** `e2e-walk-<role>@test.example.com` — the shared e2e cast password. You are **<persona name>**.

This is a walk-only account. No automated spec seeds it, wipes it, or signs in as it.

**Your seeded world:** <plain nouns — gyms, teams, people, requests, in the state the walk depends on>

---

## Leg 1 — <name>
- [ ] <step>. **Expected:** <observable result>. *(behavior-map §NN)*
- [ ] ...

## Leg 2 — <name>
...

---

## If something's off
- **<symptom>** → <how to tell seed problem from product bug, and what to check first>

## Cleanup
<what the walk itself writes, and what to note if USER changes state during the walk>
Anything you changed:
`[USER]{}`

---

## Sign-off
<one or two direct questions about the thing this walk exists to validate>
`[USER]{}`

Anything that felt wrong, even if it passed:
`[USER]{}`
```

Notes on filling it in:
- Every `[USER]{}` slot is backtick-wrapped with braces ALWAYS EMPTY, prompt on the line above — see `document-drafting-conventions.md`. Never `...` or placeholder text inside the braces.
- Legs are ordered `- [ ]` steps, each with an EXPECTED result, each mapped to a behavior-map entry where one exists.
- An earlier step must never destroy the precondition a later step needs — e.g. don't approve a join request in Leg 2 if Leg 4 needs one pending. **Fix this in the FIXTURE, not the leg order:** seed two pending requests so Leg 2 can consume one and Leg 4 still finds one waiting. Seeding generously costs a row; making the walk tiptoe around its own state costs USER a real constraint on what he's allowed to click, and a walk he can't explore freely isn't a walk. Splitting into separately-seeded runs is the last resort, not the first move — it means signing in twice and losing your place. (USER, 2026-07-28: "make the seed generous rather than the walk careful.")
- Skip a leg explicitly (with `- [ ]` left unchecked and a note) rather than silently omitting a case that isn't seeded for this walk — say why, the way the 1224 example does for the single-subject case.

## Step 5: Read his feedback back

When USER fills a slot, the loop isn't over. Each note gets answered **in the doc, underneath his own words**, classified as one of:

1. **Working as designed** — explain why, point at the decision/section that makes it correct.
2. **A real defect** — fix it, then note the fix here.
3. **A genuine gap that's nobody's bug** — file it as an issue, link it, and say so.

The 1224 example (Leg 3's declare-button note) has a worked instance of all three answered under one note — use it as the model for tone and structure: direct, no hedging, each half of a multi-part note addressed separately.

## Anti-patterns

- Handing over a bare preview URL plus steps in chat instead of a doc.
- Writing the doc before completing Step 1 — a doc pointing at a broken preview.
- Walking as a non-walk-cast account (a journey account, a personal account, an invented one-off).
- Saying "verified" about a path you traversed the ingredients for but never actually clicked through.
- A leg whose earlier step destroys the precondition a later step needs.
- Leaving a USER note unanswered in the doc — the loop closes when the note has a reply, not when he stops looking at it.
