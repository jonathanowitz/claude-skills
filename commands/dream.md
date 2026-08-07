---
description: Nightly maintenance — the cloud watches, the local morning half acts. Scans hot-path docs and tmp artifacts, archives the unambiguous, triages the rest.
allowed-tools: [Read, Glob, Grep, Bash, Write]
---

# Dream

Nightly maintenance, redesigned (v2, decided 2026-08-01). **The cloud watches; the local morning half acts.** Two live nights of the armed design produced three PRs to disposition and about one piece of real signal — the value was always the *noticing*, and the branch→commit→PR ceremony was overhead. v2 keeps the noticing and moves the acting to where acting is cheap and reversible: the dev machine, in the morning, with a human present.

Dream is not new capability. It is a **clock**, plus a spec narrow enough to check mechanically. `/maintenance` asks "what have we learned"; dream asks "is this file over 300 lines, yes or no". Keep that altitude — every judgment call you feel tempted to make belongs in a script or in a triage line, never in your head at 2 AM.

## The rule that governs everything below

**Classification lives in scripts, never in your reading of a file** (KD-7). You orchestrate: you supply the scripts the impure inputs they cannot fetch (issue states, open PRs), you run them, and you transcribe their output. You never decide that a file looks done, looks stale, or looks safe to archive. If a verdict seems wrong, the script is missing a signal — say so and fix the script in daylight.

`tmp-scan.sh` and the other scan scripts are pure functions of (files, time source, injected state). They make **no network calls at all**, and that is structural: `gh` does not exist in the cloud routine sandbox (`which gh` exits 1, verified 2026-07-24), and the GitHub MCP connector is callable only by a model, never from inside a bash script. So anything GitHub-shaped is fetched by **you** — via the MCP connector at night, via `gh` locally in the morning — and passed in as an argument.

## What v2 removed, and why the removal is the point

The armed apparatus existed only to make *unattended* mutation safe: KD-2 forbids the 2 AM cloud run touching `main`, so every archival had to travel through a pinned base SHA, a fenced commit, a pushed branch, and a PR. A watcher does not mutate, so all of it evaporates. **Retired from the flow:** the armed-job tier, `dream-commit.sh`, the `archive-with-index.sh` *PR* path, the nightly `report-<date>` PR job, the C10 duplicate-PR guard, and the base-SHA pinning / one-job-at-a-time-through-PR of the old Phase 0/2/3. The scripts still exist in `hooks/` for reference; the night flow no longer calls them.

**Survives intact, because it was the safety and not the ceremony:** KD-7 (classification in scripts), KD-14 (an open issue vetoes a done signal), KD-12 (`--time-source=git` distrust of clone mtime), KD-2 (never commit `main`), KD-11 (every archived file gets an index row), KD-10 (`example-app/tmp/` is gitignored and belongs to the local half).

**Consciously relaxed: KD-6's liveness alarm.** v1 made the nightly report's absence the alarm that the routine had died. v2 has no committed artifact to go missing, and manufacturing a heartbeat the ephemeral cloud container could sync back to the local machine is more machinery than the signal is worth. So a clean night is simply silent, and a night that never ran is caught by USER noticing the gap — an accepted tradeoff (2026-08-01), not an oversight. The routine platform's own run record remains the place to confirm a firing if a gap is ever suspected.

---

# `/dream` — the night watcher (cloud)

Pure watcher. **It scans; it never mutates.** No commits, no PRs, no arming, no archival. Its only outputs are a liveness signal every run and a findings note on the nights that have something to say.

## Phase 0 — Land on fresh `origin/main`

**Do this first, every run.** The cloud container checks out a **detached HEAD that can be behind `origin/main`** (observed 2026-07-25: `example-context` at `5cdce52` while `origin/main` was at `e3a07c3`). A scan of a stale snapshot reports findings that are already fixed. There is no longer any base SHA to *hold* — nothing commits — but the scan still has to run against the current tree.

For each repo (`example-context`, `example-app`, `dev-reference`):

```
git -C <repo> status --porcelain          # MUST be empty — see below
git -C <repo> fetch origin --quiet
git -C <repo> checkout -q --detach origin/main
git -C <repo> rev-parse HEAD              # record it — findings are claims about this SHA
```

