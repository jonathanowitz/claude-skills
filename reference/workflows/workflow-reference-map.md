# Dev Workflow Reference Map

**Last updated:** 2026-03-17
**Purpose:** Single visualization of the entire dev workflow, which docs govern each step, when they're read, and where gaps exist.

---

## The Workflow (end-to-end)

```mermaid
flowchart TD
    START[Session Start] --> SSP[session-start-protocol.md]
    SSP --> SCOPE{What's the goal?}

    SCOPE -->|New feature| FRAME[Frame the Problem]
    SCOPE -->|Resume work| RESUME[Check next-steps.md<br/>+ resume prompt]
    SCOPE -->|Quick fix| QUICKFIX[Skip to Implementation]

    FRAME --> FRAMESKILL[/frame skill]
    FRAMESKILL --> PROBLEMBRIEF[Problem Brief]
    PROBLEMBRIEF --> SHAPE[Shape the Solution]

    SHAPE --> SHAPESKILL[/shape-project skill]
    SHAPESKILL --> BREADBOARD[Breadboard + Brief]
    BREADBOARD --> GEMINI1[Gemini Review<br/>mandatory]
    GEMINI1 --> USERAPPROVE{USER approves?}
    USERAPPROVE -->|iterate| SHAPE
    USERAPPROVE -->|approved| PREIMPL

    PREIMPL[Pre-Implementation Checklist] --> ISSUE[Create GitHub Issue]
    ISSUE --> WORKTREE[Create Worktree]
    WORKTREE --> IMPLEMENT[Implementation]

    IMPLEMENT --> SELFVAL[Self-Validation Protocol]
    SELFVAL --> TESTS[Write + Run Tests]
    TESTS --> E2ECONV[e2e-test-conventions.md]
    TESTS --> PREPR[Pre-PR Checklist]
    PREPR --> GEMINI2[PR Review Hook<br/>background agent]
    PREPR --> CREATEPR[Create PR]

    CREATEPR --> MERGE{Merge}
    MERGE --> POSTMERGE[Post-Merge Checklist<br/>hook-triggered agent]
    POSTMERGE --> SESSION[/session-capture]
    SESSION --> NEXTSTEPS[Update next-steps.md]
```

## Reference Chain — What Governs Each Step

### 1. Session Start
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Session protocol | `workflows/session-start-protocol.md` | CLAUDE.md line 100 | No |
| Stale context check | MEMORY.md + proactive agent | CLAUDE.md "Stale Context Detector" | No |
| Project CLAUDE.md | Per-project instructions | Auto-loaded by Claude Code | Yes |

**Gap found today:** Session started with a resume prompt pasted into `/clear`. No session-start-protocol was run — went straight to implementation.

### 2. Frame the Problem
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Frame skill | `commands/frame.md` | User runs `/frame` | No — skill exists but isn't gated |
| Problem brief format | Inline in frame skill | — | No |

**Gap found today:** Skipped entirely. Jumped from "plan approved, worktree ready" straight to code. The problem (home gym recovery) was discovered mid-validation and had to be framed retroactively.

### 3. Shape the Solution
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Shape skill | `commands/shape-project.md` | User runs `/shape-project` | No — skill exists but isn't gated |
| Breadboard format | Reference: `briefs/schedule-intake-pipeline.md` | Listed in shape skill (as of today) | Yes (newly added) |
| Gemini review | Mandated in shape skill step 6 | shape-project.md (as of today) | Yes (newly added) |

**Gap found today:** When first asked to shape, I produced an HTML mockup instead of a breadboard. The skill didn't previously define what a breadboard IS. Now it does, with reference examples.

### 4. Pre-Implementation
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Pre-impl checklist | `workflows/pre-implementation-checklist.md` | CLAUDE.md line 13 | Yes ("hard gate") |
| Shaped brief check | First item in pre-impl checklist | pre-implementation-checklist.md (as of today) | Yes (newly added) |
| Behavior map entries | CLAUDE.md line 17 | CLAUDE.md Planning Protocol | Yes |
| Cross-model review | pre-impl checklist item | pre-implementation-checklist.md | Yes |
| Session capture | pre-impl checklist item | pre-implementation-checklist.md | Yes |
| Worktree creation | CLAUDE.md line 51 | CLAUDE.md Git Workflow | Yes |

**Gap found today:** The pre-impl checklist was not run. A plan existed (from a prior session in `~/.claude/plans/`), worktree was ready, and I went straight to coding. The checklist should have caught "no shaped brief with breadboard."

