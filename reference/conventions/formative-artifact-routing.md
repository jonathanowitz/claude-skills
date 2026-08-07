# Formative Artifact Routing — the two-home rule

Formative thinking artifacts (pre-mortems, UI mockups, shaping/framing scratch, triage ledgers and decks) used to be born in the code repo's `tmp/` — purely because sessions start in the code checkout and the artifact gets written to the nearest `tmp/`. That folder is gitignored, so those files are never committed and accumulate as orphaned local scratch until `/dream`/`/tidy` sweeps them. They are not code, and a worktree never wants them. (Origin: example-app#1278, surfaced by the first v2 `/dream morning` run, which archived ~44 such orphans in one pass — overwhelmingly pre-mortems and mockups.)

The fix is a routing rule, not a new folder. Two homes, keyed to artifact kind:

## 1. Thinking artifacts → born in the context repo, never in the code repo

Pre-mortems, UI mockups, shaping/framing scratch, and triage ledgers/decks are written to **`<context_repo>/tmp/`** and never touch the code repo. For a repo that declares one, `<context_repo>` is the `-context` sibling resolved via `resolve_product_field context_repo` (example-app → `example-context`, so the concrete path is `~/Projects/example-context/tmp/`). That vault is Obsidian-openable, already `/dream`-swept, and already carries `tmp/archive/INDEX.md` — so this leans entirely on machinery that already exists; there is no new plumbing to manage.

Fallback: a repo with **no** `context_repo` declared has no other home, so its thinking artifacts stay in the repo's own `tmp/` (the prior status quo). The rule only redirects when a context sibling exists.

## 2. Code-bound artifacts → born in the context repo, then copied into the worktree at creation

The narrow set of formative artifacts that graduate into the feature — test plan, walk doc, migration draft — are created during the formative phase in `<context_repo>/tmp/` alongside the thinking artifacts, then **copied into `<worktree>/tmp/` at worktree creation** and committed with the code. This is where the original pre-worktree/handoff instinct is exactly right: the artifact was born while thinking, and it earns its place in git history only once it's bound to shipping code.

Do **not** copy thinking artifacts (pre-mortems, mockups) into the worktree — that turns disposable thinking into permanent git history inside the code repo, which is worse than the orphan problem it replaces. Copy only the code-bound set, and only the ones this slice actually ships.

## Parking a thinking artifact against its issue

A pre-mortem (or any thinking artifact) that critiques still-open work is not disposable yet — but it also should not re-surface in every `/dream` triage while the work is unshipped. Give it a `keep-until-issue: #N` marker line and the classifier parks it: verdict `skip` while issue N is open, and an archive candidate the moment N closes (`park-expired-N-closed`). So the artifact tracks its issue's lifecycle on its own — kept while the work is unshipped, surfaced for archival once it lands — and you never swipe it in between. The marker's `#N` is metadata, not a citation, so it does not itself count as an open/closed issue reference. This composes with home #1: the parked artifact still lives in `<context_repo>/tmp/`; the marker only changes when it stops being kept.

## Why this shape

- The context repo is already the right home: swept, indexed, and version-controlled without polluting code history.
- Copying-at-creation is a judgment step (which artifacts are code-bound?), so it stays a documented lifecycle step, not a hook automation — a hook can't know which artifact graduates.
- No interim folder, no new sweep, no new index. The existing `/dream` + `tmp/archive/INDEX.md` machinery absorbs both homes.

## Surfaces that implement this

- `commands/shape-project.md` UI Mockup Protocol — writes the mockup to `<context_repo>/tmp/`.
- `commands/pre-mortem.md` Step 6 — saves the report to `<context_repo>/tmp/`.
- `workflows/pre-implementation-checklist.md` — the worktree-creation copy step for code-bound artifacts.
- `workflows/session-start-protocol.md` — the standing note so the rule is followed by default.
