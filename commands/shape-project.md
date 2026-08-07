---
description: Convert an unshaped project idea into a shaped brief for prioritization
argument-hint: <project name from ideas file>
allowed-tools: [Read, Edit, Write, AskUserQuestion]
---

# Shape Project

Shape the project idea: $ARGUMENTS

## Instructions

1. Read `~/.claude/project-ideas.md` and locate the project matching $ARGUMENTS
2. Verify that a problem brief exists with status "Framed — ready for `/shape-project`"
3. If the problem hasn't been framed yet, tell USER to run `/frame` first and stop
3a. **Verify the framing premise still holds — REQUIRED before building the brief.** A framing doc is a hypothesis with a timestamp, and a later reframe/epic issue can silently supersede it; shaping as-framed then builds on a dead premise. Before drafting anything: (1) note the framing doc's date; (2) check it against any newer reframe/epic issues the work touches — `gh issue list` / `gh issue view` for issues that changed the model or vocabulary this brief assumes; (3) grep-verify that the specific route, RPC, table, or model the framing assumes still exists in the current source (`grep` the route, the RPC — don't trust the framing doc's word for it). If the premise has moved, re-frame against current reality before shaping — do not shape the stale version. (Evidence 2026-08-03: #1207 was framed 2026-07-23 as a fan "team page (a place)"; #1224 retired team-as-a-place on 2026-07-27 — team became a SUBJECT — and #1232 confirmed the fan shell has zero entity destinations. Shaping #1207 as-framed would have built a screen the product no longer had a place for. IDs are identity, vocabulary is inherited-hypothesis — see `~/.claude/projects/-Users-USER-Projects-example-app/memory/feedback_ids_are_identity_names_are_display.md`.)
4. Read `~/Projects/claude-config/project-briefs.md` to understand the brief format
5. Create a shaped project brief using the problem brief as foundation, following the format in project-briefs.md:
   - **`issue:` frontmatter (REQUIRED):** Open the brief with a YAML frontmatter block carrying `issue: <NN>` — the example-app issue number this brief tracks. This is the authoritative, machine-readable brief→issue link that `/dream`'s brief-shipped job reads to decide when a brief has shipped; it must NOT be inferred from a prose `**GitHub:**` line or a body `#NN` (IDs are identity, prose is display). If the issue isn't filed yet, write `issue: null  # not yet filed` — brief-shipped skips a null/absent key rather than guess. Update it to the real number when the issue is created.
   - **Status:** Set to "Queued - needs shaping" or similar
   - **Concept:** Derived from the problem statement — what we're solving and why
   - **Core Features:** Designed to address the problem's success criteria
   - **Technical Approach:** Informed by constraints identified in the problem brief — and by the Reuse Audit (step 6); draft it *after* the audit so reuse decisions shape the approach rather than rationalize a greenfield design.
   - **Reuse & Adaptation:** REQUIRED section (output of the Reuse Audit, step 6). Header must carry the anchor: `## Reuse & Adaptation <!-- reuse-audit-section -->`. A brief missing this section is incomplete. See `~/Projects/dev-reference/conventions/reuse-audit.md` for the table format.
   - **Effort:** Estimate based on scope (Low/Medium/High/Very High)
   - **Key Decisions:** Surface important decisions from the answers
   - **Breadboard:** This is mandatory for any feature that has user-facing flows. A breadboard is NOT a mockup — it is structured text with:
     - **UI Affordances table** — ID, Place, Affordance, Type (display/action/input/trigger)
     - **Code Affordances table** — ID, Operation, Description
     - **Wiring table** — From, To, Condition (how affordances connect)
     - **Shared State table** — State, Storage, Read By, Write By
     - **Visual Wiring Diagram** — Mermaid flowchart showing the full flow
     - Reference format: `briefs/schedule-intake-pipeline.md` and `briefs/archive/home-gym-recovery-prompt.md`
   - **Behavior Map Entries:** Draft the entries that will be added to `app-behavior-map.md` before implementation. Each entry should be plain-language: "When [user does X], [Y happens]". Include edge cases and error states. Tag each `[untested]` — the tag gets updated to `[unit]` or `[E2E]` when tests are written.
   - **Verification:** Define what tests should exist before the feature is considered complete:
     - Unit tests: which files need tests, what scenarios to cover
     - E2E tests: which user flows need Playwright specs, what to assert
     - Which behavior map entries each test covers
     - What's exempt from automated testing and why (CSS-only, native-only, etc.)
   - **First Steps:** Suggest 3-4 concrete next steps
6. **Reuse Audit** — Mandatory, and run it *before* finalizing the Technical Approach. Read `~/Projects/dev-reference/conventions/reuse-audit.md` and apply the 4-step audit to the work this brief proposes:
   1. **Name the capability families** the work touches (matching/search, normalization, validation, data-access, formatting/serialization, auth/permission gating, state containers, …) — in capability terms, not function names.
   2. **Inventory prior art** for each family: cheap first pass against the current repo's own codebase map (its declared `context_repo` in `.claude/product.json`, if any — example-app's is `~/Projects/example-context/architecture/codebase-map.md`), then **one** parallel Explore agent over the repo's own source dirs (example-app's rebuild stack is `app/src/`, `contract/`, `api/_src/` — a worked example, not a universal path; the map can be stale, so the live pass is mandatory).
   3. **Classify** each proposed piece of work as **Reuse** / **Adapt** / **Build-new** (apply the Adapt-vs-Build-new heuristic: breaking changes for callers OR broadened responsibility → Build-new).
   4. **Justify** every Build-new by naming the specific prior art rejected and why it was unsuitable — a generic "nothing fit" is an incomplete audit.

   Write the result into the brief's required `## Reuse & Adaptation <!-- reuse-audit-section -->` section (table: capability · prior art found w/ map link · decision · rationale), and let the reuse decisions shape the Technical Approach. Scope is the current repo's own source tree (example-app's rebuild stack — `app/src/`, `contract/`, `api/_src/` — is a worked example; example-app's shipped legacy stack there is frozen and out of scope). The audit runs **before** the Design-Robustness and Refactor-as-Mitigation passes.