### 5. Implementation
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Self-validation | `workflows/self-validation-protocol.md` | CLAUDE.md line 10 | Yes ("hard gate") |
| E2E conventions | `conventions/e2e-test-conventions.md` | CLAUDE.md line 64 | Yes ("hard gate") |
| Test plan conventions | `conventions/test-plan-conventions.md` | CLAUDE.md line 63 | No |
| Mobile-first UX | `patterns/mobile-collapsible-ui.md` | CLAUDE.md line 62 | No |
| CSS rendering preflight | Inside self-validation-protocol.md | — | Yes |

**Gap found today:** E2E conventions doc was read, but the newly-added sections (overlay suppression, scenario accounts, targeted test runs) were written AFTER discovering the issues. The conventions doc is reactive, not preventive.

### 6. Pre-PR
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Pre-PR checklist | `workflows/pre-pr-checklist.md` | CLAUDE.md line 53 | Yes ("hard gate") |
| PR review hook | `~/.claude/hooks/` PR_CREATE_HOOK | CLAUDE.md "PR_CREATE_HOOK signal" | Auto |

**Status today:** Haven't reached this step yet — still in validation.

### 7. Post-Merge
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Post-merge checklist | `workflows/post-merge-checklist.md` | CLAUDE.md line 55 | Yes ("hard gate") |
| Post-merge hook | `~/.claude/hooks/` POST_MERGE_HOOK | CLAUDE.md "POST_MERGE_HOOK signal" | Auto |
| Project completion | `workflows/project-completion-protocol.md` | CLAUDE.md line 94 | No |
| Behavior map update | `architecture/app-behavior-map.md` | Post-merge checklist | Yes |

### 8. Session End
| What | Doc | Loaded from | Hard gate? |
|------|-----|-------------|------------|
| Session capture | `/session-capture` skill | CLAUDE.md line 104-108 | No (prompted) |
| Next-steps update | `conventions/next-steps-convention.md` | CLAUDE.md line 108 | Yes |
| Session summary format | `templates/session-summary-template.md` | CLAUDE.md line 106 | No |

---

## What CLAUDE.md Actually Does

CLAUDE.md is loaded at conversation start (auto-injected by Claude Code). It contains:

1. **Inline rules** — core principles, trust/expertise, tone
2. **Hard-gate references** — "run through X, this is a hard gate" (7 instances)
3. **Soft references** — "reference X when doing Y" (8 instances)
4. **Hook signals** — POST_MERGE_HOOK, PR_CREATE_HOOK, WORKTREE_SETUP_COMPLETE
5. **Proactive agent triggers** — data verification, stale context, pre-PR validation

**CLAUDE.md does NOT:**
- Enforce reading order (it's a flat list, not a flowchart)
- Gate on `/frame` or `/shape-project` — it says "Shape Up" but doesn't require the skills
- Reference `development-process.md` at all (the master workflow doc is orphaned)

---

## Gaps Identified

| Gap | Severity | Fix |
|-----|----------|-----|
| **`development-process.md` is orphaned** — not referenced from CLAUDE.md or any checklist. It's the master workflow but nothing points to it. | High | Add reference from CLAUDE.md, or merge its unique content into existing docs |
| **No gate between "plan approved" and "code"** — CLAUDE.md says "pause after plan approval" but doesn't require a shaped brief with breadboard | High | Fixed today: pre-impl checklist now gates on shaped brief |
| **`/frame` and `/shape-project` aren't hard-gated** — they exist as skills but nothing forces their use before implementation | Medium | Add to CLAUDE.md Planning Protocol as explicit steps |
| **E2E conventions are reactive** — lessons get added after issues are discovered, not before tests are written | Low | Acceptable — conventions grow organically. The "read before writing" gate in CLAUDE.md helps |
| **Session-start protocol is skippable** — resume prompts bypass it entirely | Medium | Consider making it a hook or adding to CLAUDE.md as stronger language |
| **Master workflow doc references Codex CLI** — no longer used | Low | Updated today (v1.1) but still has Codex references in Stages 4-5 |
| **No explicit "send to Gemini" step in CLAUDE.md** — it's in the pre-impl checklist and shape skill but not in the top-level planning protocol | Medium | Add to CLAUDE.md Planning Protocol |

---

## Today's Session: What Was Read vs. What Should Have Been

| Step | Should have read | Actually read | Result |
|------|-----------------|---------------|--------|
| Session start | session-start-protocol.md | Resume prompt only | Skipped protocol |
| Before implementation | pre-implementation-checklist.md | Not read | Jumped to code |
| Before implementation | Shaped brief check | N/A (didn't exist as gate) | No brief, no breadboard |
| Writing tests | e2e-test-conventions.md | Yes (via explore agent) | Good — but overlay/account issues discovered empirically |
| Mid-validation | /frame | Yes (after USER asked) | Retroactive framing |
| Mid-validation | /shape-project | Attempted but wrong format | Produced mockup, not breadboard |
| Reshaping | shape-project + Gemini | Yes (after correction) | Final brief is solid |
