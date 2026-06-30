;# Autonomous Agent Workflows

**Created:** 2026-03-15
**Status:** Living document — evolve as we learn

---

## Philosophy

Agents should do focused work without babysitting. The key insight: **you can't paper over bad docs or missing tests by steering the agent in real time.** If an agent needs hand-holding, that's a signal to improve the spec, the docs, or the validation — not to sit there and watch it.

Build incrementally. Start with read-only agents, prove the pattern, then expand scope.

## Foundation: Agent Definitions

An agent is a markdown file that defines:
- **What** it does (clear, bounded scope)
- **What tools** it can use (minimal set)
- **What inputs** it needs (spec, issue, file paths)
- **What output** it produces (file, PR comment, stdout)
- **What validation** proves it worked

Agent definitions live in `~/Projects/dev-reference/agents/`.

### Anatomy of an Agent Definition

```markdown
# Agent: <name>

## Purpose
One sentence. What does this agent do?

## Trigger
When should this agent run? (manual, post-merge, pre-PR, on schedule)

## Inputs
- What context does the agent need?
- File paths, issue numbers, spec content, etc.

## Allowed Tools
Explicit list. Start restrictive, widen only when needed.

## Instructions
Step-by-step. Written as if briefing a competent but context-free contractor.

## Output
What does the agent produce? Where does it go?

## Validation
How do we know it worked? What does "good" look like?
```

## Running Agents

### Headless Mode (simplest)

```bash
claude -p "$(cat ~/Projects/dev-reference/agents/agent-name.md)" \
  --allowedTools "Read,Glob,Grep" \
  --output-format stream-json
```

The agent definition IS the prompt. The `--allowedTools` flag enforces the tool boundary — the agent literally cannot use tools you didn't list.

### From Within a Session

Use the Agent tool with a specific subagent_type or a detailed prompt. Good for kicking off work while you continue doing something else:

```
Agent(run_in_background: true, prompt: "Run the pre-PR validation agent for branch feature/foo")
```

### Key Flags

| Flag | Purpose |
|------|---------|
| `--allowedTools "Read,Glob,Grep"` | Restrict to read-only |
| `--allowedTools "Read,Glob,Grep,Edit,Write,Bash"` | Full implementation access |
| `--output-format stream-json` | See work in real-time |
| `--output-format json` | Structured output for piping |
| `--continue` | Resume a previous conversation |
| `--model sonnet` | Use a cheaper/faster model for simple tasks |

## Starter Agents

Build these first. They're read-only, low-risk, and immediately useful.

### 1. Code Review Agent

**Trigger:** Before creating a PR (already wired into PR_CREATE_HOOK)
**Tools:** `Read, Glob, Grep, Bash(git diff only)`
**Does:** Reviews the branch diff for security issues, debug artifacts, missing tests, architectural concerns.
**Output:** Findings summary (stdout or PR comment)

### 2. Brief Verifier Agent

**Trigger:** After writing or updating a brief
**Tools:** `Read, Glob, Grep, Bash(gh issue view, psql read-only)`
**Does:** Checks all quantitative claims in a brief against live data — row counts, issue statuses, branch existence.
**Output:** Verified/stale report

### 3. Stale Context Detector

**Trigger:** Session start
**Tools:** `Read, Glob, Grep, Bash(git, gh)`
**Does:** Checks MEMORY.md, next-steps.md, and open issues for drift since last session.
**Output:** List of stale items to address

### 4. Test Coverage Reviewer

**Trigger:** After implementation, before PR
**Tools:** `Read, Glob, Grep`
**Does:** Compares changed files against test files. Flags new endpoints/functions without corresponding tests.
**Output:** Coverage gaps list

---

## Bug Fix Agent Pattern

The highest-leverage pattern for autonomous bug fixing: don't jump to a fix — write a failing test first, then delegate the fix to a subagent.

### Why This Works

Writing the reproduction test forces the main agent to understand the bug before attempting a fix. The subagent gets a binary pass/fail contract with zero ambiguity — no vague spec to misinterpret, no judgment calls about "done."

### Workflow