7. **Design robustness pass** — After drafting the technical approach and code affordances, run through the Design Robustness Checklist in `~/Projects/dev-reference/conventions/build-project-principles.md`. Ask: (1) What breaks if someone forgets a step? (2) What does this need to be operable? (3) What's cheap now but expensive to retrofit? Incorporate findings into the design before sending to Gemini.
8. **Refactor-as-Mitigation pass** — Mandatory. Read `~/Projects/dev-reference/methodology/refactor-as-mitigation.md` and apply it to the technical approach you just drafted. Specifically, ask:
   - Does the technical approach modify a single "god module" (e.g., `app.js`) in 3+ places? If yes, the brief should propose extracting one or more of those sites into new modules **before** building the feature.
   - Does any new state in the brief have multiple owners or live in a place that doesn't already own related state? If yes, propose extracting a state container module.
   - Does any code affordance say "modify file X" while X is already crowded or implicated in the problem statement? If yes, propose splitting X first.
   - Does the brief introduce a new module BUT also require modifications to several existing files? If yes, ask whether more extraction would let the new module be self-contained.

   When refactor opportunities are found, restructure the brief: add a "Pre-Feature Refactor" section listing each proposed extraction (module name, what it owns, why it's needed, which risks it eliminates), and update the slice plan so the refactor lands as its own slice (or set of slices) **before** the feature slices. The refactor is part of the feature, not a follow-up — follow-ups never happen.

   Default to recommending extraction for new features. Default to patching for narrow bug fixes. Make the choice explicit in the brief.
9. **Send to Gemini (via `agy`) for cross-model review** — this is mandatory before presenting to USER. Inline the brief (now including the refactor-as-mitigation pass output) into a prompt file and run `agy --model "Gemini 3.1 Pro (Low)" -p "$(cat /tmp/agy-brief-review.txt)"` and ask it to review for completeness, breadboard quality, risks, behavioral gaps, and copy/UX. (`agy` is the Antigravity CLI; `gemini` is dead — issue #823. `--model` is mandatory and takes the display string; there is no `-m` flag.) Incorporate feedback, then document what was changed in a "Cross-Model Review" section at the bottom of the brief.
10. **Pre-mortem gate — MANDATORY, every brief, not conditional on effort.** After the Gemini pass, run the `pre-mortem` skill on the brief you just wrote (7 expert personas independently surface failure modes). Fold every surviving finding into the brief and record the run in a `## Pre-Mortem` section. This is the failure-first lens — structurally different from the Gemini/robustness/refactor passes (which are completeness/quality lenses) — and it is the single most common thing a shaped brief is missing. Do NOT present the brief for the go without it. If a brief is so trivial a pre-mortem is genuinely wasted, say so explicitly to USER and get his skip — never skip silently. (Added 2026-08-06 after this gate drifted out of practice: 0 of the last 5 briefs, 21/65 all-time, had one.)
11. Add the new brief to project-briefs.md under "## Project Briefs"
12. Update the priority table in project-briefs.md (add as lowest priority initially)
    - NOTE: The priority table only lives in project-briefs.md (single source of truth)
13. Use AskUserQuestion to confirm the priority ranking or ask where to place it
14. Move the project from "Active Ideas" to "Archived Ideas" in project-ideas.md
15. Summarize what was done

## UI Mockup Protocol

When the shaping process involves any UI changes (new screens, layout adjustments, component additions, navigation changes, etc.):

1. Create a standalone HTML reference file at `<context_repo>/tmp/mockup-<project-slug>.html` — the context sibling resolved via `resolve_product_field context_repo` (example-app → `~/Projects/example-context/tmp/`), NOT the session-cwd `tmp/`. A mockup is a thinking artifact; it belongs in the context repo, never in the code repo. See `conventions/formative-artifact-routing.md`. (Repo with no `context_repo` declared: fall back to the repo's own `tmp/`.)
2. The file should be a self-contained visual mockup (inline CSS, no external dependencies) that shows the proposed UI changes
3. Use realistic placeholder content — not lorem ipsum — based on the project's domain
4. Include a header comment explaining what the mockup represents and which parts are new/changed
5. Present the mockup to USER for review before finalizing the brief's UI-related sections
6. The mockup is a shaping artifact, not production code — it's meant to communicate intent and get alignment on layout/flow before any real coding begins

## Guidelines

- Be thorough - use all the shaping answers to inform the brief
- Keep the brief format consistent with existing entries
- Effort estimates: Low (1-2 weeks), Medium (2-4 weeks), High (1-3 months), Very High (3-6+ months)
- Always ask about priority placement rather than assuming
- Mark the original idea as archived but keep it for reference
- If the project touches UI, follow the UI Mockup Protocol above before finalizing the brief
