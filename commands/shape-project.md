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
4. Read `~/Projects/claude-config/project-briefs.md` to understand the brief format
5. Create a shaped project brief using the problem brief as foundation, following the format in project-briefs.md:
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
   2. **Inventory prior art** for each family: cheap first pass against the rebuild map (`~/Projects/example-context/architecture/codebase-map.md`), then **one** parallel Explore agent over `app/src/`, `contract/`, `api/_src/` (the map can be stale; the live pass is mandatory).
   3. **Classify** each proposed piece of work as **Reuse** / **Adapt** / **Build-new** (apply the Adapt-vs-Build-new heuristic: breaking changes for callers OR broadened responsibility → Build-new).
   4. **Justify** every Build-new by naming the specific prior art rejected and why it was unsuitable — a generic "nothing fit" is an incomplete audit.

   Write the result into the brief's required `## Reuse & Adaptation <!-- reuse-audit-section -->` section (table: capability · prior art found w/ map link · decision · rationale), and let the reuse decisions shape the Technical Approach. Scope is the rebuild stack (`app/src/`, `contract/`, `api/_src/`); the shipped legacy stack is frozen and out of scope. The audit runs **before** the Design-Robustness and Refactor-as-Mitigation passes.
7. **Design robustness pass** — After drafting the technical approach and code affordances, run through the Design Robustness Checklist in `~/Projects/dev-reference/conventions/build-project-principles.md`. Ask: (1) What breaks if someone forgets a step? (2) What does this need to be operable? (3) What's cheap now but expensive to retrofit? Incorporate findings into the design before sending to Gemini.
8. **Refactor-as-Mitigation pass** — Mandatory. Read `~/Projects/dev-reference/methodology/refactor-as-mitigation.md` and apply it to the technical approach you just drafted. Specifically, ask:
   - Does the technical approach modify a single "god module" (e.g., `app.js`) in 3+ places? If yes, the brief should propose extracting one or more of those sites into new modules **before** building the feature.
   - Does any new state in the brief have multiple owners or live in a place that doesn't already own related state? If yes, propose extracting a state container module.
   - Does any code affordance say "modify file X" while X is already crowded or implicated in the problem statement? If yes, propose splitting X first.
   - Does the brief introduce a new module BUT also require modifications to several existing files? If yes, ask whether more extraction would let the new module be self-contained.

   When refactor opportunities are found, restructure the brief: add a "Pre-Feature Refactor" section listing each proposed extraction (module name, what it owns, why it's needed, which risks it eliminates), and update the slice plan so the refactor lands as its own slice (or set of slices) **before** the feature slices. The refactor is part of the feature, not a follow-up — follow-ups never happen.

   Default to recommending extraction for new features. Default to patching for narrow bug fixes. Make the choice explicit in the brief.
9. **Send to Gemini (via `agy`) for cross-model review** — this is mandatory before presenting to USER. Inline the brief (now including the refactor-as-mitigation pass output) into a prompt file and run `agy --model "Gemini 3.1 Pro (Low)" -p "$(cat /tmp/agy-brief-review.txt)"` and ask it to review for completeness, breadboard quality, risks, behavioral gaps, and copy/UX. (`agy` is the Antigravity CLI; `gemini` is dead — issue #823. `--model` is mandatory and takes the display string; there is no `-m` flag.) Incorporate feedback, then document what was changed in a "Cross-Model Review" section at the bottom of the brief.
10. Add the new brief to project-briefs.md under "## Project Briefs"
11. Update the priority table in project-briefs.md (add as lowest priority initially)
    - NOTE: The priority table only lives in project-briefs.md (single source of truth)
12. Use AskUserQuestion to confirm the priority ranking or ask where to place it
13. Move the project from "Active Ideas" to "Archived Ideas" in project-ideas.md
14. Summarize what was done

## UI Mockup Protocol

When the shaping process involves any UI changes (new screens, layout adjustments, component additions, navigation changes, etc.):

1. Create a standalone HTML reference file at `tmp/mockup-<project-slug>.html`
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
