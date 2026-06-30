# Exploration Output Conventions

How to deliver exploration / mapping / strategy work to USER.

## Rule

For any multi-step exploration, mapping, journey set, option analysis, or strategy artifact: **write the output to a durable `.md` file USER can annotate inline.** Do not dump the mapping as chat prose and ask him to react in the conversation.

## Why

Chat prose is ephemeral and forces reaction in a lossy medium that scrolls away. A file is a durable artifact that:
- accumulates across the exploration instead of being re-derived each turn,
- can be annotated inline with the repo convention `[USER]{...}`,
- keeps the substrate the downstream `/frame` sessions project from (so private assumptions don't diverge).

Stated directly 2026-05-16 during the re-platform user-journeys exploration: *"put the journey in a .md file so i can annotate instead of just dumping it on me. I think generally for this process you should be writing things to files for me to react to — this creates durable documents."*

## How to apply

- Write the artifact to a `.md` file in the relevant context repo (e.g. `example-context/architecture/*.md`).
- Tag unconfirmed claims so annotation targets are obvious: `[H]` = hypothesis (load-bearing, unconfirmed), `[SETTLED]` = confirmed and traceable to an anchor.
- Include a short "How to annotate this doc" note pointing at the `[USER]{...}` inline convention.
- Keep not-yet-approved proposals **inside the exploration doc**, not in the canonical strategy/direction doc — the canonical doc holds settled decisions only; the exploration doc is where reactable proposals live.
- In chat, give only a brief summary + the file path. Let the file carry the substance.
- Crystallize upward (exploration doc → `/frame` brief → canonical anchor) only on explicit instruction. Premature promotion is the failure mode this defends against.

## Related

- `conventions/doc-consolidation-guide.md` — keep these lean; one exploration doc per topic, not fragmented.
- Pairs with USER's hypothesis-first collaboration style: the file is *where* the hypotheses go.
