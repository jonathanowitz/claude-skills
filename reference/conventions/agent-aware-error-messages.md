# Agent-Aware Error Messages

Error messages in scripts and hooks should read as **prompt continuations** — giving an agent the state, the action to take, and where to look. Terse messages that cite a log path without prescribing the next step transfer debugging work to the agent and are a validated source of validation-skip events (26 events in 7 weeks; brief: `example-context/briefs/agent-self-check.md` § Problem).

## Three-Line Template

```
[STATE]: <what failed — describe the condition, not the tool>
  Action: <verb + object — what to do next>
  Reference: <path or command>  (optional when the action is a direct, unambiguous command)
```

## Three Rules

1. **Action uses verb + object.** "Read /tmp/pr-gate-npm-test.log and fix the failing tests" not "See the log."
2. **Reference is optional.** Include it when the action is "investigate" or "compare"; omit when the action is a direct command that is self-explanatory.
3. **Failure must be reviewable.** A PR reviewer reading the failure should understand what broke without re-running the gate. Avoid run-time-only identifiers (temp file handles, PIDs) in the STATE line.

## Evidence

Mechanical gates (hooks that physically block) reach 100% agent compliance. Advisory rules + memory land at ~55% (maintenance data, 7-week window). The lever that closes this gap is failure messages that read as prompt continuations, not messages that leave the agent guessing at the next step.

The `test-review-gate` hook (2026-04-21) and `pr-merge-gate` hook (same window) are the precedents: advisory version of each rule had ~55% compliance; mechanical enforcement hit 100% immediately.

The 2026-04-25 worktree-first incident is the concrete cost of the current gap: the pre-push hook fired with a terse "wrong branch" message; the agent interpreted it as noise and edited the main checkout anyway.

## Worked Examples

### pr-gate.sh — step failure ([1/5] npm test)

**Before:**
```
  FAIL  npm test (see /tmp/pr-gate-npm-test.log)
```

**After:**
```
  FAIL  npm test — test suite failed
        Action: Read /tmp/pr-gate-npm-test.log, find the failing test, fix the code
        Reference: /tmp/pr-gate-npm-test.log
```

### pre-pr-create-gate.sh — hook denial

**Before:**
```
BLOCKED: pr-gate not green. <reason> Run `bash scripts/pr-gate.sh` from the branch's worktree, fix any failing checks, then retry `gh pr create`.
```

**After:**
```
[STATE]: pr-gate not green — <reason>
  Action: Run `bash scripts/pr-gate.sh` from the branch worktree and fix the failing checks
  Reference: scripts/pr-gate.sh
```

## Where This Convention Applies

- `scripts/pr-gate.sh` — all `step_fail` calls (Slice 1 of #778)
- `~/.claude/hooks/pre-pr-create-gate.sh` — `block()` denial message (Slice 1 of #778)
- Any future gate script in `scripts/` or `~/.claude/hooks/`
- `tools/agent-browse.mjs` — hard-fail output per D11/D12 of the agent-self-check brief