**If `git status --porcelain` is non-empty, skip that repo entirely and record why.** `/dream` is an ordinary slash command with `Bash` in its allowed-tools, so it can be invoked on a laptop, where the cloud's assumptions do not hold: the working tree is somebody's actual checkout, mid-edit. A checkout against a dirty tree drags uncommitted changes across and strands the user off their branch. **`--detach`, not `-B`** — a detached checkout leaves no branch behind and moves nothing the user owns.

If a fetch or checkout fails, record it verbatim and continue with the other repos. **Never stop and never ask a question** — nobody is watching (KD-6). A run that halts produces no findings and no liveness, and that silence reads as "the routine died".

## Phase 1 — Scan, read-only, all three repos

Everything here is read-only. You are producing *findings*, never actions.

**Stale-file candidates — `example-context/tmp/`.** `example-app/tmp/` is gitignored (KD-10), invisible to a clone; it is the morning half's job, not this one.

1. First pass, to discover referenced issues:
   ```
   ~/.claude/hooks/tmp-scan.sh --dir=<example-context>/tmp --repo-root=<example-context> --time-source=git --format=json
   ```
2. Read the `issues` keys off that JSON. For each, fetch the state **via the GitHub MCP connector** against `USER/example-app` (the single tracker for the whole orbit). A merged PR counts as `CLOSED`. Note: MCP `list_pull_requests` returns `merged:false` with a populated `merged_at` for merged PRs — read `merged_at`, not `merged`.
3. Second pass, authoritative:
   ```
   ~/.claude/hooks/tmp-scan.sh --dir=<example-context>/tmp --repo-root=<example-context> \
       --time-source=git --issue-states=<n>=CLOSED,<n>=OPEN --format=json
   ```

**`--time-source=git` is mandatory and is not a preference (KD-12).** `git clone` does not preserve mtime — confirmed twice in the live sandbox, where `README.md`'s filesystem mtime sat ~9 days after its last commit. Under `mtime` in a fresh clone every file reports as 0 days old, so nothing is ever stale *and the night looks clean*. The failure is silent in both directions, which is what makes it the sharpest hazard in the design.

Report the `delete` verdicts as **archive candidates** — they are what tomorrow morning's actor will archive — and the `review` verdicts as **triage candidates**. The night watcher does neither; it only names them. Two signals it deliberately refuses to guess about: `untracked-fallback` (no commit history, age fell back to mtime — treat as unreliable, never zero) and `mockup-stale` (surface it; the morning half decides).

**Doc thresholds.**
```
~/.claude/hooks/check-doc-threshold.sh --file=<example-context>/next-steps.md --max-lines=100 --unique-section="## Immediate next step"
```
Independent signals, each flagged on its own line, nothing more. **Line cap:** 100 is the written rule (`next-steps-convention.md:65`, lowered from 300 on 2026-07-31); the boundary is exact (100 passes, 101 violates) — flag `violation` and the overage. **Structural:** rule 8 requires *exactly one* `## Immediate next step` section, so both sides are findings *regardless of line count* — `duplicate_sections:true` (with `sections:N`; a 143-line file with six of these was the evidence, green on the line cap and already rotted into a changelog) and `missing_section:true` (the required heading was renamed or deleted, which would otherwise audit green forever). Flag whichever fired as its own line. Which lines or sections go is a content judgment with no written rule behind it, and inventing one at 2 AM is exactly the prose-classification KD-7 forbids.

**Behavior-map drift — flag only, forever.** Diff recently merged PRs against `§NN` claims in `app-behavior-map.md` / `codebase-map.md` and **emit suspicions, never edits**. Confirm a PR's merge state with `pull_request_read`, never `list_pull_requests.merged` — the list tool returns `merged:false` with a populated `merged_at` for PRs that are in fact merged, so any job trusting its `merged` field silently under-counts. These are large canonical docs — read them by section (`Grep` the heading, then `Read` with `offset`/`limit`), never whole-file.

