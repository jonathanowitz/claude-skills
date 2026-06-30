# Reuse Audit (shaping convention)

**Purpose.** Force every shaped brief to inventory existing code and justify any net-new build *before* the Technical Approach is locked — so the same capability (fuzzy matching, normalization, validation, data-access, …) doesn't get re-implemented divergently per feature. Divergent-implementation sprawl is a future consistency bug plus a consolidation cost; the audit catches it at shaping time, before code.

**Where it runs.** As a step in `/shape-project`, after Concept + Core Features are drafted and **before** the Technical Approach is finalized (reuse decisions *shape* the approach; a trailing audit just rationalizes a greenfield design already written). It runs *before* the Design-Robustness and Refactor-as-Mitigation passes.

**Scope.** The **rebuild stack** — `app/src/`, `contract/`, `api/_src/`. The shipped legacy stack is frozen and out of scope.

**Propagation.** The audit's output is a required `## Reuse & Adaptation` section in the shaped brief. `/implement` consumes that brief as its input, so the reuse decisions reach implementation and its sub-agents for free — no separate dispatch step is needed. The brief *is* the propagation mechanism.

---

## The 4-step audit

### 1. Name the capability families

State the work in terms of **capabilities**, not implementation names — "this needs fuzzy matching," not "a new `searchPrograms` function." Naming by capability is what makes prior art findable across differently-named copies (the unified-search matchers were all "search" but named three different things).

**Capability-family vocabulary** (starter list — grows from real audit findings, see Governance):

- **matching / search** — fuzzy or exact name/entity matching, ranked search, similarity scoring
- **normalization** — canonicalizing names, strings, identifiers, keys
- **validation** — shape/format/business-rule checks, zod contracts, input guards
- **data-access** — DB reads/writes, query builders, RLS-aware fetchers, caching layers
- **formatting / serialization** — rendering, derived keys, payload shaping, date/number formatting
- **auth / permission gating** — admin/role checks, RLS boundaries, session/identity guards
- **state containers** — shared client state, query state, stores

If the brief touches a capability not in the list, name it anyway and flag it for the Governance pass.

### 2. Inventory prior art

For each named family:

