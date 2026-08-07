# Breadboarding

**Purpose:** Map the solution as a circuit diagram - places, affordances, and wiring - before coding.

---

## File Naming Convention

**Always include the project name in breadboard files:**
- Filename: `breadboard-[project-name].md` (e.g., `breadboard-exampleapp.md`)
- Header: Include project name prominently at the top

This prevents confusion when working across multiple projects.

---

## What is a Breadboard?

A breadboard is analogous to a circuit diagram in electronics. It shows:
- **Places:** Key screens, pages, or contexts (like components on a board)
- **Affordances:** Things users can interact with AND code operations (like pins on components)
- **Wiring:** How affordances connect to each other (like traces on a circuit board)

**This is NOT a wireframe or UI mockup.** No visual layout, no boxes, no pixel details.

---

## The Ryan Singer Method (Shape Up)

To breadboard properly, Claude Code needs to enumerate all affordances - both frontend and backend - then wire them together.

### Step 1: List UI Affordances

Create a table of everything the user can interact with:

| ID | Place | Affordance | Type |
|----|-------|------------|------|
| U1 | Login | Email input | input |
| U2 | Login | Password input | input |
| U3 | Login | Login button | action |
| U4 | Dashboard | Projects list | display |
| U5 | Dashboard | Create project button | action |

### Step 2: List Code Affordances

Create a table of backend operations:

| ID | Operation | Description |
|----|-----------|-------------|
| C1 | validateCredentials | Check email/password against database |
| C2 | createSession | Generate auth token, store session |
| C3 | fetchProjects | Load user's projects from database |
| C4 | createProject | Insert new project record |

### Step 3: Create Wiring Table

Show how each affordance connects to others:

| ID | Wires To | Condition |
|----|----------|-----------|
| U3 | C1 | on click |
| C1 | C2 | on success |
| C1 | U3 | on failure (show error) |
| C2 | U4 | redirect to dashboard |
| U5 | C4 | on click |
| C4 | C3 | on success (refresh list) |

### What This Gives You

1. **A graph in data form** - can be visualized as an actual breadboard diagram
2. **Vertical slicing data** - shows dependencies, where you can cut vs. not
3. **Complete picture** - both UI and code in one view
4. **Implementation roadmap** - follow the wires to build

---

## Key Principles

- **Not a wireframe** - no visual layout, no boxes, no pixel details. For clickable validation, use a clickable-prototype tool (see below).
- **Two separate tables** - UI affordances and Code affordances
- **Numbered IDs** - every affordance gets a unique identifier
- **Explicit wiring** - show every connection between affordances
- **Both ends** - frontend AND backend in the same breadboard
- **Just enough detail** - prove the solution is feasible without over-specifying

---

## Anti-Patterns (Don't Do This)

```
BAD - This is a wireframe, not a breadboard:

┌─────────────────────────────────────────────────┐
│  Login Screen                                   │
├─────────────────────────────────────────────────┤
│  Email: [________________]                      │
│  Password: [________________]                   │
│  [Login Button]                                 │
└─────────────────────────────────────────────────┘
```

The visual boxes add nothing. The affordances and wiring are what matter.

---

## Quick Reference Format

For simpler projects, a compact text format works:

```
[Place Name]
  - affordance → wires to
  - affordance → wires to
```

But for anything non-trivial, use the full tables method - it forces completeness and enables vertical slicing.

---

## State Planning

While creating the wiring table, annotate shared state to prevent mid-implementation refactors.

### Process
1. Identify affordances that read/write the same data
2. Note which component should own that state
3. Mark cross-component dependencies

### Extended Wiring Table Example

| ID | Wires To | Shared State | State Owner |
|----|----------|--------------|-------------|
| U1 | C1 | dimensions[] | App |
| U3 | C1 | dimensions[] | App |
| U8 | C2 | dimensions[] | App |
| U15 | C6 | evaluations{} | App |
| U16 | C6 | evaluations{} | App |

### What This Reveals
- Multiple affordances touching `dimensions[]` → state lives in App, passed as props
- Components become stateless renderers with event callbacks
- Prevents the "lift state mid-implementation" refactor

### Questions to Ask
- Which affordances read/write the same data?
- Does any component need access to state owned by a sibling?
- If yes → lift state to common parent or use a store

---

## Platform Matrix (Required for Platform-Specific Features)

For any feature with platform-specific behavior (native APIs, push notifications, live activities, deep links, offline support), the brief must walk through all platforms explicitly:

| Platform | Behavior | Design Decision |
|----------|----------|-----------------|
| iOS native | [specific behavior] | [decision or "N/A"] |
| Web mobile | [specific behavior] | [decision or "N/A"] |
| Web desktop | [specific behavior] | [decision or "N/A"] |
| Android | [specific behavior] | [decision or "N/A"] |

**Skip for:** Features that behave identically across all platforms (pure server-side, CSS-only, API changes).

**Why:** Every shaping session in the April 2026 window had product-level redirections from missing platform considerations — web modal for iOS-only features, Android handling, desktop fallbacks.

(Evidence: 2026-04-06 delay reporting — missed web-only considerations. 2026-04-07 Live Activities — missed web modal and Android handling. USER consistently catches platform completeness gaps.)

---

## Clickable Prototype Validation (Required)

A breadboard is the spec — it captures places, affordances, and wiring. But affordance tables can't communicate spatial flow, screen transitions, or how a multi-step interaction actually *feels*. For any feature that introduces **new UI or changes an existing UI pattern**, generate a clickable prototype before moving to implementation.

**This is a hard gate for:**
- New features with user-facing UI
- New UI patterns or navigation flows
- Competing UX approaches that need comparison

**Skip for:**
- Pure backend/API changes with no UI
- Bug fixes to existing UI (the flow already exists)
- Config or infrastructure changes

### Process
1. Complete the breadboard (affordance tables + wiring + state)
2. Generate a clickable prototype from the breadboard's UI affordances
3. Click through the flow — does the sequence make sense? Are transitions clear?
4. If comparing approaches, build both as `/v1/` and `/v2/` and pick one
5. Screenshot or screen-record for the shaped brief
6. Reference the prototype decision in the brief: "validated via clickable prototype"

### What the Prototype Is Not
- Not a design tool — monochrome, hand-drawn font, intentionally ugly
- Not production code — throwaway after shaping
- Not a replacement for the breadboard — the breadboard is the contract, the prototype is a validation pass

See `~/Projects/dev-reference/guides/example-d-prototyping.md` for setup and usage.