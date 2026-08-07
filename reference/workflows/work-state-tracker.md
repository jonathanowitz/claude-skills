# Work-State Tracker (example-app orbit) — the single source of truth for priority + state

**Scope:** This doc describes the tracker for the **example-app orbit** — `example-app`, `example-context`, `dev-reference`, and `claude-config` (the orbit rule in `references/product-json.md`; these repos all set `issue_tracker = USER/example-app`). Every other repo (decidr, example-b, example-c, example-d, consulting…) tracks its own priority + state in its own repo, by whatever mechanism that repo declares — the specific board and field IDs below apply only to the orbit.

**Canonical since 2026-07-17.** For the orbit, "what is the state of all my work, and what is the next thing" is answered by **GitHub Project #1 — "Project Tracker"** (`github.com/users/USER/projects/1`), for both USER and every Claude session working in an orbit repo. This replaces the drift-prone stack of hand-synced artifacts (the `next` label — deleted; the `project-briefs.md` priority table — stripped; `next-steps.md` as a priority signal — retired).

## The layers (don't reintroduce competing sequencers)

- **Work items** = GitHub issues in `USER/example-app` (the orbit's shared tracker — see Scope above).
- **Priority + sequence** = the board's **Priority** field: `Now` / `Next` / `Later`. This is THE sequencer. (Newly auto-added issues have no Priority and sit in the board's "No Priority" / triage column until placed.)
- **State** = the board's **Status** field: `Todo` / `In Progress` / `Done`, kept current by GitHub's built-in **workflows** (auto-add new issues; issue closed → Done; PR merged → Done; auto-archive Done > 2 weeks). **No manual feeding** — that is the whole point; manual feeding is what rotted every prior artifact.
- **Track** = `Rebuild` / `Infra` / `Cleanup` / `Ops` / `Side` (formalizes the old `1·rebuild`-style prefixes).
- **Epic → slice** = the native **Parent issue** + **Sub-issues progress** fields. Epics are issues; slices are their sub-issues. The "By epic" board view shows the plan.
- **Detail / shaping prose** = the shaped briefs in `example-context/briefs/` (and the `project-briefs.md` index), linked from the issue. This is the *detail* layer, never a priority source.

## Reading it

- **USER (glance):** the **Priority** board view — Now / Next / Later / No-Priority columns; drag a card between columns to re-prioritize.
- **A Claude session (auto):** the `SessionStart` hook `~/.claude/hooks/tracker-now-next.sh` injects the current `Now` + top-3 `Next` at the start of every example-app session (capped to avoid context bloat).
- **A Claude session (ad hoc query):**
  - What's Now/Next: `gh project item-list 1 --owner USER --format json | jq '[.items[]|select(.priority=="Now" or .priority=="Next")]|map({n:.content.number,priority,status,title:.content.title})'`
  - Untriaged inbox: filter `.priority==null and .status!="Done"`.

## Writing it

- **Start work on issue #NN:** `bash ~/.claude/hooks/example-now.sh <issue#>` → sets that item **In Progress + Priority=Now** (adds it to the board first if absent). Fold this into the worktree-create step of the git workflow.
- **Mark done:** do it the normal way — **close the issue**, or merge a PR whose body says `Fixes #NN`. GitHub's native workflow moves it to `Done`. **Never set Status=Done by hand or by hook** — the native workflow owns that transition; a second writer causes a race (agy review, 2026-07-17).
- **Re-prioritize:** USER drags on the board; an agent (rarely) uses `gh project item-edit --id <item> --project-id PVT_kwHOAI1B-M4BQIxS --field-id <Priority-field> --single-select-option-id <opt>`.

## IDs (for scripting)

- Project: `PVT_kwHOAI1B-M4BQIxS` (number 1, owner `USER`)
- **Priority** field `PVTSSF_lAHOAI1B-M4BQIxSzhYNXug` — Now `93fb5f92` · Next `dae48f26` · Later `8deb3b2f`
- **Track** field `PVTSSF_lAHOAI1B-M4BQIxSzhYNXuk` — Rebuild `429fe63b` · Infra `9f5f72a2` · Cleanup `c1badcd5` · Ops `d5483b0c` · Side `5c631725`
- **Status** field `PVTSSF_lAHOAI1B-M4BQIxSzg-WAHE` — Todo `f75ad846` · In Progress `47fc9ee4` · Done `98236657`

(Re-list any time with `gh project field-list 1 --owner USER --format json`.)

## Constraints / gotchas

- `gh project` CANNOT create Views or toggle Workflows — those are web-UI only (one-time setup, done 2026-07-17).
- macOS ships **bash 3.2** — no associative arrays (`declare -A`); use `case` for name→id maps in tracker scripts.
- Branch names are descriptive (`feature/<desc>`) and carry no issue number, so "In Progress" can't be inferred from a branch — hence the explicit `example-now` helper rather than a WorktreeCreate hook (which also only fires for Claude-internal worktrees, not `git worktree add`).
- `Later` is a *deliberately-deferred* bucket, not a dumping ground. Newly auto-added issues get **no** priority (triage), not `Later`. If `Later` starts re-rotting like the old `next` label, collapse to binary Now/Next + no-priority (agy's recommendation, deferred by USER 2026-07-17).
