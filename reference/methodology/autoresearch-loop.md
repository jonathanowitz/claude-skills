# AutoResearch Loop

**When to use:** Any codebase optimization where USER has a robust test suite and a single measurable metric to improve.

## The Pattern

An autonomous, metric-driven optimization loop: an AI agent iteratively modifies code, runs tests + benchmarks, and keeps or discards each change based on a measurable outcome.

```
1. Agent reads program.md (goal, metric, constraints, file scope)
2. Agent brainstorms an optimization idea
3. Agent edits source code
4. Run validation script:
   a. Unit tests (fast gate — fail = abort)
   b. Correctness tests (conformance gate)
   c. Benchmark (measure primary metric)
5. Compare metric to previous best:
   • Better → git commit, log to .jsonl, KEEP
   • Worse  → git revert, log to .jsonl, DISCARD
6. Repeat from step 2
```

Each cycle should complete in 1-5 minutes, yielding 12-60 experiments per hour.

## Required Infrastructure

| Component | Purpose | Who Maintains |
|-----------|---------|---------------|
| `program.md` | Goal, metric definition, file scope, off-limits areas, constraints, baseline, progress log | USER (refine over time) |
| `autoresearch.sh` | Runner script: tests → benchmark → outputs `METRIC key=value` lines | USER (set up once) |
| `autoresearch.jsonl` | Experiment log: run #, commit, metrics, keep/discard, description | Agent (appends each run) |
| Test suite | Correctness gate — must be comprehensive enough that passing tests = correct behavior | USER (pre-existing) |
| Test corpus | For correctness domains: known inputs with known-correct expected outputs | USER (curated) |

## Critical Success Factors

1. **Robust test suite** — Without this, the agent can't safely experiment. The test suite IS the safety net.
2. **Single measurable metric** — One number to optimize. The agent needs a clear keep/discard signal.
3. **Fast feedback loop** — Tests + benchmark must run in <5 minutes per cycle.
4. **Scoped file boundaries** — Explicitly tell the agent what it can and cannot touch.
5. **Progress log** — Prevents repeated dead ends across context resets.

## Two Modes

### Performance optimization (same output, faster)
- Metric: latency, throughput, memory, allocations
- Validation: output must be identical to baseline
- Risk profile: low — wrong output is caught by diff
- Example: Shopify Liquid (53% faster parse, 61% fewer allocations from ~120 experiments)

### Correctness optimization (better output)
- Metric: error rate, accuracy, format compliance
- Validation: output compared against expected corpus
- Risk profile: medium — need comprehensive corpus to catch regressions
- Example: PDF parser error elimination
- **Also applicable for format expansion** — add new PDF formats to the test corpus with expected outputs, then let the agent iterate until error rate drops to zero for the new format while maintaining existing format accuracy

## When NOT to Use

- No test suite or metric exists (build those first)
- The optimization requires architectural changes (agent works best within existing structure)
- Feedback loop is slow (>10 min per cycle kills the experiment volume)
- The domain requires human judgment to evaluate output quality (agent needs binary keep/discard)

## Reference Implementation

See `example-app/docs/autoresearch-methodology-summary.md` for the full write-up with Karpathy and Shopify source links.

## Related

- `autonomous-agents.md` — Agent workflow patterns (autoresearch is a specialized agent loop)
- `vertical-slice-pattern.md` — For multi-session work, each autoresearch domain could be a slice
