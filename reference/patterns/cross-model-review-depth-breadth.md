---
type: pattern
scope: cross-model review (Gemini)
applies_to: test review, code review with multiple review dimensions
---

# Cross-model review: depth + breadth pattern

**TL;DR:** When running a Gemini review that has to cover more than ~3 dimensions, a single call quietly drops one. Run two parallel calls instead — one focused on the single hardest question, one deliberately unstructured "what else catches your eye?" breadth sweep.

## The failure mode

A broad review prompt with 6 numbered dimensions ("check arithmetic, check coverage gaps, check vacuous passes, check mock fidelity, check isolation, check naming") looks like it covers everything. What happens in practice: the model gives solid treatment to 3-4 dimensions and thin-to-absent treatment to the rest. Which dimensions get dropped varies by run and isn't predictable. The prompt *looks* thorough; the output *is* thorough on most things; the one dropped dimension is exactly where a BLOCKER might hide.

## Evidence (2026-04-11, Slice 1 of example-app #579)

A/B test: same 31-test spec, same files, same model (`gemini-2.5-pro`), two review strategies.

**Strategy A — super prompt (1 call, 6 numbered dimensions):**
- Caught: `onConflict` BLOCKER, payload-completeness WARNING, DST edge-case suggestion, test-name mismatch, `vi.useRealTimers` duplication
- **Missed:** month boundary rollover gap (BLOCKER), notifications-test vacuous pass (BLOCKER), mock fidelity (skipped the dimension entirely)

**Strategy B — 4 parallel focused prompts:**
- Caught: `onConflict` BLOCKER, payload-completeness WARNING, month boundary BLOCKER, notifications vacuous pass BLOCKER, mock fidelity (CLEAN)
- **Missed:** test-name mismatch, `vi.useRealTimers` duplication, DST edge-case suggestion

**Score:** Strategy A missed 2 BLOCKERs and dropped 1 dimension entirely. Strategy B missed 3 SUGGESTION-level items. Neither dominated — and the items each missed were things the *other* was structurally likely to catch.

**Cost:** A was 1 call. B was 4 calls (~3x prompt authoring, same wall-clock when parallel).

## The pattern

Run **exactly two parallel calls**:

### Call A — Depth (one question, sharp)
Pick the single hardest question — usually one the human reviewer can't easily self-check. Cross-file comparisons and hand-computed fixtures are good candidates. Use the strongest reasoning model (`Gemini 3.1 Pro (High)`, fallback `Gemini 3.1 Pro (Low)`).

Examples by feature type:
- **API + DB mock code** → "Does the hand-rolled mock faithfully emulate every chain pattern the real source uses?"
- **Time/date fixtures** → "Independently compute every expected value and flag mismatches."
- **E2E selectors** → "Grep the HTML and flag any selector that doesn't exist."

### Call B — Breadth (unstructured)
No numbered checklist. No "do NOT flag" list. Those constraints are specifically what causes dimension-dropping in the super-prompt failure mode. Explicitly acknowledge that obvious things have been checked upstream so the model is primed to hunt for the non-obvious.

Template:
```
Act as a senior QA engineer reviewing a test file written before
implementation. Three other reviewers have already flagged the obvious
issues: vacuous passes, selector verification, behavior map coverage,
basic mock correctness. Your job is to find what they missed.

Look for things like:
- Test names that don't match what the assertions actually check
- Repetitive hygiene issues (cleanup duplication, fragile fixtures)
- Cases where the test would pass for the wrong reason
- Edge cases in the feature's domain that nobody wrote a test for
- Anything that makes you say "huh, that's suspicious"
```

Use `Gemini 3.1 Pro (Low)` — breadth sweeps don't need the strongest model, they need a fresh perspective.

### Synthesizing

- **Consensus** (both flagged) → highest confidence
- **Depth-only** → medium confidence on that specific dimension
- **Breadth-only** → evaluate carefully — often the highest-leverage catches because they're things you didn't know to look for
- **Conflict** → investigate
- **Hazard ≠ remedy** → every finding is two claims, verify each

### Hazard and remedy are separately checkable

A finding bundles "here is a failure" with "here is the fix." Those have independent truth values, and a *correct hazard lends unearned credibility to whatever remedy rides along with it* — you verify the failure, feel the finding check out, and adopt the fix untested.

Trace the proposed remedy through the same concrete fixture that demonstrates the hazard. If it does not prevent that exact case, say so and solve it yourself. **Confirming the hazard is not confirming the finding.**

Evidence: 2026-07-27, example-app #1224. Gemini correctly identified that the `/operator` index route (guarded by persona only, no scope check) could eject an operator holding three gyms out to fan home when a stale bookmark named a scope they no longer held. Its prescribed fix was to restore a deleted carve-out — but that carve-out's condition was `if (sameType.length > 0) return null`, which fires precisely when the operator holds other programs. It did not cover the case it was prescribed for. Adopting it would have re-added dead complexity and left the hazard unfixed; the real fix belonged to a different module entirely.