**Brief-shipped candidates.** For each brief in `dev-reference/briefs/` not already under `briefs/archive/`, read its `issue:` YAML frontmatter key (the authoritative brief→issue link — see `shape-project`). **A null or absent key → skip the brief and report it as unmappable; never guess a number from prose** (a bolded `**GitHub:**` line or a `#NN` in the body is display, not identity). With a numeric key, fetch that issue's state via the MCP connector against `USER/example-app`: **CLOSED → report as an archive candidate** for the morning half. Closed IS the ship signal — a merged PR closes its `Fixes #NN` issue, and a PR-less config/convention brief closes its issue on completion; the old "issue closed AND PR merged" double-gate is exactly what left this job unable to act, and it only reports candidates a human confirms anyway. If you ever do read PR merge state here, confirm it with `pull_request_read`, not `list_pull_requests.merged` (same false-`merged` caveat as above). Do not move anything.

**Not run at night: `board-hygiene`.** Project #1 is user-owned, and the GitHub MCP connector exposes Projects v2 fields only for org-owned projects — at night the job could only ever skip (`list_issue_fields` → `[]`, "Could not resolve to an Organization"). It lives in the morning half, where `gh` reaches the board.

## Phase 2 — Speak only when there is a finding

**A clean night is silent.** If Phase 1 turned up nothing — no archive candidates, no threshold violation, no drift, no shipped brief — the run stops without a word. There is no heartbeat and no "alive, clean" note: manufacturing one the ephemeral cloud container could sync back to the local machine costs more than it is worth, and a missing night is caught by USER noticing the gap (accepted tradeoff, 2026-08-01). If a firing is ever in doubt, the routine platform's own run record is where to confirm it.

**A non-clean night writes a findings note** listing each candidate with the SHA it was computed against, so the morning half (or USER) can act on it. **No commits. No PRs. No archival.** The night watcher's entire job is to notice, and to say so only when there is something to say.

---

# `/dream morning` — the actor (local)

Runs on the dev machine, where archiving is safe: **reversible, local, indexed, human present.** This is where v2 *acts* — the original evidence was "prune still owed, noticed 15×, acted 0×," and the acting is the whole point; it just relocated from expensive cloud PRs to cheap local archiving. It cleans **both** tmp directories the cloud cannot: `example-context/tmp/` and the gitignored `example-app/tmp/` (KD-10).

## Step 1 — Classify both directories

Fetch issue states with `gh` (you are local now), then run the classifier over each directory. `example-context/tmp/` is tracked, so use git time; `example-app/tmp/` is gitignored, so mtime is the only signal available — that is a known limitation, not a bug.

```
~/.claude/hooks/tmp-scan.sh --dir=<example-context>/tmp --repo-root=<example-context> \
    --time-source=git --issue-states=<...> --keep-list=<keep-list> --format=json
~/.claude/hooks/tmp-scan.sh --dir=<example-app>/tmp \
    --time-source=mtime --issue-states=<...> --keep-list=<keep-list> --format=json
```

The classifier is the same one `/tidy` uses, so the two can never drift. Its verdicts:
- **`delete`** — an unambiguous archive: a cited issue all-closed, a ticked `- [x] Done`, or a `mockup-*.html` untouched past 45 days. An open or unknown cited issue **keeps** the file (`skip` + `open-issue-keep`) — it is never even asked about (USER 2026-08-05: "if something is still open, you shouldn't ask me if I want to archive it"). This strengthened KD-14: the veto used to demote to `review`; now an open issue is a keep, self-expiring the moment every cited issue closes. The near-miss that forced KD-14 was a *delete* of this project's own framing doc while #1221 was open.
- **`review`** — ambiguous. Goes to human triage, never an automatic move.
- **`skip`** — suppressed: an in-file `(keep)` marker, a basename on the `--keep-list` (a `keep-registry` swipe from a previous morning), or a `keep-until-issue: #N` park whose issue N is still open. It does not surface again while parked.
- **`skip` → `delete` on close** — a `keep-until-issue: #N` park EXPIRES the moment N closes: the file leaves `skip` and becomes an archive candidate (signal `park-expired-N-closed`), so a pre-mortem archives itself once its issue ships without ever cluttering the triage pile in between.

## Step 2 — Archive the unambiguous

For each `delete` verdict, move the file into its sibling archive **with an index row, in one step** (KD-11):

```
~/.claude/hooks/archive-with-index.sh --file=<path> \
    --archive-root=<repo>/tmp/archive --index=<repo>/tmp/archive/INDEX.md
```

