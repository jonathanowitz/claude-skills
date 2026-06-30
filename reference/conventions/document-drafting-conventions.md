# Document Drafting Conventions

Conventions for documents USER will edit inline — hypothesis-first walk questions in `~/Projects/example-context/design-phase/ledger-*.md`, briefs, shaped-project docs, fill-in-the-blank templates.

## Scope: ANY reaction-worthy artifact goes in a doc, not chat prose

**Rule:** If you're handing USER anything he needs to *react to* — proposals, decision sets, walk questions, ADR drafts, catalog/schema diffs, methodology changes, or a **diagnosis he's expected to weigh in on** — write it to a doc with inline `[USER]{}` slots first, then point him to the doc. Do NOT deliver it as chat prose with a "react to these in your reply" ask. Reserve chat for status, confirmations of *his* instructions, and genuinely one-line yes/no questions.

**Stronger default for multi-step walks: the whole process lives in the doc; chat is pointers.** During an LB-walk / shaping arc, the default working medium for *everything* — my hypotheses and strawmen, not just the formal questions — is the .md doc with inline slots. When I produce a hypothesis (e.g., a Q0 timeline), I write it into the doc with per-section `[USER]{}` slots and the chat message is a thin pointer ("added the Q0 hypothesis at §Q0 — correct it inline"). Do NOT reproduce the hypothesis content in chat: the chat copy goes stale the moment he edits the doc, and duplicating it is double-maintenance.

**Why:** chat prose gives him nowhere to write his answer next to the specific point — he has to re-quote or hold five threads in his head. The trigger is "is this reaction-worthy?", NOT "is this a formal walk-question / ADR?" The narrow read of this file (it only governs walk questions) is the bug.

**How to apply:** before sending a chat response that asks USER to confirm/choose/react to more than a trivial yes/no, stop — put it in a doc with `[USER]{}` slots first.

**Evidence:** 2026-05-28 a design walk Reflection 2 — drafted ADRs as finished prose ("where am I supposed to react to this?"). Same session, immediately repeated it: delivered a multi-part cascade *diagnosis* + 5 decisions as chat prose. USER: "please. always write to a doc so i can react for the love of everything." The diagnosis wasn't a "walk question," so the narrow scope didn't trip — proving the rule has to be artifact-purpose ("reaction-worthy"), not artifact-type. **2026-05-29 a design walk** — presented a Q0 producer-rhythm hypothesis in chat; USER: "can you add that to the doc so I can write against it inline please; **in general this process should almost entirely be done in the md docs**." Generalizes the rule from discrete reaction-worthy artifacts to the entire walk's working medium.

## Answer slots: empty braces, not `...`

**Rule:** End each hypothesis-first walk question with an EMPTY `[USER]{}` marker on its own line. NEVER put `...` (or `<your answer>`, `TBD`, any other placeholder text) inside the braces. **Always write the marker backtick-wrapped as inline code** (`` `[USER]{}` ``) — bare/unwrapped, Obsidian garbles the brackets and braces, so the slot renders broken. (Evidence: 2026-06-26 — wrote bare `[USER]{}` slots across the WitzCraft copy doc; "it needs to have the fucking backticks too or it shows up weird in the markdown on obsidian.")

```
Right framing — X or Y?
`[USER]{}`
```

NOT:
```
Right framing — X or Y?
`[USER]{...}`
```

**Why:** The empty `[USER]{}` marker IS useful — it's the signal of where his answer goes, and his typing flow is "click between the braces and type." Adding `...` inside means he has to delete the `...` first before typing — pure friction. Empty braces = zero-friction insertion point; filled-with-placeholder braces = deletion tax.

**How to apply:** Default to empty `[USER]{}` on every walk question. Same applies to any structured doc where the pattern is "I draft the question/section; USER writes the answer inline" — the marker is fine, the placeholder text is not.

**Evidence:** 2026-05-26 a design walk draft — first iteration had `[USER]{...}`; USER flagged it ("just something I have to delete"). Second iteration removed the brackets entirely; USER flagged THAT too ("I still want `[USER]{}` I just don't want you throwing `...` in between the braces"). The empty-braces form is what he wants. **Recurred 2026-05-29 a design walk framing draft** — reverted to `[USER]{...}` across all 18 slots from pattern-matching to a generic "fill-here" placeholder; USER: "why did you start putting `[USER]{...}` again instead of just `[USER]{}`". This is a documented convention being re-violated, not a missing rule — the failure mode is generic-placeholder muscle memory overriding the established empty-slot convention at draft time.

## AskUserQuestion framing: open-ended, not bounded

**Rule:** When offering N options on a design decision (AskUserQuestion, ledger walk question, or any "pick one" prompt), frame the option set as open-ended — invite the user to push back with a better cut. NEVER present N options as exhaustive when the framing itself might be wrong.

Default phrasing:

> "Here are the paths I see — push back if there's a better framing I'm missing."

NOT:

> "Pick one: α, β, γ, δ."

**Why:** Even when N options look exhaustive to me, USER often has a domain-cut I haven't considered. The exhaustive framing implicitly says "these are the choices" when the actual right answer is sometimes "none of these — here's the better axis." If I bound the option space too narrowly, the user has to fight my framing before answering the question — pure friction.

**How to apply:**
- Default to open-ended framing in every AskUserQuestion and ledger walk-question.
- Even in cases that look exhaustive (yes/no, A/B), add a "push back if there's a better framing" beat — it costs nothing and unlocks user-side reframing.
- When USER picks "none + better framing," treat that as the option set being wrong, not the user being difficult. Update the framing, re-pose.

**Evidence:**
- 2026-05-19 LB1-ADR — bounded option space α/β/γ/δ for filter algebra; USER proposed ε (structural-impossibility via constrained dropdowns). The right axis wasn't on my list.
- 2026-05-20 LB1-foldback — framed Gemini-4 clean PASS as "diminishing returns, cap iterations at 3"; USER: iterate until PASS, no cap. The cap itself was wrong framing.
- 2026-05-22 pass2-audits-producer — 5-scenarios menu for mitigation directions; USER: "what 5?" — the structure was buried in prose, the right cut was a roadmap-grounded subset.

## Hedged confirmations are conditional locks

**Rule:** When USER's confirmation hedges — "I think," "can revisit," "maybe," "for now," "good enough for v1" — record it as `{Confirmed-pending-revisit}` not `{Confirmed}`. Reflect the hedge back before treating as firm. Prevents over-locking in iterative design walks.

**Why:** In long design arcs (R3, R4, R8 walks), each lock becomes substrate for the next region. Treating a hedged confirmation as a firm lock means downstream regions inherit a load-bearing assumption that wasn't actually load-bearing — and re-locking later costs more than recording the hedge in the first place.

**How to apply:**
- Watch for hedging language in confirmations: "I think," "can revisit," "maybe," "for now," "let's go with X for v1."
- Record as `{Confirmed-pending-revisit}` or `{Confirmed-with-caveat: <caveat>}` — not bare `{Confirmed}`.
- Reflect the hedge back in the next message: "Recording as conditional — flag if you want it firmed up before [downstream region]." Surfaces the hedge so USER can either firm it or let the conditional stand.
- When a downstream region cites a conditional-lock as substrate, surface that explicitly: "This depends on [conditional X]; if X changes, this region needs to revisit."

**Evidence:**
- 2026-05-25 a design-walk review — treated hedged confirmation ("I think — can revisit") on an enum as firm `{Confirmed}` lock. Later required re-locking when downstream LB3 surfaced the inherited-vocabulary assumption.
