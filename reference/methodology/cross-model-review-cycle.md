# Cross-Model Review Cycle

**Rule:** For high-stakes design decisions (ADRs, breadboards, architectural amendments), iterate Gemini cross-model review **until clean PASS**. No iteration cap. No diminishing-returns judgment. The clean PASS is the convergence signal — it's how you *know* the previous pass's fixes didn't introduce new issues.

## Invocation pattern

```bash
agy --model "Gemini 3.1 Pro (Low)" -p "$(cat /tmp/review-prompt.md)"
```

The `-p` argument (not piped stdin) is the reliable invocation. (See also: `feedback_gemini_cli_invocation` memory — the described rule now uses `agy` with `--model`.)

## The loop

1. Compose a review prompt that includes the artifact under review + relevant upstream/downstream context docs + an explicit review structure (verdict, blockers, warnings, coverage check, constraint check, delta-preview check, cross-link completeness, novelty/re-litigation risk).
2. Run Gemini. Capture the output verbatim.
3. **Apply all blockers + meaningful warnings.** Don't cherry-pick.
4. **Re-run.** Reframe the prompt to call out which findings were closed by the new revision; ask Gemini to verify they're cleanly closed AND surface any NEW issues introduced by the fixes.
5. Continue until a pass returns PASS with no blockers and no new findings. **That clean PASS is the exit condition.**

## Why iterate until PASS (not until "diminishing returns")

The clean PASS is **not** redundant verification. It is the only signal that the previous pass's fixes were complete and didn't introduce new issues. Stopping at "REVISE with fixes applied" is shipping on the assumption that the fixes landed cleanly — that assumption is exactly what the next pass tests.

The cost argument collapses on inspection. Each Gemini call is cheap (minutes of run time + small token spend) relative to:
- Implementation rework if a structural issue surfaces during a slice
- Shipping a wrong model and finding out post-launch

Token-per-call optimization is the wrong variable. Optimize for **correctness of the artifact**, not for fewer Gemini calls.

## Process tweaks that compound

These don't replace the iterate-until-PASS rule; they reduce the iteration count without bounding it artificially.

- **Pre-Gemini consistency sweep.** Before the first Gemini call, re-read each section of the artifact against the others — does this still hold given the other sections' refinements? Cross-section consistency lapses are the dominant failure mode in multi-section artifacts.
- **Open-ended option framing.** When offering choices: "here are N paths I see — push back if there's one I'm not surfacing." Don't bound the option space to known options. The user often sees an option you didn't.
- **Re-prompt Gemini explicitly on the previous round's findings.** Tell Gemini what was just fixed. It targets verification at the right places instead of re-reviewing the whole artifact every time.

## When to use this cycle

- ADRs (architecture decision records)
- Breadboards (flow/state design artifacts)
- Architectural amendments that override prior do-not-reopen entries
- Any artifact where "I'm too close to see the structural issues" is plausibly true

## When NOT to use

- Code reviews (use the existing PR-review pattern instead)
- Implementation work (Gemini is a fresh-eyes design verifier, not an implementation reviewer)
- Day-to-day decisions that don't have multi-section composition risk

## Evidence

LB-1 ADR for Artifact A — Filter Algebra & Identity (2026-05-19/20). 4 Gemini passes:
- Gemini-2: REVISE (3 findings — D3/D4 ambiguity, D6 algebra contradiction, D5 conflation)
- Gemini-3: REVISE (2 blockers + 1 warning — ε source basis, default vs Deselect-All conflict, empty-pill clarification)
- Gemini-4: **PASS** clean (zero findings — convergence)

I originally framed Gemini-4 as "diminishing returns" and recommended skipping it. USER corrected: run until no more blockers. He was right — without Gemini-4 we'd have shipped on the assumption that Gemini-3's fixes were complete. The PASS was the only signal that closed the loop.

## Related

- `~/Projects/dev-reference/patterns/cross-model-review-depth-breadth.md` — **complementary pattern, not a duplicate.** Depth+breadth is *how to structure one review pass* (parallel focused + unstructured calls to catch what a super-prompt would drop). This methodology is *when to stop the multi-pass cycle* (iterate until clean PASS). They compose: for high-stakes artifacts with many dimensions, each iteration of this cycle can run depth+breadth in parallel, then converge across iterations. For ADR-style artifacts with fewer independent dimensions (e.g., LB-1), single-call-per-iteration is usually sufficient because the iteration loop itself catches dropped findings across passes.
- `~/Projects/dev-reference/patterns/shell-llm-prompt-composition.md` — temp-file prompt composition (avoids the `$(cat file)`-inside-single-quoted-heredoc silent-failure mode).
- `~/Projects/dev-reference/methodology/breadboard.md` — for the breadboard artifact form this cycle reviews.
- `~/Projects/dev-reference/methodology/decision-gate-protocol.md` — for upstream "should we be making this decision now?" framing.
- Project memory `feedback_gemini_cli_invocation` — the invocation rule (now `agy --model "<display string>" -p "$(cat file)"`; memory name preserved as-is).
