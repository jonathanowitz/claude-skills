# Ambiguous Instruction Protocol

When a user instruction has two plausible referents — a pronoun with two antecedents, a trailing clause that could modify two different nouns, an ambiguous verb ("remove X" when X could mean the rule set or the variables) — ask one clarifying question before acting.

**The math:** Cost of asking = ~30 seconds. Cost of picking the wrong horn = 5–15 minutes of rework plus losing the user's trust that you're reading carefully.

## Ambiguity signals

- **Pronouns with multiple antecedents.** "Make sure it uses the right value" — which "it"?
- **Trailing clauses.** "This template is not mobile-adaptive, and you can also remove X" — is "remove" a second instruction, or a continuation of the first?
- **Instructions that apply to multiple existing instances.** "Update the pricing text" — every copy, or the one we're currently editing?
- **"The" referring to something not yet specified.** "Use the format from the other one" — which other one?
- **Mixed 50/50 plausibility.** If the two interpretations have roughly equal product logic, assume you cannot guess correctly; ask.

## What to ask

One focused question that surfaces the two interpretations and lets the user point at the right one:

> "I want to make sure I read that right — 'remove' refers to the @media rules, or to the liquid variables listed above? Happy to do either, just want to pick the right one."

Not two questions. Not a long preamble. Offer the two horns, ask the user to point.

## When to skip the ask

- **Clear referent with only one plausible antecedent.** Don't manufacture ambiguity for the sake of asking.
- **Tiny reversible change.** If the wrong guess costs 2 seconds of `git checkout`, just pick one and show the user what happened.
- **User has already answered this class of question once in the session.** Cache their preference; don't re-ask on every occurrence.

## Evidence

- **2026-04-23 email template** — "This template is not mobile-adaptive, and you can also remove [liquid variables]" read as "remove @media rules." Built v1 in the wrong direction; had to throw away.
- **2026-04-23 youth summit parser** — "D1 and D2 are separate divisions" read as "merge them into the same pool." Actual intent was to preserve the separation and fix a different bug (bid-label contamination). One clarifying question would have named the right bug.