1. **User reports a bug** (symptom description, issue number, screenshot, etc.)
2. **Main agent investigates** — reads code, reproduces the issue, understands root cause
3. **Testability gate:** Can you write a failing test against the existing code without restructuring? If the logic is buried in global state, DOM manipulation, or tightly coupled modules, you've found a refactor — not a bug fix. File a refactor issue and stop. Don't force the pattern where it doesn't fit.
4. **Main agent writes a failing test** that captures the broken behavior. The test should pass once the bug is fixed.
4. **Main agent delegates to a subagent** in a worktree with one instruction: make this test pass. The subagent must NOT modify the test — only application code.
5. **Validation is automatic** — `npm test` passing IS the proof.

### Red/Green Contract

The bug fix pattern is a strict Red/Green TDD cycle split across two agents:

1. **RED (test-writer / main agent):** Write a test that fails against current code. Run it. Confirm the failure is behavioral (wrong value, missing call), not structural (import error, missing file). The failing test output is the handoff artifact.
2. **GREEN (fixer subagent):** Make the test pass by changing only application code. Run the full suite. The passing test output is the completion proof.

The subagent's contract is: **fix the code, not the test.** If the subagent can't make the test pass without modifying it, that's a signal to escalate back to the main conversation — either the test is wrong or the fix requires architectural judgment.

**Verification is mechanical, not self-reported.** The test runner's exit code is the only authority. An agent saying "I believe the fix is correct" without test output is not done.

### In-Session Example

```
# 1. Investigate and write the failing test in the main conversation
#    (read the bug report, trace the code, write the test)

# 2. Delegate the fix
Agent(
  isolation: "worktree",
  prompt: "A failing test has been added at tests/unit/schedule-filter.test.js,
    test name: 'should not show past events when filter is active'.
    This test reproduces issue #372.
    Make this test pass by fixing the application code.
    Do NOT modify the test file.
    Run npm test to verify all tests pass before reporting done."
)
```

### Headless Example

```bash
# Main agent already wrote the failing test and committed it

# Subagent picks it up in a worktree
git worktree add ../example-app-fix-372 -b fix/372
cd ../example-app-fix-372
npm install

claude -p "A failing test exists at tests/unit/schedule-filter.test.js,
  test name: 'should not show past events when filter is active'.
  Make this test pass by fixing the application code.
  Do NOT modify the test file.
  Run npm test to verify all tests pass." \
  --allowedTools "Read,Glob,Grep,Edit,Bash" \
  --output-format stream-json
```

---

## Graduating to Implementation Agents

Once read-only agents are reliable, you can graduate to agents that write code. The requirements get stricter:

### Prerequisites

1. **Test suite you trust** — Agent-written code must pass the same suite your code does. If the tests are flaky or incomplete, the agent will produce garbage that looks like it works.
2. **Strict linting/type checking** — Catches classes of bugs before tests even run. The stricter the better for agents.
3. **Clear spec** — A GitHub issue or brief with acceptance criteria. Vague specs produce vague code.
4. **Worktree isolation** — Implementation agents always work in a worktree. Never on main.
5. **Always spawn agents for worktree work** — The main shell resets cwd after each Bash call. Running `cd /worktree && command` in the main conversation is error-prone because every subsequent command loses the directory. Spawn an agent (with `isolation: "worktree"` or a background agent) for any multi-step work in a worktree — tests, pre-PR checklists, implementation. Single quick checks can use a one-off absolute-path command.
6. **Predefine output location in the prompt** — Before launching any agent that produces written output, specify exactly where the output goes as part of the agent prompt. Two patterns:
   - **Return in result message** (preferred): The agent returns its output in its completion message. The orchestrator writes it to the correct file. This avoids write-permission issues entirely.
   - **Write to a predefined path**: If the agent must write files directly (e.g., many files, large output), the prompt must name the exact output path — and that path must be writable from the agent's cwd. If the target is in a different repo, launch the agent from that repo's directory.
   Never leave the output location for the agent to figure out. An agent that does 17 minutes of research and then can't write the result has wasted 17 minutes.
   (Evidence: 2026-04-02 — behavior map enrichment agent read the entire app codebase, prepared 101 annotated entries, then was blocked by cwd write permissions. All work lost.)

### Implementation Agent Pattern

```bash
# 1. Create worktree
git worktree add ../example-app-feature-x -b feature/x

# 2. Run agent in worktree context
cd ../example-app-feature-x
claude -p "$(cat ~/Projects/dev-reference/agents/implement-spec.md)

## Spec
$(cat ~/Projects/example-context/briefs/feature-x.md)

## Issue
$(gh issue view 999 --json title,body --jq '.title + \"\n\" + .body')" \
  --allowedTools "Read,Glob,Grep,Edit,Write,Bash" \
  --output-format stream-json

# 3. Review output next morning / after the run
```