Generalizes past cross-model review to any external claim pairing a diagnosis with a prescription — subagent reports, code-review comments, a library error suggesting a flag.

## When NOT to use this pattern

- **Single-dimension reviews** — "Is this SQL migration safe?" is already one question. Don't fragment.
- **Generic `/second-opinion` calls** — for architecture review, debugging, a one-shot second opinion from a human colleague is the mental model, not a multi-perspective audit.
- **Quick sanity checks** — this pattern adds minutes. If the question is "does this look right at a glance?", one call is fine.

## Gemini CLI workspace scope with worktrees

Gemini CLI scopes its file access to the directory it's launched from. When implementation work lives in a git worktree (sibling directory), Gemini can't read the worktree files by default — it gets "Path not in workspace" errors and spins trying to locate them.

**Fix (preferred when you need Gemini's tools to read files):** Use `--add-dir` to add the worktree to Gemini's workspace:

```bash
agy --model "Gemini 3.1 Pro (Low)" --add-dir /path/to/worktree -p "Review the test files at tests/api/foo.test.js ..."
```

This works even when the main cwd is the original repo checkout. Gemini can then read files from both directories.

**Fix (preferred when the files are smallish — under ~3000 lines combined):** Inline the file contents into the prompt itself. Workspace scope becomes irrelevant because Gemini just reads the prompt. But **use temp-file composition** (see [shell-llm-prompt-composition](shell-llm-prompt-composition.md)) — `$(cat /path)` inside a single-quoted heredoc `<<'PROMPT'` does NOT expand, and Gemini receives literal `$(cat /path)` text. See "How to detect silent failures" below.

**(Evidence: 2026-04-16 — #621 payments tests lived in `example-app-payments-stripe` worktree. Two Gemini calls failed with "Path not in workspace" errors before adding `--include-directories`.)**

## How to detect silent failures

Gemini will produce plausible-looking output even when its tool reads fail or when file contents weren't inlined as you intended. Three concrete tells:

1. **The response cites test names / function names / class names that don't exist in your file.** When Gemini can't read the file, it falls back to context clues in the prompt + training-data priors, producing realistic-sounding but fabricated artifacts. Always cross-check at least one quoted identifier against the actual file before trusting the review.
2. **The response is suspiciously generic** — applies to "any test of this kind" without citing specific line numbers or quoting actual code. Genuine reviews quote.
3. **The CLI emits `Path not in workspace` or `read_file` errors before the final response.** These are visible in stderr; check them if you ran with `2>&1`. They mean Gemini tried to fetch a file path you passed and couldn't.

**Validation guardrail in your prompt:** include "If you flag a finding, you MUST quote a snippet from the actual code to prove you read it." The breadth template above doesn't enforce this; add it when high confidence matters.

**(Evidence: 2026-05-19 — #795 Slice 2 review. Single-quoted heredoc blocked `$(cat ...)` expansion. Gemini breadth call fabricated test names like `"should handle Mercury API failure gracefully"` that did not exist. Caught only because USER said "if your gemini calls are failing, you need to figure out how to make the docs readable to them — don't just gloss over it." Without the prompt-quote validation rule, a less attentive reviewer could have acted on the fabricated findings.)**

## Gemini auto-router failure mode

When invoked without `-m`, Gemini routes through an internal model classifier (`NumericalClassifierStrategy`). This router can fail on large prompts with:

```
API returned invalid content after all retries.
[Routing] NumericalClassifierStrategy failed: Error: Failed to generate content: Retry attempts exhausted
```

**Fix:** Always pass `--model "<display string>"` explicitly when scripting with `agy`. This bypasses the router entirely. Recommended defaults:
- Depth (focused reasoning) → `--model "Gemini 3.1 Pro (High)"` (or `--model "Gemini 3.1 Pro (Low)"` as fallback)
- Breadth (fresh perspective) → `--model "Gemini 3.1 Pro (Low)"`

**(Evidence: 2026-05-19 — depth call without `-m` failed with router-exhausted error. Retry with `-m gemini-2.5-pro` succeeded immediately on the same prompt.)**

## Where this is wired in

- `~/.claude/commands/review-tests.md` — Stage 3 uses this pattern by default for test review (Stage 4 gate).
- Generic `/second-opinion` does NOT use this pattern — it's opt-in via `/review-tests` specifically.

## See also

- `~/.claude/commands/review-tests.md` — the skill that operationalizes this
- `~/.claude/commands/second-opinion.md` — the generic single-call pattern
- `~/Projects/dev-reference/workflows/development-process.md` — Stage 4 test-review gate
- [adversarial-debate-verify-review.md](adversarial-debate-verify-review.md) — the complementary axis: after multi-perspective review, debate conflicts and verify each finding against code before it reaches a human
