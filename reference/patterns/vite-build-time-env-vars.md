# Vite (and any build-time) env vars are baked at BUILD, not read at RUNTIME

**The mental model that prevents the bug:** there are two kinds of env var on Vercel, and they behave oppositely.

- **Build-time / inlined** — `VITE_*` (Vite), `NEXT_PUBLIC_*` (Next), anything read during the build and compiled into the client bundle. The value is a string literal in the shipped JS. The deployment **cannot** see a later change — the variable doesn't exist at runtime, only its baked-in value does.
- **Runtime** — `process.env.X` inside a Vercel Function / server handler. Read at invocation. Change it in Vercel → it takes effect on the next request, **no rebuild needed**.

## The trap

Setting (or changing) a `VITE_*` var in Vercel does **nothing** to an already-built deployment. It only affects the **next build**. So:

- If a PR that deploys to an environment introduces or depends on a new `VITE_*` var, the var **must be set for that environment BEFORE the build runs**. Merging first and setting the var after = the deployed bundle was built without it (missing/blank/stale value).
- The fix is never "just set the var" — it is "set the var, **then trigger a fresh build**."

## Recovery — the build already ran without the var

1. Set the var for the target environment: `vercel env add VITE_FOO production`
2. Trigger a fresh build (env-first, build-second — running the build before the var is set just reproduces the broken bundle). Any one of:
   - `vercel --prod` from the repo root (builds on Vercel's infra with the project's production env) — simplest.
   - Dashboard → Deployments → latest Production → ⋯ → **Redeploy**, with **"Use existing Build Cache" OFF** (so Vite re-inlines) — safest; rebuilds the exact merged commit, no local drift.
   - Empty commit to the deploy branch + push (`git commit --allow-empty -m "chore: rebuild for VITE env"`) — git-integration rebuild, auditable.

## Verify it took

Build-time vars are visible in the shipped bundle, so you can confirm without prod creds: fetch a deployed JS asset and grep for the expected value (e.g. the Supabase URL), or just exercise the feature. A blank/inert client surface with no network calls to the expected backend is the signature of "built without the var."

## Pre-merge gate

Before merging any PR that (a) deploys to a real environment AND (b) adds or newly depends on a `VITE_*` (or other build-time-inlined) var: confirm the var is set in Vercel **for that environment** first. `vercel env ls <environment>` lists the names. This belongs in the pre-PR checklist for build-time-env-touching PRs.

**Evidence:** 2026-06-15, example-app rebuild — PR #882 merged the new `/app2/` (Vite+React) front door to production; the prod build ran without `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` (they were never set for Production — `vercel env ls production` showed no `VITE_*`). Result: the live front door shipped with no Supabase wiring (blank competition list, no DB calls). Latent because the same vars WERE set for Preview, so every preview deploy looked correct. Caught by checking `vercel env ls production` before writing the go-live steps, not by the merge.
