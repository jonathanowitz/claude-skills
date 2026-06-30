# Build Project Principles

Reference this document when initiating projects that involve building software.

---

## Slice Ordering Principles

### Don't Defer Data Infrastructure
- **Persistence (localStorage, database)** - Build into first slice
- **State management patterns** - Establish early
- **API structure** - Define before building UI

**Rationale:** Adding infrastructure later means retrofitting every component. 10% more work upfront saves refactoring later.

### Safe to Defer
- UI polish and styling (build first, polish later)
- Interaction enhancements (drag-drop, animations)
- Edge case handling (get happy path working first)
- Advanced features beyond MVP

---

## Vertical Slice Sequence

Typical order for web apps:

1. **Data infrastructure** - Persistence, state shape, load/save
2. **Core CRUD** - Create/read/update/delete for primary entities
3. **Core logic** - The algorithm or business rules
4. **Navigation** - Tabs, routing, page structure
5. **Edit capabilities** - Inline editing, forms
6. **Polish** - UI modernization, empty states, error handling
7. **Enhancements** - Drag-drop, animations, advanced interactions

---

## Review a slice at its build fidelity

When walking or reviewing a slice, judge it against the fidelity it was *built* to — not a higher one. The review question must match what the slice actually produced.

- **Structural / IA slice rendered in wireframe tokens** (e.g. a rebuild's early shells): the human walk judges the STRUCTURAL decision — information architecture, what's present vs absent, navigation model — NOT visual cohesion or polish. "Does it look like a finished, cohesive app?" is unanswerable (and misleading) at wireframe fidelity.
- **Don't import polish-level review questions into a structural slice.** If the slice deliberately didn't build polish ("build first, polish later"), don't ask the reviewer to judge polish.
- Behavioral correctness is usually covered by tests/CI — reserve the human walk for the judgment tests can't make, and scope that judgment to the fidelity in front of the reviewer.

*Evidence: 2026-06-25 example #974 (Fan Shell → D1 chrome). The walk checklist asked "does the home read as one cohesive app?" USER: "it's not a cohesive app yet — it's just a bunch of shells because we are working with wireframes." The structural decision (header chrome, no tab bar, account route) was the only thing to judge; cohesion was the wrong yardstick.*

---

## UI Building Guidelines

### Special Characters in Buttons
Special characters (×, →, ←, etc.) have irregular font metrics and won't visually center even when CSS says they're centered.

**Solution:** Use `transform: translateY()` adjustments or actual SVG icons rather than trusting text alignment.

```css
.delete-icon {
  transform: translateY(-2px); /* Adjust based on font */
}
```

---

## UI Mockup Conventions

Mockups created during shaping must use the **actual project HTML, CSS, and design tokens** — not approximations.

### Rules
1. **Copy real CSS** — Import or inline the project's `design-tokens.css` variables and relevant `style.css` rules. Don't approximate colors, radii, or shadows from memory.
2. **Copy real HTML structure** — Use the actual header, card, button, and layout markup from the app. The mockup should look like the app, not a generic wireframe.
3. **Use real SVGs and assets** — Copy the logo SVG, icons, etc. from the source files.
4. **Show realistic content** — Use actual competition names, dates, and locations from the domain, not lorem ipsum.
5. **New elements only** — Only write new HTML/CSS for the parts that don't exist yet. Everything else comes from the codebase.

**Why:** A mockup built from scratch looks different enough from the real app that USER has to mentally translate between the two. Using real styles eliminates that gap and makes review faster.

(Evidence: 2026-03-26 — first mockup for unauth landing used approximated colors and layout, missed the dark theme entirely, and didn't match the actual card styles. Rebuilt from real CSS in 10 minutes.)

---

## Design Robustness Checklist

During shaping, after drafting the initial design, do a second pass for failure modes and operability. Don't defer these as "future polish" if they're cheap to add now.

### 1. What breaks if someone forgets a step?
If the design requires manual coordination (e.g., every consumer must call `next()` after finishing), ask whether the system can own the control flow instead. Promises, callbacks, and event-driven patterns move responsibility from the caller to the infrastructure.

**Example:** A manual `OverlayQueue.next()` call in every dismiss handler creates coupling and a stuck-queue risk. A Promise-based design where `showFn` returns a Promise that resolves on dismiss lets the queue auto-advance — no manual step to forget.

### 2. What does this need to be operable?
Production code needs observability. If the answer to "why didn't X happen?" requires reading source code, add:
- **Debug logging** — state changes, decisions, queue contents
- **Cancel/clear** — ability to remove items or reset state
- **Lifecycle hooks** — `onEmpty`, `onShow`, `onError` callbacks for coordination with other systems

### 3. What's cheap now but expensive to retrofit?
If adding something later means modifying every consumer, it belongs in the initial design:
- Configurable delays or transitions (one line in a loop vs. N setTimeout changes)
- Callback hooks (one property vs. event emitter retrofit)
- Return-value contracts (`showFn` returns `false` to skip vs. adding a pre-check layer)

**Rule of thumb:** If it's ≤5 lines in the infrastructure and saves touching N consumers later, include it now.

*Evidence: 2026-03-20 overlay queue shaping — initial design used manual `next()` callbacks. Promise-based auto-advance was ~5 lines more in the queue manager but eliminated coupling to every overlay's dismiss handler. Operational affordances (cancel, debug logging, onEmpty, transition delay) added ~15 lines total.*

---

## Propagation: the shaped brief is the carrier, not a new dispatch step

When a workflow change needs to reach implementation work or dispatched sub-agents, the propagation mechanism is **the shaped brief itself** — not a new step in `/implement` or its dispatch protocol. `/implement` takes the shaped brief as its input, so anything written into the brief (e.g. a required section) reaches implementation and its sub-agents for free.

Adding a "cite section X" / "pass through Y" line to `implement.md` re-states what's already in the document `/implement` consumes — pure duplication, and often the exact drift a guardrail exists to prevent. It also collapses any refactor-as-mitigation "extract to a shared doc so two skills don't drift" justification, because there's then only **one** skill consumer (the shaper), not two.

**Rule of thumb:** When a design proposes "make `/implement` do Z so sub-agents inherit it," stop and ask — is Z already in the brief? If yes, the brief carries it downstream; no skill edit needed.

*Evidence: 2026-06-17 #896 (Reuse-Audit shaping step). First draft added an `implement.md` dispatch mirror + justified extracting the audit procedure to a shared doc on "two skills need it → avoid drift." The mirror was duplication — `/implement` already reads the brief's `## Reuse & Adaptation` section. Dropped the mirror, dropped the dual-consumer justification, narrowed the change to one skill edit (`shape-project.md`) + one convention doc.*

---

## Reference Files

When building, also reference:
- `voice/USER-ui-preferences.md` - Tech stack, visual design, interaction patterns
- `methodology/vertical-slice-pattern.md` - Multi-day project structure
- `methodology/breadboard.md` - Circuit-style breadboarding