It never moves a file without writing its row (V5). Decision text is read from an explicit `## Decision` section or a `decision:` frontmatter key, **never inferred** — a file with no marker is still archived and its row reads "no explicit decision recorded". An index nobody can trust is worse than no index, because an index gets cited. **This is a local `mv` plus an index write — no branch, no commit, no PR.** Archival is reversible; that reversibility is precisely why the 45-day age trigger is allowed to auto-archive where a *delete* never could.

**An unchecked internal checkbox does NOT veto archival — all-cited-issues-closed outranks it (decided 2026-08-03, USER).** A `delete` verdict carrying `unchecked-remain` alongside `issues-all-closed` still archives: USER "sometimes just forgets the checkboxes", so an unchecked box is not reliable evidence of unfinished work, whereas a closed issue is a positive signal the work landed. The only signal that withholds automatic archival is an OPEN (or unknown-state) cited issue — KD-14 — which now keeps the file as `skip` + `open-issue-keep` (strengthened 2026-08-05 from the earlier demote-to-`review`: an open issue is a keep, not a triage question). This is the current classifier behavior (the `issue-closed.md` fixture archives despite `unchecked-remain`; it flips to `skip` the moment its cited issue's state is unknown/open); it is documented here so it reads as intent, not a bug to be "fixed" later.

## Step 3 — Triage the rest with decidr, only when there is a pile

**If Step 1 produced no `review` verdicts, skip this step entirely** — no deck, no prompt. decidr fires only when there is genuinely something to decide, so a morning with a clean review pile never interrupts. Doing the triage one-question-at-a-time in chat is what let "prune still owed" rot for 15 sessions; batching it means it only ever asks when the asking is warranted.

When there IS a `review` pile, put the whole of it in front of USER at once as a **decidr deck** (skill: `decidr`) — one card per `review` file, its signals and age in the body, three swipes:

- **Archive** → run `archive-with-index.sh` on it, exactly as Step 2.
- **Keep** → append its basename to the `--keep-list`. Next morning the classifier returns `skip` for it and it stops asking (`keep-registry`). This is the whole reason `--keep-list` exists.
- **Later** → append a line to `tmp/needs-triage.md`, leaving the file in place.

Author the deck, run `decidr <deck.json>` in the background, and read the answer file back when it exits (see the skill for the two hazards that will break the run if skipped). Everything ambiguous ends up either dispositioned, deferred to `needs-triage.md`, or silenced via the keep-list — nothing is guessed.

## Step 4 — `board-hygiene`, flag-only, local

`gh` reaches Project #1 here. Report **correction and consolidation candidates only** — "consolidate" means group related stale issues and nominate which **existing** issue absorbs the others, never an epic. **`gh issue create` and its MCP equivalents are not in dream's vocabulary at any tier** (KD-4/KD-5): the board stays product-only.

---

## Never, at any tier — night or morning

- Committing to `main` (KD-2 — the anti-pattern found in every shipped implementation researched)
- Opening, merging, or approving a PR — the night watcher opens none, and the morning actor archives locally without one
- **Deleting** a file. Dream archives and indexes; nothing in dream ever unlinks (Step 2 is a `mv` into `tmp/archive/`)
- **Creating** GitHub issues
- Editing `MEMORY.md` or anything under `memory/`
- Editing application code
- Editing `app-behavior-map.md` or `codebase-map.md` — the night watcher flags drift, forever; it never edits
- Archiving on a `review` verdict, or on `untracked-fallback` / unknown-issue age — those go to triage, never to an automatic move
- Asking a question at night. Nobody is watching. Record the blocker and continue. (The morning half is interactive by design — that is what decidr is for.)

## Still an open thread

- The **memory sweep** stays out of scope until `MEMORY.md` has a written, checkable definition of "lean" (KD-8) — unattended agents fail hardest on vague specs, and there is no threshold to hand a script yet.

*(Resolved 2026-08-01, #1221: the stored cloud routine prompt was rewritten to the v2 watcher contract — it now discovers the checkout root instead of assuming `$HOME` (container has `$HOME=/root`, repos under `/home/user`), symlinks hooks into `$HOME/.claude/hooks` to match dream.md's `~`, and dropped the retired v1 armed-execution / open-PR instructions and the `create_pull_request` tool.)*
