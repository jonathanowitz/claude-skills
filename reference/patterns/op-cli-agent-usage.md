# Using the `op` (1Password) CLI from an agent subprocess

When a task needs secrets that live in 1Password (e.g. running `op run --env-file=.env.test.tpl -- <cmd>` to get Supabase test creds), the agent's Bash tool **can** drive `op` directly — as long as the 1Password desktop app is unlocked and the CLI integration is set up. The trap is using the wrong probe to decide whether op is available.

## The load-bearing rule

**`op whoami` is a MISLEADING availability check from an agent subprocess — never use it.**

`op whoami` reports **session-token** state (the `op signin` flow). The agent's Bash tool spawns a fresh shell per call from the user's profile, so it never carries an `OP_SESSION_*` token → `op whoami` returns `account is not signed in` **even when op is fully functional** via the desktop-app integration.

**Corollary — NEVER ask the user to run `op signin` / `! eval $(op signin)` to "fix" a failed `op whoami`.** This is the recurring failure mode (3× and counting). `op signin` sets `OP_SESSION_*` in **the user's interactive shell**, which your Bash tool's fresh subprocess does not inherit — so your *next* `op whoami`/`op read` still won't see it, and you've burned a turn (and the user's attention) for nothing. The instant you'd type `op whoami`, type `op read <ref>` instead. The fix is ALWAYS `op read`, NEVER user involvement. (The only thing the user must do is have the 1Password desktop app *unlocked* — and that's almost always already true; verify with `op read`, not by asking.)

The desktop-app integration (XPC) serves item access **without** a session token. So while `whoami` reports "not signed in," these work from the same subprocess:
- `op read "op://<vault>/<item>/<field>"` — read one secret **(the dependable primitive — use this)**
- `op vault list`, `op account list` — list metadata

**BUT `op run` and `op inject` are NOT dependable from the agent subprocess** — see the "authorization timeout" section below. They initialize a full client (a heavier auth path than `op read`'s XPC item-access) and frequently die with `error initializing client: authorization timeout` or `response: promptError`, even in the same shell where `op read` succeeds a second earlier. Do not build a flow that depends on `op run`/`op inject`; build it on `op read` + the resolve-once-cache pattern below.

**Correct availability probe: `op read <ref>` (or `op vault list`). If it returns the value, op works — go straight to `op run`.** Do NOT conclude "op can't work in my subprocess" from `whoami`, and do NOT make the user materialize secrets to a plaintext `.env` or hand-run every command. (Evidence — this keeps recurring despite the doc existing:
- 2026-06-17 — wasted a multi-message detour concluding op was unusable in-subprocess because `op whoami` failed, while `op read "op://Example-Dev/Supabase-Test/url"` succeeded immediately in the same shell. The user had to push back twice. (This doc was written in response.)
- 2026-06-19 — same `op whoami` mis-probe logged again in session telemetry.
- 2026-06-21 — S3a.0 Gate 2: ran `op whoami` → "not signed in" → asked USER to `! eval $(op signin)`, waited, ran `op whoami` AGAIN (still failed), only THEN used `op read` (worked instantly). USER: "that's the second or third time you've done the op sequence wrong." Root cause confirmed upstream: `claude-config/rules/hooks-and-agents.md` WORKTREE_SETUP section said "Requires `op` signed in (`op whoami`)" — actively priming the wrong probe at session-load time. Fixed that line to point at `op read` + forbid the user-signin escalation.)

## Why it works without a prompt

When the desktop app is **unlocked** + CLI integration is on + the `op` binary has Full Disk Access, op authorizes CLI requests over the already-open XPC channel — **no biometric prompt needed**. Biometric only prompts when the app is **locked**, and that prompt genuinely cannot fire in a non-TTY subprocess. So: app unlocked → agent op commands just work; app locked → the user must unlock once in the GUI, then they work.

## Prerequisite (one-time, may already be done)

On macOS Sequoia (15.x), TCC blocks terminal-launched processes from reading 1Password's Group Container, so `op` falls back to token mode and the integration appears dead. Fix = grant **Full Disk Access to the `op` binary itself** (`/opt/homebrew/bin/op`), NOT Terminal.app, then Cmd+Q relaunch. Minimal blast radius (only the trusted op binary gets container access). Diagnostic tell: `op whoami --debug` → `Skipped loading desktop app settings file … operation not permitted`. If agent `op read` fails with a permission/EPERM error (not a "not signed in" error), this FDA grant is the fix — surface it to the user. Full origin writeup: 2026-06-09 1Password migration.

## Quick reference

```bash
# Probe (from agent Bash) — NOT `op whoami`:
op read "op://Example-Dev/Supabase-Test/url"      # returns value → op works

# Use it:
op run --env-file=<wt>/.env.test.tpl -- pnpm --dir <wt> exec vitest run ...
```

If the probe fails:
- `account is not signed in` on `op read` too → app is locked or integration off → user unlocks the 1Password app once.
- `operation not permitted` / EPERM → the `op`-binary Full Disk Access grant above.
- `authorization timeout` / `promptError` on `op run`/`op inject` (but `op read` works) → the client-init auth path is cold; don't retry `op run` — switch to `op read` per below.

## `op run` / `op inject` fail with "authorization timeout" — use `op read` only

Observed repeatedly (2026-07-15, nav-slice-2a Gate 2): `op run --env-file=... -- <cmd>` and `op inject -i <tpl> -o <out>` both fail in the agent Bash subprocess with `error initializing client: authorization timeout` (and `op inject` sometimes `response: promptError`), while `op read "op://..."` in the very same shell returns the secret instantly. The two commands take different auth paths: `op read` rides the already-open XPC item-access channel; `op run`/`op inject` spin up a full client session that wants the session/biometric handshake, which can't complete non-interactively. **Treat `op read` as the ONLY reliable op primitive from an agent.** `op run`/`op inject` may work when the desktop session is freshly warm, but they are not dependable — never gate a multi-step flow on them.

`op inject` gotcha (if you do use it): it substitutes any `op://` string it finds, **including inside `#` comment lines**. A committed `.env.tpl` whose header comment mentions "op:// references" makes `op inject` choke (`invalid secret reference 'op://references...'`). Strip to assignment lines first: `grep -E '^[A-Z_]+=op://' .env.tpl > clean.tpl`.

## Minimize prompts: resolve every secret ONCE while warm, cache, reuse

The recurring "why do I keep getting op prompts?" pain comes from touching op many times: N per-secret `op read`s per command × several command re-runs (deploy, then tests, then a retry) — each time the short-lived cached session has lapsed, the user gets another Touch ID prompt. The fix is to collapse the whole batch to ONE op moment:

1. If op is cold (`op read` fails with a prompt/timeout), ask the user to warm it ONCE interactively via the `!` prefix (e.g. `! op read "op://Example-Dev/Supabase-Test/url"` or just unlocking the 1Password app). The `!`-prefixed command runs in the user's interactive context where the biometric CAN fire; your subprocess then rides the freshly-warmed session.
2. Immediately (while warm) run ONE script that `op read`s **all** needed secrets — for every downstream step (deploy token + test env + DB creds) — and writes them to a session-scoped env file in the scratchpad, `chmod 600`. One script = the reads run back-to-back on one warm session = at most one prompt.
3. Every downstream step sources that cached file (`set -a; . <scratchpad>/creds.env; set +a; <cmd>`) — zero further op calls. Deploy, run all tests, re-run on failure: none of them touch op again.
4. Delete the cached env file when the batch is done (it holds plaintext secrets; the scratchpad is session-isolated + gitignored, but don't leave it lying around).

This took nav-slice-2a's Gate 2 (inspect DB + deploy preview + run 4 journeys, each needing 7+ secrets) from ~4 scattered prompts down to the single warm-session moment the user provided. Sanity-check the cache after resolving: `grep -qE '=$' creds.env` catches any secret that resolved empty (a failed read) before a downstream step dies with a confusing "X is required".
