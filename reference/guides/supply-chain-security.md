# Dependency Supply-Chain Security

The standard for how Example Project installs third-party packages safely. Two ecosystems, one posture. **pnpm (JS) and uv (Python) are the standard; npm is legacy** — kept running on the shipped stack until cutover, never extended.

## Threat model — the install-time attack surface

The risk is not "a dependency has a bug." It's that **installing a package runs attacker-controlled code or pulls an attacker-controlled version**, before any of your code runs:

1. **Compromised publish / malicious version** — a maintainer account is taken over (or a maintainer goes rogue) and a poisoned version is published. The window between "poisoned version published" and "the world notices + yanks it" is usually hours to a couple of days.
2. **Install-time code execution** — npm lifecycle scripts (`postinstall`, `preinstall`) and Python source-distribution build hooks run arbitrary code on `npm install` / `pip install`. This is the #1 path from "I added a dependency" to "my machine/CI is compromised."
3. **Transitive blast radius** — you vet your direct deps; the poison is three levels down in something you never chose.

Two controls neutralize most of this, and **both ecosystems support both controls**:

| Control | What it does | uv (Python) | pnpm (JS) | npm (legacy) |
|---|---|---|---|---|
| **Minimum release age** | Refuse any package version published inside a rolling window — sidesteps the "poisoned version, not yet yanked" window, transitively | `exclude-newer` | `minimumReleaseAge` | ✗ (only per-invocation `--before`) |
| **Block install-time code** | Refuse to run lifecycle/build code from packages | `no-build` | lifecycle scripts off by default (v10+) | `ignore-scripts` (all-or-nothing) |
| **Frozen, lockfile-pinned installs** | Install exactly the locked tree, never re-resolve | `uv sync --frozen` | `pnpm install --frozen-lockfile` | `npm ci` |

The minimum-age control is the high-leverage one: it costs nothing operationally (you just install versions that are 7+ days old) and it closes the single most common real-world attack — the freshly-published compromised version — without you having to know anything about the specific package.

---

## Python — uv

**Status: shipped.** `tools/` migrated pip → uv in #857 / PR #866 (2026-06-11). Config in `tools/pyproject.toml`:

```toml
[tool.uv]
package = false          # tools/ is standalone scripts, not an installable package
exclude-newer = "1 week" # rolling min-age window; covers transitive deps. uv records it
                         # as exclude-newer-span = "P1W". Only bites at lock time.
no-build = true          # refuse to execute sdist build code — install from wheels only
```

Key properties:

- **`exclude-newer` only bites at lock time (`uv lock`), never on `uv sync --frozen`.** So it can't break CI — CI just installs the already-locked tree. The age gate is applied when you *update* the lockfile, which is exactly when a poisoned version would otherwise slip in.
- **`no-build = true` is only safe because every locked dep ships a wheel.** This was verified at migration time — including the C-extension deps (pyroaring, pypdfium2, zstandard, pydantic-core) which have manylinux x86_64 wheels. If you add a dep that has no wheel for the CI platform, `uv lock` / `uv sync --no-build` will fail loudly — that's the gate working. Either find a wheel-shipping alternative or consciously remove `no-build` and re-audit.
- **`uv.lock` pins the full transitive tree** (59 packages for `tools/` today), with platform-specific wheels for every C-extension.

CI pattern (`.github/workflows/manual-upload.yml`, `schedule-monitor.yml`):

```yaml
- name: Install uv + Python
  uses: astral-sh/setup-uv@v8
  with:
    python-version: '3.11'
- name: Install Python parser dependencies
  run: uv sync --frozen --no-build --directory tools
# then route the Node pipeline through the uv venv:
#   PYTHON_BIN: ${{ github.workspace }}/tools/.venv/bin/python
```

The existing `process.env.PYTHON_BIN` hook (in `auto-publish.js` / `process-upload.js` / `pdf-validation.js`) means the Node→Python bridge needs zero script changes — just point `PYTHON_BIN` at the uv venv.

Local dev needs uv installed: `brew install uv`. Run scripts with `uv run` (see `tools/README.md`). Updating deps: `uv lock` (re-applies the age gate) → commit `uv.lock`.

---

## JavaScript — pnpm

