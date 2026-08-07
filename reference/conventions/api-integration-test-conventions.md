# API / DB Integration Test Conventions

Applies to the **vitest API/DB integration suite** (`tests/api-integration/**`, run via `vitest.integration.config.js`) — the layer that exercises real Supabase behavior (RLS, RPCs, triggers, `auth.uid()`) and/or deployed Vercel function contracts. NOT Playwright (see `e2e-test-conventions.md`) and NOT pure unit tests.

## The cost model — internalize this before adding tests

**Integration-suite wall-time = (network latency to the DB) × (number of fixture round-trips).** It is dominated by I/O, not CPU or assertion count. Every `makeConfirmedUser` / `makeUnclaimedProgram` / `createUser` / row insert that crosses the network to a **shared remote** Supabase branch costs ~100ms+ and the suite runs **sequentially** (shared mutable DB → `concurrent:false`). So cost grows with fixtures, silently, every slice — until the CI job hits its timeout cap and starts flaking fully-green runs on wall-clock alone.

This is a recurring failure mode: a suite that's "green today" is one or two slices from canceling on timeout. The cap-bump is a stopgap that hides the cost; it is not a fix. (Evidence: example-app #934 — `api-tests` hit 93% of its 10-min cap; a single 42-fixture file added 1m41s.)

## Two levers — apply both

### 1. DB-direct tests run against a LOCAL ephemeral Postgres, not the remote branch (default)

A spec that talks **only** to Supabase via `supabase-js` (service/anon/user client, `.from()`, `.rpc()`, `auth.admin.*`) and never hits a deployed endpoint is **DB-direct**. It does NOT need a remote branch or a deployed app — run it against `supabase start` (local Postgres + GoTrue + PostgREST):

- **Fidelity is exact, not approximate.** Local Postgres applies the identical `supabase/migrations/` SQL, so RLS policies, SECURITY DEFINER RPCs, triggers, unique-index concurrency, and JWT-based `auth.uid()` resolution behave the same. Verified: a 42-fixture file ran ~25× faster locally (3.96s vs ~1m41s) with all security-critical (null-uid, RLS-REVOKE) assertions passing.
- **CI runners are fresh**, so `supabase start` auto-applies migrations + seed. Do NOT also `supabase db reset` (doubles init). Locally, a pre-existing volume can be stale (`start` logs "Starting database from backup" and skips migrations) — `supabase db reset` is the local-only fix. Add a one-line schema-readiness assertion (e.g. `select to_regclass('public.accounts')`) so a missing migration fails loud instead of RED-on-every-test.
- DB-direct fixtures should read `TEST_SUPABASE_*` straight from `process.env` so the same spec runs against local or remote by URL alone — no code change.
- **Source the local lane's env from `supabase status -o env`, NEVER `op run --env-file=.env.test.tpl`.** The `.env.test.tpl` secrets point `TEST_SUPABASE_URL` at the **remote e2e branch** — so a "local" run wrapped in `op run` silently drives every fixture against remote, and a mutation check (break a CHECK/FK/RLS, expect exactly one test to flip red) passes *vacuously GREEN* because the assertions never ran against the schema you mutated. Point the local lane at the `supabase start` instance's own credentials. (Recurring false-positive-GREEN mutation, 2 sessions.)

A spec that hits a **deployed** endpoint (`fetch`/`TEST_BASE_URL`/`apiGet`/`apiPost`) cannot have only its DB layer pointed local while the deployed function still reads remote — the function and the test must agree on which DB they see. Those (Mixed + HTTP-only) stay on the deploy-gated path unless you run the functions locally too (`vercel dev` against local Supabase).

### 2. Minimize fixture round-trips even on the remote path

- **Prefer `beforeAll`-shared fixtures over per-`it()` creation** for read-only tests. Create one user/program/team once and reuse it; isolate only the genuinely *mutating* cases with their own fixtures. A file with 25 read-mostly cases does not need 42 user/program creations.
- **Don't create what you can seed.** A stable, read-only fixture belongs in `seed.sql`, created once at branch/DB init, not minted-and-torn-down per test.
- **Watch the count.** If a new spec adds more than a handful of fixture round-trips, that is a cost signal — reach for sharing or local-Postgres before merging.

## Mechanical guard — keep the lanes from drifting

When a suite is split into a local-Postgres lane and a deploy-gated lane, job routing must key off a **drift-resistant, machine-checkable signal**, never a hand-maintained glob (it rots: a DB-direct test dropped in as a plain `*.test.js` silently runs slow; a `*.db.test.js` that fetches the app fails confusingly).

- Name DB-direct specs `*.db.test.js`; route jobs by that suffix.
- Enforce with a CI lint, **behavior-keyed** (not a blunt "imports supabase ⇒ local"): a spec is local-lane iff it uses a supabase-js client factory **AND** references no HTTP route. That correctly leaves Mixed (supabase-js **and** fetch) on the deploy lane — a binary rule creates an impossible state for Mixed files.
- The lint is itself test-first: pin it from both sides with paired negative + positive fixtures that name the violating file on FAIL (so an exit-1 from a crash can't masquerade as a correct rejection). See `example-app/scripts/check-test-bucket-boundary.js` + `tests/check-test-bucket-boundary.test.js` (#934).

## Related
- Assertion discipline (pair every negative with a positive): `test-plan-conventions.md` § Interaction-gate.
- Supabase schema/migration ops: `~/Projects/dev-reference/workflows/supabase-schema-workflow.md`.
- Playwright e2e: `e2e-test-conventions.md`.
