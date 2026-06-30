# Model Selection Guide
**Created:** 2026-03-15
**Last updated:** 2026-03-15

Reference for selecting the right model for the right task across Claude and Gemini families. Updated as we gather empirical data from real workflows.

---

## Available Models

### Claude (Anthropic)

| Model | ID | Strengths | Best For |
|-------|-----|-----------|----------|
| **Opus 4.6** | `claude-opus-4-6` | Deep reasoning, detailed attack scenarios, cross-file analysis, high finding volume | Complex security reviews, exploit hunting, architecture decisions, multi-file analysis |
| **Sonnet 4.6** | `claude-sonnet-4-6` | Balance of speed and quality | Most coding tasks, standard code review, implementation work |
| **Haiku 4.5** | `claude-haiku-4-5-20251001` | Fast, cheap | Quick tasks, simple lookups, formatting, summarization |

### Gemini (Google — via `agy`)

| Model | Display String | Strengths | Best For |
|-------|---------------|-----------|----------|
| **3.1 Pro (High)** | `Gemini 3.1 Pro (High)` | Deepest reasoning (2.2x thought tokens vs 2.5), catches subtle cross-file patterns | Second-pass deep review, design-level vulnerabilities, auth logic flaws |
| **3.1 Pro (Low)** | `Gemini 3.1 Pro (Low)` | Reliable, fast, good finding volume, operational issues | Standard code review, security audit, breadth-first analysis |
| **3.5 Flash (High)** | `Gemini 3.5 Flash (High)` | Fastest | Fallback when Pro is unavailable, simple tasks |

---

## Empirical Benchmarks

### Security Audit: Auth & Access Control (2026-03-15)

7 files (~1,564 lines), auth/CORS/rate-limiting review.

#### Claude Opus vs Gemini 2.5 Pro (parallel, same files)

| Dimension | Claude Opus | Gemini 2.5 Pro |
|-----------|------------|----------------|
| Findings per run | 7-11 | 4-8 |
| Duration | 50-70s | 38-76s |
| Attack scenario detail | Excellent | Good |
| Cross-file analysis | Strong | Good |
| Unique catches | WRITE_ROUTES gap, referral IDOR, route enumeration, innerHTML XSS | PKCE/native OAuth (2 of 3 runs) |

#### Gemini 2.5 Pro vs 3.1 Pro Preview (same prompt)

| Metric | 2.5 Pro | 3.1 Pro Preview |
|--------|---------|-----------------|
| Duration | **75.9s** | 155.9s (3x 429 retries) |
| Output tokens | **3,557** | 2,137 |
| Thought tokens | 4,488 | **9,978** |
| Findings | **8** | 6 + 2 info |
| API errors | **0** | 3 (capacity) |
| Availability | Reliable | Capacity-limited |

**Key insight:** 3.1 thinks 2.2x harder but produces fewer findings. Its unique catches (email-based admin auth, innerHTML XSS) independently converged with Claude's — suggesting genuine deeper analysis, not just more output.

---

## Task-to-Model Mapping

| Task | Recommended Model | Why |
|------|-------------------|-----|
| **Security audit (primary)** | Claude Opus + Gemini `3.1 Pro (Low)` in parallel | Best combined coverage; convergent findings = highest confidence |
| **Security audit (deep pass)** | Gemini `3.1 Pro (High)` | Catches subtle design-level issues; use as optional second pass |
| **Code review (PR)** | Claude Sonnet + Gemini `3.1 Pro (Low)` in parallel | Good balance of speed and quality for diff-based review |
| **Implementation** | Claude Sonnet | Best coding model for day-to-day work |
| **Complex architecture** | Claude Opus | Deep reasoning for design decisions |
| **Quick tasks** | Claude Haiku or Gemini `3.5 Flash (High)` | Speed over depth |
| **Summarization** | Claude Haiku | Fast, cheap, reliable |

---

## Prompt Sensitivity

Both Claude and Gemini respond strongly to prompt structure. Empirical findings:

### What works for Claude
- **Exploit-focused pentest role** — produces high-signal findings, good attack scenarios
- **"Part 2: cross-file systemic patterns"** — catches coverage gaps, consistency issues
- **Pre-read files inline** — eliminates tool use overhead (21 tool calls → 0, 49% faster, 48% cheaper)

### What works for Gemini
- **Per-file section headers required** — forces thoroughness; without this, Gemini skims and produces 2-4 terse findings
- **Cross-file analysis section** — catches systemic patterns that per-file misses
- **"Be verbose"** — Gemini defaults to terse output; explicit verbosity instruction increases output tokens 2-4x
- **Plain text output (the default)** — `agy` does not have a reliable `--output-format json` flag; use plain text output (the default) for all scripting. Structured telemetry is not available via `agy`.

### What doesn't work
- **Role-specific prompts for Gemini** (e.g., "you are a security architect") — narrows scope too much, loses findings
- **Generic "review for security" without structure** — both models produce shallow results

---

## Reliability & Availability

| Model | Availability | Fallback |
|-------|-------------|----------|
| Claude Opus | Reliable | — |
| Claude Sonnet | Reliable | — |
| Claude Haiku | Reliable | — |
| Gemini 3.1 Pro (Low) | Reliable | — |
| Gemini 3.1 Pro (High) | **Capacity-limited** (MODEL_CAPACITY_EXHAUSTED) | Gemini 3.1 Pro (Low) |
| Gemini 3.5 Flash (High) | Reliable | — |