**Status: LIVE (S1.0a, 2026-06-11).** pnpm migrated from npm for the rebuild monorepo in S1.0a (#868). Installed via `corepack` (Homebrew corepack + `corepack enable pnpm`); version pinned in `packageManager` field. **Shipped `pnpm-workspace.yaml`:**

```yaml
packages:
  - 'app'
  - 'contract'
# Supply-chain: refuse versions published in the last 7 days (transitive).
minimumReleaseAge: 10080   # minutes = 7 days
minimumReleaseAgeExclude:
  - '@sentry/*'            # already-merged release that was <7d old at migration time
# Allow-list packages that need build scripts:
allowBuilds:               # pnpm 11 renamed onlyBuiltDependencies → allowBuilds
  esbuild: true
# Patch for capacitor-live-activity: npm postinstall git-apply breaks on pnpm symlinks
patchedDependencies:
  capacitor-live-activity@0.x.x: patches/capacitor-live-activity.patch
```

**pnpm 11 rename:** `onlyBuiltDependencies` (pnpm ≤10) → `allowBuilds` (pnpm 11+). If you see the old key silently doing nothing (esbuild still ignored), you're on pnpm 11 — use `allowBuilds`.

**Phantom deps exposed by pnpm's strict symlinked layout:** npm's flat hoisting silently resolves undeclared imports. pnpm makes them fail loudly. Expect to declare `playwright`, `zod`, and similar dev-tool deps that were transitively available under npm.

**Vercel nft + pnpm workspace symlink gotcha:** Vercel's file tracer (`@vercel/nft`) traces normal `node_modules` and relative imports — but it CANNOT follow pnpm workspace symlinks. A workspace package (`@example/contract`) resolved via the pnpm store symlink produces `ERR_MODULE_NOT_FOUND` at runtime on a Vercel serverless function, even if `dist/` exists and exports are configured. The fix: esbuild-bundle the handler, INLINING the workspace package (`bundle: true` + the package is NOT in `external`). Real `node_modules` deps (e.g., `zod`) stay external so nft can trace them normally. This is the C1 api build pattern used by `scripts/build-api-rebuild.mjs`.

Original target config notes — `pnpm-workspace.yaml`:

Key properties:

- **`minimumReleaseAge`** (pnpm ≥10.16; default 24h in v11) is the JS sibling of uv's `exclude-newer`. `10080` minutes = 7 days, matching the Python side. Like `exclude-newer`, it applies at resolve time, not at frozen install — CI stays deterministic.
- **Lifecycle scripts are blocked by default since pnpm 10.** `postinstall`/`preinstall`/`install` scripts only run for packages you explicitly allowlist via `onlyBuiltDependencies`. This closes the #1 supply-chain entry point *by default* — the opposite of npm, where scripts run unless you remember to disable them. When a package genuinely needs its build script (esbuild, sharp, etc.), add it to the allowlist consciously, one at a time.
- **Native workspaces** fit the AS-2 `contract/app/api` monorepo (no extra tooling).
- **Content-addressable store** — per-worktree installs become hardlinks into a shared store, near-instant and low-disk. Directly speeds the worktree-per-feature workflow (the `WORKTREE_SETUP_COMPLETE` install step drops from minutes to seconds).
- **Vercel detects pnpm natively** via the `packageManager` field in `package.json` — no build-config change.

CI pattern (S1.0a, shipped in `.github/workflows/test.yml` etc.):

```yaml
- uses: pnpm/action-setup@v4
- run: pnpm install --frozen-lockfile   # the npm ci equivalent
```

Adoption churn handled at S1.0a bootstrap:
- ✅ CI workflows (`test.yml`, `docker-build.yml`) flipped npm→pnpm.
- ✅ Global `CLAUDE.md` updated with pnpm workspace context note.
- ✅ Global `worktree-create-hook.sh` + `bash-post-hook.sh` made **conditional** on `pnpm-workspace.yaml` (so the hooks work for both the rebuild monorepo and legacy npm worktrees).
- Still open: `WORKTREE_SETUP_COMPLETE` hook install step (update when worktree pattern is exercised post-S1).

Known churn risk: pnpm's symlinked `node_modules` occasionally trips flat-layout-assuming tooling. Capacitor CLI is generally fine; the escape hatch if something breaks is `node-linker=hoisted` in `.npmrc` (trades the strict layout back for a flat one, keeps the other controls).

---

## npm — legacy

The shipped stack runs on npm and stays there until cutover. **Do not extend npm to new surfaces** — new work is pnpm. npm's supply-chain story is structurally weaker:

- **No persistent minimum-release-age.** npm only has per-invocation `--before <date>`, which nobody remembers to pass and which isn't recorded in the lockfile. There is no equivalent of `minimumReleaseAge` / `exclude-newer` that sticks.
- **Lifecycle scripts run by default.** The mitigation is `ignore-scripts=true` in `.npmrc` — but it's all-or-nothing (no per-package allowlist), so it breaks any dep that legitimately needs a postinstall (esbuild, sharp, Capacitor). After enabling it you must `npm rebuild <pkg>` the known-good ones by hand.

**Optional stopgap for the shipped stack** (not yet applied — there's no root `.npmrc` today): add `ignore-scripts=true` to a root `.npmrc`. **Test `npm ci` first** — esbuild/sharp/Capacitor postinstall is the breakage risk; rebuild those manually if needed. This is a defensive hardening of code that's being retired, so weigh it against just reaching cutover; it is *not* part of the AS-9 lock.

Always use `npm ci` (frozen, lockfile-exact) in CI, never `npm install`.

---

## Quick reference

| You're doing… | Command |
|---|---|
| Install Python deps in CI | `uv sync --frozen --no-build --directory tools` |
| Update a Python dep (re-applies age gate) | `uv lock` then commit `uv.lock` |
| Run a Python tool locally | `uv run <script>` |
| Install JS deps in CI (rebuild) | `pnpm install --frozen-lockfile` |
| Install JS deps in CI (legacy npm stack) | `npm ci` |

## See also
- `tools/README.md` (example-app) — uv setup + `uv run` usage
- `tools/pyproject.toml` (example-app) — live uv config
- `example-context/architecture/rebuild-architecture.md` §2 AS-9 — the pnpm lock
- uv: https://docs.astral.sh/uv/ · pnpm settings: https://pnpm.io/settings
