# Session-Start Protocol

Run through these steps sequentially at the beginning of every session.

## 0. Read the workflow (code sessions)
- If this session involves writing or reviewing code, read `~/Projects/dev-reference/workflows/development-process.md` first. It defines the end-to-end sequence: frame → shape → implement → review → merge. Individual checklists enforce gates at each step, but `development-process.md` is the sequencing authority.

## 1. Check recent sessions
- Look at `~/.claude/sessions/` for the most recent session file
- Offer to review it for context on where things left off

## 2. Identify the project
- Check `~/.claude/project-index.md` for active projects
- Ask: Resume an active project, or starting something new?

## 3. Scope the session
- Ask: What's the goal today?
- Ask: How much time do you have?
- Plan scope to fit the available time
- **Time budget check:** If the goal involves shipping a feature but there are known infrastructure issues (test failures, env setup, Docker config), ask: "Is infrastructure work the priority, or should we ship the feature first?" Don't let infrastructure debugging consume a session intended for feature work without explicit approval.
  (Evidence: 2026-04-07/08 — two consecutive sessions consumed by e2e infrastructure instead of delay reporting feature. USER: "jesus we haven't done the actual work.")

## 4. Code-first recon (before any planning)

Do this **before** entering plan mode or proposing an approach:

- **`git -C <repo> fetch origin` then compare local `main` to `origin/main` FIRST** — `git -C <repo> rev-list --left-right --count main...origin/main`. If local `main` is behind, say so out loud and treat the local checkout as **stale until refreshed**. This is a hard gate before any of the recon below: a stale `main` makes "branch already exists?", "is this built?", reuse-audits, and every absence-claim ("X doesn't exist in the codebase") unreliable. New worktrees must be based off `origin/main` (`git worktree add <path> -b <branch> origin/main`), never local `main`.
  (Evidence: this is the #1 chronic theme across the 6/10–7/6 window — #937 red misdiagnosed as flake because local `main` was missing merged #935; a 4-fork reshape proposal built on "/my-results and /account don't exist" that was false because the checkout was 9 commits stale; a reuse-audit Explore agent returning "Build-new" from a tree 4 commits behind origin.)
- `git branch | grep <feature>` — does a branch already exist for this work?
- If branch exists: `git log <branch>` — is the work already done or partially done?
- Check `next-steps.md` for the target project — what's the current resume point?
- **Check the current project's briefs location for any brief matching the topic keywords** — its context sibling if one is declared (`resolve_product_field context_repo`; example-app → `example-context/briefs/`), otherwise the repo's own `briefs/` or `tmp/` — if a brief already exists, the session question shifts from "what are we doing?" to "where are we in this?" A brief in progress changes the framing entirely; find it before asking framing questions.
  (Evidence: 2026-05-31 — framing questions drafted without checking briefs directory; existing brief found mid-session and the framing restarted.)
- `gh pr list --repo <owner/repo>` — are there open PRs? Open PRs represent active work that may not be in `next-steps.md`.
- If a worktree exists for this project, check its `next-steps.md` too — the worktree is where active work lives, and its next-steps diverges from main.
- `gh issue list --repo <owner/repo>` — what issues are open?
- Cross-reference: do the issues match what's actually in the code?

**Why:** Docs and backlog files can be stale. The code repo is the source of truth. This step takes seconds and prevents planning work that's already built.

## 5. Enter plan mode only if needed

After recon confirms what actually needs to be done:
- If the work is non-trivial, enter plan mode
- If plan mode: include creating a feature branch as part of the plan
- If it's a quick fix: skip plan mode, commit to the current working branch

## 6. Confirm understanding

Before starting implementation:
- State what you're about to do and why
- Confirm USER agrees with the approach
- Flag any assumptions explicitly

## 7. Resume pointers are plan-snapshots, not constraints

When the last session's resume prompt (or `next-steps.md`, or a recent checkpoint) names a "next step," treat it as a **hypothesis about phase**, not a directive. The plan was correct when written; phase may have moved since.

**At session start, verify current phase with USER before driving toward a downstream gate.** Apply Critical Rule #3 (verify external claims before acting) to phase/sequence claims, not just code facts. The resume pointer is an external claim about where the work is — same evidence standard.

**Pattern:**
1. Read the resume prompt → form a hypothesis about phase.
2. State the hypothesis explicitly: "Resume says next is X — confirm X is still right, or has phase moved?"
3. Wait for confirmation before driving toward the downstream gate.

**Why:** Three sessions in 2026-05 anchored on stale resume-pointer plan:
- 2026-05-19 design-phase-methodology — resume said "dissect region by region"; methodology was novel and should have been the first deliverable.
- 2026-05-18 rebuild-architecture-review-experience-phase — drove toward §7 freeze on resume-pointer guidance; design-phase phase was actually the precondition.
- 2026-05-20 LB1-foldback — interpreted "try again / try again" as drain/fold-back directive; was actually a 529 retry.

Each instance cost a redirect before the session could proceed correctly. A 30-second confirmation at session start would have prevented all three.

## 8. Where formative artifacts go — the two-home rule (standing)

Sessions start in the code checkout, so the reflex is to write every scratch artifact to the nearest `tmp/` — which is the code repo's gitignored `tmp/`, where thinking artifacts orphan and pile up. Don't. When you write a **thinking artifact** this session — a pre-mortem, UI mockup, shaping/framing scratch, triage ledger or decidr deck — it goes in **`<context_repo>/tmp/`** (`resolve_product_field context_repo`; example-app → `~/Projects/example-context/tmp/`), never the code repo. Only **code-bound artifacts** (test plan, walk doc, migration draft) get copied into `<worktree>/tmp/` at worktree creation and committed with the code. Full rule + rationale: `conventions/formative-artifact-routing.md`. (Origin: example-app#1278.)