For scripts, always include a fallback chain:
```bash
agy --model "Gemini 3.1 Pro (High)" -p "..." 2>&1 || agy --model "Gemini 3.1 Pro (Low)" -p "..." 2>&1
```

---

## Telemetry

### Claude
- Subagent usage returned in task notification: `total_tokens`, `tool_uses`, `duration_ms`
- CLI: `claude -p "..." --output-format json` for structured output

### Gemini (via `agy`)
- Plain text output is the default. `agy` does not have a reliable `--output-format json`; structured telemetry is not available.
- Token/latency stats are not returned by `agy` in a parseable form — measure wall-clock externally if needed.

---

## Dual-Model Review Pipeline (Validated)

Refined across 4 runs on auth & access control audit (2026-03-15). This is the recommended pattern for security audits and deep code reviews.

### Step 1: Pre-read files
Read all target files once. Feed identical content to both models inline — eliminates tool use overhead.

### Step 2: Parallel initial review
Run both models simultaneously with differentiated prompts:

**Claude prompt structure:**
```
You are a penetration tester. Find exploitable vulnerabilities with attack scenarios.
Part 2: Cross-file systemic patterns — coverage gaps, consistency issues,
missing protections across files that interact.
```

**Gemini prompt structure:**
```
For EACH file, write a section header and list all findings.
If clean, explain why. After per-file analysis, add a CROSS-FILE ANALYSIS section.
Be verbose in descriptions.
```

### Step 3: Cross-validation (highest-value step)
Feed each model's findings to the other and ask:

```
For EACH finding: Confirm, Dispute (with reasoning), or Adjust Severity.
After evaluating all findings: WHAT DID THIS REVIEWER MISS?
```

Append the **known patterns library** (`audit-known-patterns.md`) as a checklist:
```
APPENDIX: KNOWN PATTERNS FROM PRIOR AUDIT DOMAINS
[patterns here]
Check whether any apply to the findings above or to the files under review.
Do NOT let these patterns bias you — only flag if you see concrete evidence.
```

**Why patterns go in Step 3, not Step 2:** The initial review should be unbiased — models find what's actually there. Patterns in cross-validation act as a "did you check for these known risks?" checklist without anchoring the discovery pass.

**Why this matters:**
- Calibrates severity (Gemini tends to over-rate CORS/rate-limit findings)
- Catches false positives (2 found in our test)
- Produces genuinely new findings that independent review missed (5 found in our test)
- The "what did they miss" prompt triggers findings that neither model caught independently
- Pattern library catches recurring codebase-specific risks across domains

### Step 4: Synthesize
Merge with calibrated severities:
- **Convergent findings** (both independently flag) = highest confidence
- **Cross-validated confirmations** = high confidence
- **Single-model findings confirmed in cross-validation** = medium confidence
- **Disputed findings** = needs human judgment

### Empirical results

| Pipeline step | Findings produced | False positives caught | Time |
|--------------|-------------------|----------------------|------|
| Parallel review (Step 2) | ~15-17 combined | 0 | ~70s |
| Cross-validation (Step 3) | +5 new findings | 2 removed | ~90s |
| **Total** | **~20 calibrated** | **2** | **~160s** |

---

## Anti-Patterns (Learned the Hard Way)

| Don't | Why | Do Instead |
|-------|-----|------------|
| Give Gemini a role-specific prompt ("you are a security architect") | Narrows scope, loses findings (2 vs 8 with same files) | Per-file structure with cross-file section |
| Let Claude read files via tools | 21 tool calls, 2x time, 2x tokens | Pre-read and inline content |
| Trust severity ratings from a single model | Gemini rated 3 things Critical that were Medium | Cross-validate between models |
| Skip cross-validation to save time | Misses 5+ findings, leaves false positives in | Always run Step 3 |
| Use gemini-3.1-pro-preview as default | Capacity-limited, 3x 429 errors in our test | Use 2.5-pro as default, 3.1 for optional deep pass |
| Feed Claude >1.5K lines in "no tools" mode | Hallucinated 12/21 findings on 2,173-line bundle. Splitting into 2 batches (1,185 + 973 lines) produced 30 findings with 0 hallucinations — confirmed 2026-03-16 | Keep bundles under 1,200 lines. Split large file sets into batches. |
| Put source files after a long prompt preamble for Claude | Claude lost 2K lines of source code appended after findings+patterns in cross-validation | Put source files FIRST, instructions after — or shorten the preamble |
| Pass large prompts as `claude -p "$VAR"` argument | CLI hangs indefinitely on ~10KB+ arguments (confirmed 2026-03-15: 293-line bundle hung 20+ min as arg, completed in 24s via stdin) | Pipe via stdin: `echo "$PROMPT" \| claude -p --output-format text` |

---

## Notes

- Sonnet and Haiku benchmarks TBD — will add data as we run comparable tasks
- Model selection may shift as new versions release; update this doc with empirical data, not assumptions
- Cost comparison TBD — will add when we have consistent token counts across enough tasks
- Full audit data: `example-context/tmp/audit-auth-access-control.md`
- Batch-size validation data: `example-context/tmp/audit-input-validation.md` + Domain 2 re-run at `/tmp/domain2-batch-test-20260315-194557/`
- Regression test suite: `dev-reference/tests/audit-regression/`