1. **Cheap first pass — the codebase map.** Read the relevant section of the rebuild map (`example-context/architecture/codebase-map.md`) for that family. Free, already-structured.
2. **Live confirm — one Explore.** Dispatch **one** Explore agent that searches *all named families in parallel* over `app/src/`, `contract/`, `api/_src/`. The map can be stale, so the live pass is mandatory — a stale map degrades to "slightly more Explore work," never to "missed prior art." Do not run a serial Explore per family.
3. **UI / interaction capability — also check design system and library before concluding "none found."** If the capability family is UI or interaction (a button, input, overlay, menu, gesture, form control, disclosure, progress indicator), the codebase scan is *not* sufficient on its own — prior art also lives *outside* the codebase:
   - **Design-system primitive:** `components/ui/*` — shadcn components already installed.
   - **Native HTML element:** `<dialog>`, `<details>`, `<input type="search|date|range|...">`, `<progress>`.
   - **One-command add:** `npx shadcn add <component>` — the locked primitive path for the rebuild stack (AS-7).
   - **Established npm package:** for gestures/interactions not covered by the above (e.g. pull-to-refresh), check npm before hand-rolling.
   A "none found" classification for a UI capability that didn't check these four is an **incomplete audit** — the same standard as a Build-new with no justification (step 4).
   (Evidence: #960 — pull-to-refresh classified Build-new after codebase scan; `react-simple-pull-to-refresh` + shadcn primitives not checked. ~19 raw `<button>` + 8 raw `<input>` hand-rolled while `components/ui/button.tsx` was installed and unused.)

Record what each pass found (or didn't).

### 3. Classify each proposed piece of work

| Decision | Meaning |
|---|---|
| **Reuse** | Call the existing implementation as-is |
| **Adapt** | Extend / parameterize / generalize the existing implementation |
| **Build-new** | No prior art, or prior art genuinely wrong-shaped |

**Adapt-vs-Build-new heuristic** (closes the ambiguity that lets a rewrite hide as an "Adapt"): if the change would introduce **breaking changes for existing callers** *or* **fundamentally broadens the capability's original responsibility**, classify it **Build-new** (which may deprecate/replace the old) and justify — don't call it an Adapt. "Adapt" is for additive, backward-compatible extension.

> This audit is **rung 2** of the [minimum-viable-solution ladder](minimum-viable-solution-ladder.md); the other rungs (skip / stdlib / platform-native / one-line) operate at the same design-altitude. A clean Build-new here can still be over-built — see the date-picker example in the ladder doc.

### 4. Justify every Build-new

A Build-new with no justification is an **incomplete audit**. The justification must **reference the specific prior art considered and why it was unsuitable** — not a generic "nothing fit." Example: *"Rejected client-side `DiceMatcher` — this requires a server-side indexed match over 1,444 rows; the existing matcher pulls to the client and can't scale per-keystroke."* This makes the guardrail auditable rather than rhetorical, and is what stops it decaying into a rubber-stamp.

---

## Output: the `## Reuse & Adaptation` brief section

Every shaped brief carries this section. The header **must** include the machine-readable anchor so a future mechanical gate can grep a stable marker rather than human-editable header text:

```markdown
## Reuse & Adaptation <!-- reuse-audit-section -->

| Capability | Prior art found | Decision | Rationale |
|---|---|---|---|
| fuzzy matching | [`search_program_teams_fuzzy`](path/in/codebase-map.md), client `resolveProgram` | Adapt | Generalize the SQL trigram path to a shared scorer; additive, no caller breakage |
| program normalization | (none found) | Build-new | Rejected `normalizeGymName` — that canonicalizes gyms, not programs; different token rules |
```

- **Capability** — from the family vocabulary (step 1).
- **Prior art found** — link to the `codebase-map.md` section or source file when found there; "(none found)" if the inventory came up empty.
- **Decision** — Reuse / Adapt / Build-new (step 3).
- **Rationale** — *why this prior art* (for Reuse/Adapt) or *why nothing fit* (mandatory for Build-new, per step 4).

**Edge — no capability applies.** For a pure-config or copy-only brief, record one row: "no reusable capabilities; net-new is the surface itself" — don't skip the section. Its absence means an incomplete brief.

---

## Ordering vs. Refactor-as-Mitigation

These two passes are complementary and must not collide:

- **Reuse Audit (this doc) — horizontal:** *Does this capability already exist elsewhere?* → decide Reuse / Adapt / Build-new.
- **Refactor-as-Mitigation — vertical:** *If I'm building, am I building into a god module, and where does the new code land safely?*

**Run the Reuse Audit first** (decide reuse vs. build), **then** Refactor-as-Mitigation (for whatever is Build-new/Adapt, decide where it lands).

---

## Governance

USER owns this doc. The capability-family vocabulary grows **bottom-up** — a new family is proposed by the audit finding that needed it — but is **ratified by USER before being added**, so the list stays small and non-overlapping rather than bloating. Don't silently add families mid-audit; name the gap, ship the brief, propose the addition.

---

## Compliance levers (escalating)

Pure-instruction guardrails decay in this workflow (the wiring-check failed 3× and the seam-traversal gap recurred until each was made mechanical). The Reuse Audit is defended in escalating order:

1. **Structural (live):** `## Reuse & Adaptation` is a required brief section — a brief missing it is visibly incomplete, the same forcing function as Behavior Map Entries and Verification.
2. **Checklist (live):** `workflows/pre-implementation-checklist.md` verifies the brief carries a non-empty section before implementation.
3. **Mechanical gate (deferred, pre-wired):** a hook that greps the `<!-- reuse-audit-section -->` anchor and blocks `/implement` if absent. Not built yet; the anchor exists so it's a trivial retrofit. If reuse compliance decays the way wiring-check did, build it — don't relitigate.
