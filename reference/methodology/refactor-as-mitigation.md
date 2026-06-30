# Refactor as Mitigation

When evaluating risks in an implementation plan, ask whether each risk is mitigated by **adding code where it currently lives** or by **extracting code into a new seam**. The second answer is often the right one and is almost always missed by a first-pass plan.

## When to Use

- During `/pre-mortem` synthesis — after personas have surfaced risks, before reporting to the user
- During `/shape-project` — when the technical approach says "modify file X" repeatedly for a single feature
- Mid-implementation — when scope expands and the plan starts adding more globals, more `if` branches, or more code to a file that's already crowded

## The Pattern

For each HIGH-severity risk in a plan, ask three questions:

1. **Where does the code live today?** Specifically — which file, which function, which globals.
2. **What does the proposed fix add to that location?** A new branch? A new global? A new lifecycle hook?
3. **Is there a missing seam the risk is pointing at?** If two unrelated features both want to read or write the same state, that state probably wants to be its own module. If a "fix" requires touching three sites, those three sites probably share a missing abstraction.

If the answer to #3 is yes, the right fix is **extraction**, not patching. The risk is a structural signal, not a bug to suppress.

### Diagnostic signals that extraction is the right move

- The plan modifies `app.js` (or any "god module") in 3+ places
- A risk is "this state is read by A, B, and C — what if they get out of sync?" → the state wants to be a module
- A risk is "we forgot to update site N when we added the new behavior" → the behavior wants a single API, not N call sites
- A risk is "this works for case X but not case Y" because the helper is inlined inside a function that doesn't see Y → extract the helper
- The brief introduces a new module BUT also requires modifications to several existing files → maybe more extraction would let the new module be self-contained

### What extraction looks like

- A pure function moved out of a method into a `lib/` file
- A bag of related globals moved into a state container module with `get`/`set`/`subscribe`
- An inline `if` chain moved into a strategy object or a pure dispatcher
- A serialization/persistence concern moved out of business logic into a dedicated module with a strict allow-list of fields

The test for "good extraction": the new module is **unit-testable in isolation**, with no DOM, no globals, no I/O.

### Offline-resilience check (mandatory for offline-first apps)

For projects in apps with offline-first guarantees (e.g., apps used in venues with bad connectivity), every proposed extracted module must be either:
- **Pure** (no network, no I/O), OR
- **Storage-only** (uses the same `localStorage`/`IndexedDB` surfaces the existing code already uses), OR
- **Reads in-memory state already populated by an existing network call** (e.g., reads from `window.allEntries` after the existing `loadData()` call has run)

An extraction that introduces a **new** network dependency is not a safe refactor for offline-first apps — it trades one problem (coupling) for a worse one (connectivity-dependent failure). When a module would need network access, find a way to keep that I/O in the existing seam (typically `app.js` data-loading code) and have the new module operate purely on the already-loaded data.

**Verify before committing the refactor:** for each new module, grep the proposed file for `fetch`/`XHR`/`navigator.online`/`Cache.match` and confirm zero matches that aren't already present in the existing equivalent code. Then add an explicit airplane-mode test to the brief's Verification section so the check survives implementation drift.

(Evidence: 2026-04-09 — during the refactor pass on #561, USER flagged the offline-resilience question explicitly. Verifying that all 7 proposed modules were pure client-side / in-memory was the gate for the refactor. If even one had introduced a `fetch`, the approach would have been wrong for an app used in venues with bad cell signal.)

## Why This Matters

A first-pass plan tends to follow the path of least friction — modify the file where the code currently lives. This grows god modules, multiplies state-of-truth, and makes every future change to that area more expensive. Pre-mortem agents and shaping agents are particularly susceptible because they're answering the question "what could go wrong with the proposed approach" rather than "is the proposed approach the right shape."

When refactor-as-mitigation is missed, the consequences cascade:
- The new feature ships with the same coupling problems the existing code had
- Tests for the new feature have to mock more, exercise less
- The next feature in the same area inherits the problem and adds to it
- The "small follow-up cleanup" never happens because the cost is now too high

When refactor-as-mitigation is applied:
- The new feature is built on a smaller, more testable foundation
- The existing code shrinks (sometimes dramatically) instead of growing
- Adjacent features become easier to ship because the seams are already cut
- HIGH risks become MEDIUM or disappear entirely because the structural cause is gone

## How to Apply

**During pre-mortem synthesis:** After collecting persona findings, run an explicit "refactor-as-mitigation pass" before reporting. For each HIGH risk, ask the three questions above. If extraction is the answer, the recommendation isn't "fix the risk in place" — it's "extract this seam, then the risk doesn't apply." Group such risks together so the user can see the structural opportunity at a glance.

**During shape-project:** When the technical approach lists changes to >2 files for a single feature, pause and ask whether one of those files should be split first. The brief should include explicit "extract X" steps as their own phase before the feature work, not commingled with it.

**During implementation:** If you find yourself adding a third `if` to a function or a fourth global to a module, stop and propose extraction to the user. The cost of extraction is highest at the start of a session and lowest right before the first commit.

## Evidence

- 2026-04-09 — Pre-mortem on the "Competitor Pills from Expandable Cards" brief (#561) returned 15 HIGH risks across 7 personas. The first-pass synthesis recommended fixes that would have added significant code to `web/app.js` (a god module that was already the source of multiple risks). A single user question — "of these issues, which can/should be mitigated by a targeted refactor?" — surfaced that **9 of the 15 HIGH risks could be eliminated by extracting 6 new pure modules** (`competitor-context.js`, `competitor-reveal.js`, `active-filters.js`, `filter-summary.js`, `filter-persistence.js`, `subscription-tier.js`) instead of patching `app.js`. The refactor approach made `app.js` *shrink* across the implementation slices instead of growing, eliminated an entire class of state-leakage risks (because the state had a single owner), and made all new logic unit-testable in isolation. The pre-mortem agents had not surfaced any of these extractions on their own — they evaluated the proposed approach for risks rather than asking whether the approach itself was the right shape.

## See Also

- `methodology/breadboard.md` — shaping the seams up front
- `methodology/vertical-slice-pattern.md` — slicing work so extractions can happen as their own slice
- `conventions/build-project-principles.md` — wrong-level-of-solution patterns
- `commands/pre-mortem.md` — the skill that this lesson reorients (Step 4.5 references this file)
