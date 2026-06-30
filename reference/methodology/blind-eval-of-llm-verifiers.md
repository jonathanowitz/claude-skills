# Blind evaluation of LLM verifiers

How to measure an LLM that judges other LLMs' output (a review verify-pass, a finding-filter, a claim-checker) — and the two traps that produce a falsely clean score.

## When to Use
- You built an LLM stage whose job is to *filter* or *adjudicate* other findings (e.g. the cross-model review verify-pass in [../patterns/adversarial-debate-verify-review.md](../patterns/adversarial-debate-verify-review.md)) and want to know if it's safe.
- You're tempted to write synthetic test cases for it yourself and grade the results.

## The Pattern

**1. Never grade your own oracle.** Use three isolated roles, and let a deterministic script — not an LLM — do the final compare:
- **Designer/oracle** — fabricates findings + a sealed ground-truth key. Sees only the input artifact.
- **System under test** — the verifier, run as it ships.
- **Blind grader** — independently re-derives each finding's correct disposition from the code. **Never sees the key or the SUT's decisions.**
- **Mechanical compare** — joins key vs SUT vs grader. No LLM holds the key and the output together.

Accept a finding's ground truth **only when designer-key and blind-grader agree.** Exclude the rest — disagreement means the test case itself is ambiguous, not that the SUT failed.

**2. Distrust synthetic plants — they have a ground-truth ceiling.** An LLM asked to fabricate "adversarially plausible but definitely fake" findings *grounded in real code* cannot reliably do it: plausible + real-line-grounded ≈ real. In practice the designer **retracts its own plants mid-generation** ("Wait, the code correctly guards both — retract") and **mislabels its key** (tags a finding `false-positive` while its own rationale concedes it's "real in principle"). The harder you push for plausibility, the more your "fakes" become real findings.

**3. If you do build a synthetic harness, enforce referential integrity before scoring.** Require **unique, stable finding IDs** and validate that every ID appears exactly once across designer-findings, key, SUT-decisions, and grader-verdicts. A schema that doesn't constrain ID uniqueness lets the oracle emit duplicate/scrambled IDs (it will, especially when it retracts and reuses), which silently corrupts the mechanical join and makes the score meaningless.

**4. The durable signal is real artifacts, not synthetic.** Measure the verifier's Filtered-section accuracy on actual PRs over time (ground truth = merge/review outcome), not on manufactured cases.

## Why This Matters
A self-graded run *looks* authoritative — and is the most dangerous output, because you act on it. The blind grader is precisely what catches the oracle being wrong; without it you trust a contaminated key and ship a false "0 false-suppressions." The cost of the blind harness (a few extra agents) buys the one thing the cheap version can't: independence between the party that knows the answer and the party that grades.

## Evidence
- 2026-06-03 — Evaluating the `run-code-review.sh` verify-pass (just added). A self-designed + self-graded run returned a clean "4/4." Rebuilt as a 3-role blind Workflow harness: the SUT and the blind grader independently agreed on **7/7** dispositions (both filtered exactly one fabrication, with evidence) — the **only** disagreement was the synthetic oracle's key, which an independent reader rejected on 4 of 7. The designer had retracted its own plants inline and self-contradicted its key; missing ID-uniqueness enforcement scrambled the join. Conclusion: the verifier was fine; the *synthetic oracle* was the unreliable component, and only blind separation exposed it.

## See Also
- [../patterns/adversarial-debate-verify-review.md](../patterns/adversarial-debate-verify-review.md) — the verify-pass being evaluated
- [cross-model-review-cycle.md](cross-model-review-cycle.md) — the broader multi-model review methodology
- `~/Projects/dev-reference/agents/score-filtered-section.sh` — the live-PR tally this lesson points to