### Validation Stack for Implementation Agents

Every implementation agent run should end with:

1. `npm run lint` — zero warnings
2. `npm test` — all tests pass
3. `git diff --stat` — review scope (did it touch files it shouldn't?)
4. Self-review: agent re-reads its own changes and flags concerns

Encode this in the agent definition itself — the agent should refuse to report "done" unless all gates pass.

### Silent de-scoping is a blocker, not a deferral

A dispatched agent that cannot deliver a REQUIRED item without a conflict — a required deliverable that breaks a test, a spec line that contradicts existing code, a fix that needs architectural judgment — must **STOP and surface it as a blocker for the orchestrator to decide.** It must never (a) quietly drop the required item and report a tidy "deferred to a follow-up," or (b) bend product code/copy purely to make a test pass. Both read as success in the agent's summary and ship the wrong thing.

This is sharper than the Red/Green Contract's "fix the code, not the test." Two failure modes it adds:

- **Working backward from a test onto product code.** Changing a heading, label, route, or return shape *because a test asserts it* — rather than because the product needs it — is the inverse of TDD. The test is supposed to encode product intent; if it doesn't, the test is wrong (escalate), not the product.
- **"Frozen tests" over-applied.** A test is frozen only if it's an APPROVED spec for the *current* slice. A pre-existing, non-approved test that conflicts with a new required deliverable is *editable to accommodate the requirement* — treating all tests as immovable is what pushes an agent to bend product code instead of fixing the test.

**Orchestrator side: verify every reported "blocker"/deferral before shipping.** A two-stage (implement → ship) handoff must not assume Stage 1's "blockers" are real or its "done" is complete. Re-run the agent's failing case, grep the diff for the required deliverable, confirm each deferral is genuine. This is the only thing that catches a silent de-scope — no mechanical gate does.

(Evidence: 2026-06-22 — #926 S3a.1. A Stage-1 implementation agent was told to wire `/teams` with `beforeLoad: requireSignedIn`. A pre-existing, non-approved router test crashed under the guard, so the agent dropped the required guard AND changed the page heading copy purely to keep that test's regex matching — then reported it as a clean "deferred" decision. Caught only because the orchestrator verified the deferral against the original scope; the guard was restored and the pre-existing test was updated to accommodate it.)

### E2E Test Agent Pattern

E2e tests require deep knowledge of the test user's state and the app's initialization flow. A dedicated agent with focused context writes better tests than the main conversation agent juggling implementation + process + test infrastructure.

#### When to Spawn

- Stage 4: writing e2e test specs from the brief's Verification section
- Post-implementation: running e2e tests and fixing failures
- Never defer to "next session" — spawn the agent before ending the current session

#### Required Context (pass ALL of these in the prompt)

The agent needs to understand the full state chain, not just the behavior being tested:

1. **Behavior map entries** for the feature (from the brief or `app-behavior-map.md`)
2. **Test user state** — read and inline the relevant sections of:
   - `e2e/test-config.js` (comp IDs, gym IDs, user IDs, constants)
   - `e2e/fixtures/auth.setup.js` (profile state per user: home_gym, follows, onboarding flags)
3. **App initialization flow** — inline or summarize:
   - Smart default evaluation (`evaluateSmartDefault` in app.js): what tier does each test user hit?
   - Overlay/toast triggers: what prompts appear based on user state?
   - `data-app-ready` signal: when is the app safe to interact with?
4. **E2e conventions** — reference `~/Projects/dev-reference/conventions/e2e-test-conventions.md`
5. **The implementation code** — the actual component/module being tested

#### Key Rule

**Tests must be written for the actual user state, not a generic "load page, see content" flow.** Before writing any helper function, the agent must trace: this user has X follows → smart default activates Y mode → the page shows Z elements → the test interacts with Z, not with elements from a different mode.

#### Validation

The agent must:
1. Run the full e2e spec file and show all tests passing
2. Run a second time to confirm stability (no flaky passes)
3. Run `npx vitest run` to confirm no unit test regressions

(Evidence: 2026-04-02 #518 — e2e tests written without this pattern assumed Tier 3 smart default when the test user hits Tier 1. Dedicated agent with correct context fixed all tests in one pass after 90+ minutes of inline debugging failed.)

## Building Over Time: Maturity Levels

### Level 1: Read-Only Assistants (start here)
- Code review, brief verification, stale detection
- Zero risk — worst case is a bad report you ignore
- Builds trust in the pattern

### Level 2: Constrained Writers
- Test generation, doc updates, changelog entries
- Low risk — output is reviewable, easy to revert
- Teaches you what good specs look like

### Level 3: Spec-Driven Implementation
- Feature work from a brief, bug fixes from an issue
- Medium risk — requires good tests and review
- The "night shift" pattern

### Level 4: Multi-Agent Pipelines
- One agent writes code, another reviews it, another runs tests
- Agent feedback loops (like Jamon's Codex-watching-Claude experiment)
- High complexity — only worth it for large, well-defined scopes

## Regression Testing for Agent Pipelines

Agents that produce judgment-based output (security audits, code reviews, brief verification) learn empirically — prompt tuning, model selection, batch sizing, calibration heuristics. These learnings are easy to lose when you change one variable.

**Core principle:** If an agent pipeline has learned something the hard way, encode it as a regression test. Don't rely on the operator remembering.

### What to Test

1. **Known-answer tests** — A small set of inputs with planted signals where you know the correct output. Run the pipeline and diff against expected findings.
2. **Must-NOT-find tests** — Clean patterns that look superficially similar to real issues. If the pipeline flags them, it's hallucinating or over-triggering.
3. **Calibration invariants** — Rules about severity, scope, or confidence that must hold across all runs (e.g., "admin-only endpoints get -1 severity tier").
4. **Process invariants** — Rules about the pipeline itself (e.g., "batch size < 1.5K lines", "patterns only in cross-validation step").

### Structure

```
tests/<pipeline-name>-regression/
├── test-files/          # Inputs with planted signals
├── expected-findings.md # Ground truth: what to find, what NOT to find, calibration rules
└── run-regression.sh    # Runs the pipeline, checks automated invariants, flags manual review items
```

### When to Run

- **After any prompt change** — New instructions can suppress previously-caught findings or introduce false positives.
- **After model upgrades** — A new model version may shift behavior. Run regression before trusting it.
- **After process changes** — Batch size, prompt ordering, tool access, patterns library additions.
- **Periodically** — Monthly or after long gaps, to catch drift from upstream model updates.

### Building Regression Tests

1. **Start from real findings.** Take the highest-confidence findings from your pipeline and create minimal test files that contain those exact patterns plus clean counterexamples.
2. **Keep test files small.** The regression test should run in under 5 minutes. 2-3 files with 5-10 planted vulns is enough.
3. **Document why each expected finding has its severity.** This encodes calibration heuristics so they survive across sessions.
4. **Automate what you can, flag the rest for manual review.** Hallucination checks (referencing non-existent files/functions) are automatable. Severity calibration requires human judgment.

### Example

The security audit pipeline has a regression suite at `tests/audit-regression/`:
- Small test (2 files, 166 lines): 9 planted vulns + 4 clean patterns
- Stress test (2 files, 680 lines): same vuln classes embedded in realistic boilerplate
- Expected findings with severity calibration and pattern references
- Shell script with `--stress` flag, auto-checks for hallucinated files

### Integrity Controls

A regression test is only useful if the pipeline discovers findings from code analysis — not from memorized answers. When the same agent that runs the pipeline also authored the test files, there's a risk of unconscious overfitting: tuning prompts to fish for known test patterns rather than genuinely finding vulnerabilities.

**Guardrails:**

1. **Test files are frozen.** The primary agent (Claude) should not update test files unilaterally. The human approves all changes to test inputs and expected findings.

2. **Prompt changes must be justified by real-domain findings**, not regression test results. The regression test catches regressions — it should not drive prompt engineering. If a prompt change is made solely to pass the regression test, that's overfitting.

3. **Periodically rotate test files.** After completing new audit domains, build fresh test files from those real findings and retire old ones. This prevents the test suite from going stale and prevents long-term memorization.

4. **Independent model review of the test suite.** Use a different model (Gemini) to periodically audit the regression test files themselves. The reviewing model has no shared memory, no conversation history with the primary agent, and no incentive to confirm biases.

   The independent review checks for:
   - **Planted vulns that are too obvious** — trivially caught by any prompt, not actually testing pipeline quality
   - **Clean patterns too dissimilar from vulns** — easy to distinguish means the false-positive test is weak
   - **Missing vulnerability classes** — real audit has found patterns the test doesn't cover
   - **Answer leakage in comments** — test file comments that make findings trivially extractable without code analysis
   - **Prompt-test coupling** — whether the audit prompts contain language that specifically targets the test patterns

   Track the last independent review date in `tests/audit-regression/integrity-log.md`. Target interval: every 4-6 weeks, or after any major prompt/process change.

5. **Separation of concerns.** The agent that tunes prompts should not be the same invocation that evaluates regression results. Run the regression script headless (`run-regression.sh`), then have a fresh session review the output against expected findings.

---

## Agent Debrief Convention

Every sub-agent must write a debrief before reporting done. The debrief captures what the agent learned — without it, debugging patterns and efficiency insights are lost.

### File Location
`tmp/agent-debrief-<task>.md` — where `<task>` matches the agent role (e.g., `test-writer`, `fixer`, `review`).

### Format

```markdown
# Agent Debrief: <task>

**Agent:** <role (test-writer, fixer, orchestrator)>
**Issue:** #<number>
**Duration:** <approximate wallclock>

## What Was Done
- [1-2 sentences summarizing the work]

## Approaches Tried
1. [Approach] → [outcome: worked / failed because X]
2. [Approach] → [outcome]

## Fix Iterations
- [N] iterations total
- [describe what required retry and why]

## Patterns Discovered
- [anything surprising about the codebase, the bug, or the tooling]
- [race conditions, naming conventions, state management quirks]

## Missing Context
- [what would have helped if included in the prompt]
- [files that should have been listed as inputs]

## Tool Telemetry
- Dead-end calls: [N] — [what failed]
- Guesses vs greps: [N] — [what was guessed]
- Files read: [N]
- Tests run: [N]
```

### Role-Specific Extensions

The format above is the baseline. Role-specific agents extend it with sections tailored to their output:

- **Test-writer** → adds selector/API verification logs, selector gaps, suggested fixer context. See `agents/test-writer.md`.
- **Fixer** → adds root cause analysis table, scope audit log, async/state hazards, regressions introduced. See `agents/fixer.md`.
- **Orchestrator** → doesn't write its own debrief; instead collects and cross-references sub-agent debriefs. See `agents/orchestrator.md`.

When creating a new agent role, start from the baseline format and add sections for the agent's most valuable learnings — the things the orchestrator (or next session) would lose without a record.

### Why This Matters

Without debriefs:
- Fix iterations are invisible (the orchestrator doesn't know if the fixer took 1 or 10 attempts)
- Patterns discovered by sub-agents are lost (each new agent starts from zero)
- Missing context is never fed back into prompt design

(Evidence: #387 — test-writer and fixer agents produced no debriefs. The orchestrator couldn't report fix iteration counts. Patterns like "async IIFE race condition" were only caught by cross-model review, not by the agent itself.)

### Orchestrator Responsibility

The orchestrator should:
1. Include the debrief requirement in every sub-agent prompt
2. Read all debriefs after agents complete
3. Extract learnings into the session summary
4. Flag recurring "missing context" items for prompt improvement

---

## Telemetry Hard Gate

**Every agent prompt MUST include the following block.** Copy-paste it verbatim into the prompt. An agent that reports "done" without this telemetry section has not completed its work.

```
## Telemetry (hard gate — include in your final response)

Before reporting done, include this telemetry block in your response message
(not in a file — in the message itself so the orchestrator sees it immediately):

### Agent Telemetry
- **Tool calls:** N total (N productive, N dead-end)
- **Dead-end details:** [what failed and why, or "none"]
- **Fix iterations:** N — [what required retry]
- **Files read:** N | **Files modified:** N
- **Tests run:** N pass / N fail
- **Guesses vs greps:** N times guessed at a path/selector/value instead of grepping first
- **Missing context:** [what would have helped if included in the prompt, or "none"]
- **Approaches tried:** [list approaches and outcomes, especially failed ones]

This is a hard gate. Do not skip it.
```

**Why this matters:** Without telemetry in the return message, the orchestrator has no visibility into agent performance. Dead-end calls, fix iterations, and missing context are the inputs that improve future prompts. A debrief file is good for the record; telemetry in the response is what the orchestrator actually acts on.

**Orchestrator responsibility:** After receiving agent results, check for the telemetry block. If missing, flag it in the session summary as a process failure. Extract patterns from telemetry across agents to improve future prompts.

---

## Iterative Context Retrieval for Cold-Start Agents

When you can't predict which files an agent will need — especially for bug fixes in unfamiliar areas or broad refactors — don't try to hand-pick files. Let the agent discover context iteratively.

### The Problem

Hand-picking files (`## Files to touch: exact paths`) works when *you* know the codebase. It breaks when:
- The bug could be in any of 10 files and you're not sure which
- The agent needs to understand naming conventions before it can search effectively
- The scope is broad enough that listing all relevant files would eat the context budget

### The Pattern: Search → Score → Refine → Loop

1. **DISPATCH** — Start with broad searches: error message text, function names, key patterns. Cast a wide net.
2. **EVALUATE** — Score each result for relevance (high/medium/low). Explain why. Identify gaps: "I found the handler but not where it's called from."
3. **REFINE** — Use discovered terminology to narrow the search. First search reveals naming conventions; second search uses them.
4. **LOOP** — Max 3 cycles. Stop when enough high-relevance files are found to understand the problem.

### When to Use

- Bug fix agents where the root cause location is uncertain
- Agents exploring unfamiliar parts of the codebase
- Any agent prompt where listing `## Files to touch` feels like guessing

### When NOT to Use

- You know exactly which files are involved (most feature work from a shaped brief)
- The agent is working from a failing test that already points to the code (bug fix pattern)
- Read-only agents with a narrow question ("what does this function return?")

### In a Prompt

```
## Context Discovery

Do NOT start implementing immediately. First, discover the relevant code:

1. Search for "<error message or function name>" across the codebase
2. For each result, assess: is this the producer, consumer, or tangential?
3. If you haven't found both the producer and consumer of the bug, search again
   using terminology you discovered in step 1
4. After max 3 search rounds, you should have the full picture. Then fix.
```

(Insight: from the "iterative-retrieval" pattern — agents don't know the codebase's terminology until they start searching. The first search finds naming conventions, the second search uses them.)

---

## Reviewer/Author Separation

**Principle:** The agent that writes code should not be the same invocation that reviews it.

When the same agent (or same session context) writes and reviews, the review is biased — it already "understands" the intent and won't catch issues a cold reader would spot. This is the autonomous-agent equivalent of reviewing your own PR.

### How to Apply

- **In-session review personas** (current night-shift approach): acceptable for now. The personas are separate Agent calls, but they share session context. Good enough for Level 3 maturity.
- **Headless review** (Level 4 maturity): run review personas as separate `claude -p` invocations that only see the diff. True context isolation — the reviewer has no memory of the implementation journey.
- **Cross-model review** (strongest): use a different model for review than implementation. Already partially implemented via `/second-opinion` with Gemini.

### The Practical Test

If a reviewer could approve the code *without having seen the implementation happen*, the review is independent. If the reviewer needs the implementation context to understand the code, the code isn't self-explanatory enough — that's a finding in itself.

---

## Anti-Patterns

- **Babysitting defeats the purpose.** If you're watching the agent work, you're doing it wrong. Fix the spec/docs/tests instead.
- **Vague specs produce vague code.** "Make the admin page better" will waste tokens. "Add a bulk-delete button to the admin teams table that calls DELETE /api/admin/teams with selected IDs" will ship.
- **Skipping validation is expensive.** An agent that "finishes" but leaves broken tests creates more work than doing it yourself.
- **Too many tools too early.** Start restrictive. An agent with Bash access can do damage. Earn trust incrementally.
- **Not improving the loop.** Every agent run should teach you something. If the agent made the same mistake twice, fix the docs or the spec template — don't just correct it again.
- **Silent de-scoping reads as success.** An agent that drops a required deliverable or bends product code to pass a test will return a tidy summary that looks done. Require agents to escalate conflicts as blockers, and verify every reported deferral against the original scope. See "Silent de-scoping is a blocker, not a deferral."

## Integration with Current Workflow

This layers on top of what we already have:

| Existing | Agent Enhancement |
|----------|-------------------|
| Briefs in `example-context/briefs/` | Become agent input specs |
| GitHub issues | Agent reads acceptance criteria from issue body |
| CLAUDE.md conventions | Agent follows them automatically |
| Pre-PR checklist | Becomes an automated agent gate |
| Post-merge checklist | Already partially automated via hooks |
| Session captures | Agent runs get captured the same way |

No need to change the workflow — agents slot into it.
