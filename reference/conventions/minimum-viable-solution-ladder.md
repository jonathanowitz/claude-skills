# Minimum-Viable-Solution Ladder (design convention)

**The inclination.** Solve like a lazy senior dev, not an eager LLM. The eager LLM's
default is to *generate* — reach for a component, a wrapper, a new abstraction. The senior
dev's default is to *avoid writing code at all*, and to reach for what already exists before
building. This ladder is that posture, made explicit.

**It is a design principle, not a code-reduction pass.** It operates at
**approach-selection** — when you decide *how* to solve the problem, before code exists.
It is NOT "write it, then shrink it." Shrinking-after means you already paid the tokens to
write the bloat and you're now editing instead of deciding. Walk the ladder when you pick
the approach; the small solution is a *choice*, not a cleanup.

**Read the problem first.** The ladder applies *after* you understand the affected code and
trace the actual flow — minimalism is not guessing-small, it's choosing the smallest thing
that genuinely solves the understood problem.

## The ladder

Before choosing how to build something, ask in order — take the first rung that answers yes:

0. **Is this scenario even real?** → Before building any branch, schema column, conditional,
   or test that handles a *user scenario*, confirm the scenario actually occurs in the product.
   Check project memory (e.g. `project_coaches_single_gym_no_name_collision`) and the real data
   (`seed.sql`, the actual tables) — a schema that *can* represent X is not evidence X *happens*.
   If the scenario doesn't occur, the branch is YAGNI; stop here. This fires *before* rung 1,
   because "does this need to exist" usually hinges on "does this case exist," and the check has
   to happen at design time — a review pass won't catch it, because reviewers reason *inside*
   whatever premise they're handed. **A dispatched agent inherits this blind spot**: its prompt
   must carry the product facts (who the user actually is, which scenarios are live), not just the
   technical spec — otherwise it hardens logic for a user who doesn't exist. (Evidence: 2026-07-16,
   three times in five days — a full parent-gym-qualifier span rule [6 tests + fixture + schema
   expansion] built for a multi-gym coach who doesn't exist ["way over thinking this"]; a decision
   question premised on "a gym's flagship team shares the gym's name," false per seed data; a
   multi-gym team-name collision assumed realistic from the data model's *capability*. The memory
   stating none of these occur was loaded the entire session but never queried at design time, and
   both cross-model reviewers reinforced the false premise instead of challenging it.)
1. **Does this need to exist at all?** → Skip it (YAGNI). Is there a product-level solution
   that removes the need? (See `pre-implementation-checklist.md` "Product solution first.")
2. **Already in this codebase?** → Reuse / adapt it. This rung *is* the Reuse Audit
   (`reuse-audit.md`) — Reuse / Adapt / Build-new.

   **UI sub-check (fires whenever the thing being built is an interactive or visual element):**
   Before "nothing found → Build-new," walk this order:
   - (a) **Design-system primitive already installed?** → use it. Check `components/ui/*`
     (shadcn components already in the repo) before writing a raw element.
   - (b) **Native HTML element covers it?** → use it. `<details>` / `<summary>` for
     expand-collapse; `<dialog>` for modals/overlays; `<input type="search|date|range|color|
     number">` for typed inputs; `<progress>` for progress bars. No JS needed.
   - (c) **Addable via one command?** → add it. `npx shadcn add <component>` is
     the locked primitive path for the rebuild stack (AS-7). Prefer this over hand-rolling
     a component that carries its own Tailwind class soup and accessibility re-implementation.
   - *Only if (a)–(c) all fail* → hand-roll with the minimum Tailwind needed.

   Evidence (2026-06-24, #960): shadcn Button adopted in 1 of ~10 components; ~19 raw
   `<button>` + 8 copy-pasted `<input>` hand-rolled across the app; pull-to-refresh
   hand-rolled when `react-simple-pull-to-refresh` existed and shadcn `sonner`/`scroll-area`
   covered adjacent needs. The rung-2 audit found "no existing button component" and called
   Build-new — technically true but rung 2a (design system) wasn't checked.

3. **Standard library does it?** → Use the stdlib.
4. **Platform-native feature?** → Use it. (e.g. `<input type="date">`, not a date-picker
   component; CSS `:has()`, not a JS observer.) — this rung catches non-UI platform features
   (CSS, Web APIs); UI elements are caught earlier at rung 2 sub-check (b).
5. **Installed dependency already provides it?** → Use the existing package; don't add a new one.
6. **One line?** → Write the one line.
7. **Otherwise** → Write the minimum that works for the understood problem.

## The safety floor — never on the chopping block

Minimalism never trades away **trust-boundary validation, data-loss handling, security, or
accessibility**. These are not "extra code" — they are part of the minimum that *works*.
The ladder reduces incidental complexity, never these.

## Worked example

A date field: 404 lines (custom component wrapping state, formatting, keyboard nav) vs. 23
lines using native `<input type="date">`. Both pass a Reuse Audit cleanly ("no existing date
field → Build-new") — the audit answers rung 2, but the 404-line miss is a **rung-2b failure**
(the UI sub-check: native HTML `<input type="date">` covers it). The ladder catches what the
audit alone does not.

A pull-to-refresh gesture: 80 lines of touch-event wiring + CSS vs. `npm install react-simple-
pull-to-refresh` (1 line). The rung-2 audit found no existing gesture handler and called
Build-new — correct for the codebase scan, but **rung-5 failure** (installed-or-addable
dependency). Check npm *before* concluding hand-roll is the minimum.

## Why this lives ambient, not gated

A design inclination must be present at *every* approach-selection moment — shaped work and
ad-hoc edits alike. You cannot gate "think like a senior dev" at a checkpoint; a checkpoint
fires after the approach is already chosen. So the principle is **always-loaded** (global
CLAUDE.md Critical Rule #5), reinforced at shaping (`reuse-audit.md`), and **backstopped** —
not implemented — at PR time (Pre-PR Validation Agent's over-engineering delete-list, which
*detects* when the inclination didn't fire, the same role the wiring-check plays).

(Source: ponytail scan, 2026-06-23 — the principle, not the third-party plugin.)
