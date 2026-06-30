---
type: pattern
scope: multi-model code/test/plan review
applies_to: code review, test review, pre-mortem, any multi-agent review where findings must survive scrutiny before reaching a human
source: github.com/liliu-z/magpie (Multi-AI adversarial code review tool, ~149★), scanned 2026-06-03
---

# Adversarial debate + verify-audit review

**TL;DR:** Our existing multi-model review (`run-code-review.sh`, REVIEW_PERSONAS) runs reviewers **independently in parallel** and then **mechanically synthesizes** their outputs — dedup, categorize, flag disagreements. Magpie adds two stages we don't have: (1) a **cross-validation debate round** where each reviewer reads the others' findings and is forced to challenge or validate them, and (2) a tool-equipped **verify+audit pass** that greps each finding against the actual code and filters false positives before anything reaches the human. The verify pass is the cheap, high-leverage steal; the debate round is a heavier escalation tier.

## What the current system does — and the gap

| Stage | Current system | Gap Magpie fills |
|---|---|---|
| Independent review | ✅ Claude + Gemini parallel, split focus; or N isolated personas | — |
| Synthesis | ✅ third call reconciles into `[Both]/[Claude]/[Gemini]/Disagreements` | Synthesis is **mechanical** — it reconciles *text*, it doesn't re-examine *code* |
| Cross-validation | ❌ reviewers never see each other's findings | Round 2+: each reviewer challenges the others' weak claims, validates strong ones |
| Per-finding verification | ❌ findings reach the PR as-asserted | A verifier reads/greps each issue, filters false-positive / by-design / pre-existing, recalibrates severity |
| Convergence | ⚠️ fixed "max 3 iterations" (REVIEW_PERSONAS) | Stop when reviewers *agree*, not after a fixed count |

The cost of the gap: a reviewer's plausible-but-wrong Blocker (a false positive, a by-design pattern, or a pre-existing issue the diff didn't introduce) lands on the PR with full severity and a human has to spend the verification cycle. This is the same failure class as [self-validation-protocol.md](../workflows/self-validation-protocol.md) § "External help-agent claims need cross-check" — a review agent's severity assessment is an external claim, not a fact.

## Steal 1 (cheap, high-leverage): verify + audit pass

After synthesis, run **one tool-equipped pass** over the findings. For each Blocker and Warning:

1. **Read/Grep the actual changed code** to confirm the issue exists as described.
2. Sort into three filter buckets — drop or downgrade only with cited evidence:
   - **False positive** — the code doesn't actually do what the finding claims.
   - **By-design** — the pattern is intentional (matches a documented convention, an existing helper's contract, a deliberate tradeoff noted in the brief).
   - **Pre-existing** — real issue, but the diff didn't introduce it (`git blame`/`git diff` shows it predates this branch). Note it separately; don't block the PR on it.
3. **Recalibrate severity** only when the code you read justifies it.

**Evidence gate (non-negotiable):** a finding may only be filtered or downgraded if the verifier **quotes the file:line it read**. If it can't read the file, the finding stays and is tagged `[unverified]` — never downgrade on inference. This is the [#778 lesson](../workflows/self-validation-protocol.md): a confident-but-wrong severity downgrade is worse than leaving the finding loud, because the human trusts the "verified" label.

This is wired into `run-code-review.sh` as of 2026-06-03 — the synthesis stage is now a synthesis+verify stage. See § Where this is wired.

## Steal 2 (heavier escalation tier): cross-validation debate round

Insert **one round between independent review and synthesis** when the stakes justify it (security-sensitive change, irreversible migration, a finding two reviewers disagree on):

- Show each reviewer the **other reviewers' findings** from round 1.
- Prompt: *"Here are the other reviewers' findings. For each, either defend your own conflicting finding with evidence from the code, or retract it. Validate any of theirs you now agree with."*
- Then synthesize the **post-debate** positions, not the round-1 positions.

Why it works (Magpie's thesis): heterogeneous models (Claude vs Gemini) naturally disagree, and forcing them to defend or retract under each other's scrutiny surfaces which findings are robust. Our `Disagreements` section currently punts these to the human un-adjudicated — the debate round adjudicates first.

**Cost:** one extra round-trip per reviewer (~2× wall-clock, ~2× tokens). Don't pay it by default — it's an opt-in tier for high-stakes diffs, same posture as the depth+breadth split in [cross-model-review-depth-breadth.md](cross-model-review-depth-breadth.md).

## Steal 3 (cheap): convergence-based early stop

For any multi-round review loop (REVIEW_PERSONAS re-review, debate rounds), stop when reviewers **agree**, not after a fixed iteration count. Between rounds, ask: "have the reviewers converged on the open points?" If yes, terminate early and save the remaining rounds' tokens. Replaces "max 3 iterations" with "max 3 iterations *or* convergence, whichever first." Mirrors the loop-until-dry logic in Workflow patterns, inverted: loop-until-agreement.

## When to use which tier

- **Every PR review** → Steal 1 (verify+audit). It's the default now; near-zero marginal cost, strictly reduces false-positive noise.
- **High-stakes diff** (auth, RLS, money, irreversible migration) or a live `Disagreements` conflict → add Steal 2 (debate round) before synthesis.
- **Any iterative re-review loop** → apply Steal 3 (convergence stop) instead of a fixed count.

## When NOT to use

- **Trivial diffs** (single-line fix, typo, dep bump) — skip multi-model review entirely per the pre-pr-checklist Trivial shortcut. Don't verify-audit a one-liner.
- **The verify pass is not a license to over-filter** — its job is to remove *fabricated* findings, not to argue away *inconvenient* real ones. If a finding survives the evidence gate, it stays. Filtering a real Blocker to make a review look clean is the inverse failure and is worse than the noise.

## Where this is wired

- `~/Projects/dev-reference/agents/run-code-review.sh` — synthesis stage upgraded to **synthesis + verify-audit** (Steal 1) on 2026-06-03. Adds a `Filtered (false-positive / by-design / pre-existing)` section to the report.
- `~/Projects/dev-reference/agents/REVIEW_PERSONAS.md` — Consensus Rules reference convergence (Steal 3).
- Debate round (Steal 2) is **not** wired into the script by default — invoke manually for high-stakes diffs.

## Measuring it

The trustworthy signal is **Filtered-section accuracy on real PRs**, not synthetic test cases — synthetic plant generation has a ground-truth ceiling (an LLM can't reliably fabricate "plausible but definitely fake" findings grounded in real code). See [../methodology/blind-eval-of-llm-verifiers.md](../methodology/blind-eval-of-llm-verifiers.md). The live tally is `~/Projects/dev-reference/agents/score-filtered-section.sh` (filter volume, bucket distribution, evidence-gate compliance; flags uncited filters for human review).

## See also

- [cross-model-review-depth-breadth.md](cross-model-review-depth-breadth.md) — the complementary "one call drops a dimension, run two" pattern for Gemini reviews
- [../methodology/blind-eval-of-llm-verifiers.md](../methodology/blind-eval-of-llm-verifiers.md) — how to measure this verify pass without fooling yourself
- [../workflows/self-validation-protocol.md](../workflows/self-validation-protocol.md) § "External help-agent claims need cross-check" — the manual version of the verify gate
- `~/.claude/commands/pre-mortem.md` — independent-persona failure-mode analysis; a debate round is the natural extension when personas conflict
