---
description: Analyze recent sessions to extract patterns, trend telemetry, and improve protocols
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write, Agent, AskUserQuestion]
---

# Maintenance

Periodic self-improvement routine. Analyze recent session captures to find patterns, trend telemetry, audit memory and protocols, and take concrete actions to get better.

## Usage

Argument: `$ARGUMENTS` (optional — ignored, always reads all sessions since last maintenance)

## Phase 1: Gather Session Data

1. Read MEMORY.md and find the `## Last Maintenance` section to get the date of the last run **and its pointer to the prior measurement-targets file**. Read that file — `~/.claude/maintenance/measurement-targets-*.md` (most recent) — its numbered targets are THIS run's scoring baseline; trend each against the current window (Phase 2c / Phase 5). The full targets block lives here, not in MEMORY.md, so it doesn't bloat the every-turn prefix.
2. List all files in `~/.claude/sessions/` sorted by date
3. Read **all session files dated after the last maintenance date**. If no prior maintenance exists, read all sessions.
4. For each session, extract into a working dataset:
   - **Date and topic** from filename/header
   - **Reflections** — each learning event with its type (`redirected`, `assumption`, `validation-skip`, `green-field-error`, `scope-creep`, `protocol-followed`, `efficiency-win`)
   - **Recurring Patterns** section content
   - **Session Metrics** — files modified, issues touched, times redirected, plan changed, self-validation followed
   - **Tool Telemetry** — dead-end calls, guess-vs-read retries, fix iterations, agent rework, unnecessary operations
   - **Protocol gaps** mentioned in any reflection (the "Protocol gap:" lines)
5. Sessions without reflection sections (older format) — note them but skip from analysis

## Phase 2: Aggregate and Analyze

### 2a. Reflection Type Frequency

Count each reflection type across all sessions. Present as a table:

```
Type                | Count | Trend (vs last maintenance)
--------------------|-------|---------------------------
redirected          |       |
assumption          |       |
validation-skip     |       |
green-field-error   |       |
scope-creep         |       |
protocol-followed   |       |
efficiency-win      |       |
```

**Flag any type that:**
- Has count >= 3 in the window (chronic issue)
- Increased vs the last maintenance run (regression)
- Disappeared entirely (was common before, now zero — celebrate or investigate)

### 2b. Telemetry Trends

For sessions with Tool Telemetry, compute:
- **Average dead-end calls** per session
- **Average guess-vs-read retries** per session
- **Average fix iterations** per session
- **Average agent rework** per session
- **Average unnecessary operations** per session

Present as table with min/max/avg. Flag any metric that:
- Average > 1.0 (too high — needs systematic fix)
- Shows upward trend across recent sessions

### 2c. Redirection Analysis

Extract every `redirected` reflection and categorize by root cause theme:
- **UX judgment** (color, placement, wording choices USER overrode)
- **Incomplete fix** (fix worked in isolation but failed in composition)
- **Wrong scope** (created file in wrong directory, committed to wrong branch)
- **Stale assumption** (relied on memory instead of reading current state)
- **Missing context** (didn't check all call sites, didn't trace full pipeline)

Present the themes with examples and counts. The top theme is the highest-priority improvement target.

### 2d. Protocol Gap Inventory

Collect every "Protocol gap:" entry from reflections. For each:
1. Check if the gap has been addressed (search CLAUDE.md and `~/Projects/dev-reference/` for related rules)
2. Classify as: **addressed**, **still open**, or **acknowledged but no rule needed**
3. Open gaps that appear in 2+ sessions are **critical** — flag them prominently

### 2e. Win Patterns

Collect every `protocol-followed` and `efficiency-win` reflection. Identify:
- Which protocols are consistently saving time/preventing errors?
- Which agent patterns (parallel, explore, background) are working well?
- Are there wins that could be generalized into new protocols?

## Phase 3: Audit Memory and Protocols

### 3a. MEMORY.md Audit

Read the current project MEMORY.md. For each entry:
- **Still accurate?** — Cross-reference with recent sessions for contradictions
- **Still relevant?** — Has the information been used or referenced recently?
- **Missing entries?** — Are there patterns confirmed across 3+ sessions that aren't in MEMORY.md?
- **Misplaced entries?** — Run `/memory-transfer` logic: identify `type: feedback` entries that contain general tooling lessons, workflow patterns, or CLI behavior discoveries. These belong in `dev-reference/` or `claude-config/`, not memory. (Memory = user preferences and project state. Docs = general knowledge.)

Prepare a list of proposed additions, updates, removals, **and promotions to dev-reference**.

### 3b. Dev-Reference Audit

List files in `~/Projects/dev-reference/`. Cross-reference with:
- Protocol gaps from Phase 2d — any dev-reference file that should have prevented a recurring issue but didn't
- Efficiency wins from Phase 2e — any dev-reference file that proved especially valuable

Flag dev-reference files that:
- Were cited in protocol gaps but didn't prevent the issue (may need strengthening)
- Haven't been referenced in any recent session (may be stale)

### 3c. CLAUDE.md Rule Effectiveness

Check if any rules in the global or project CLAUDE.md were explicitly violated (reflection type: `validation-skip` or `redirected` that cites a known rule). This indicates the rule exists but isn't being followed — different from a missing rule.

### 3d. Skill & Tool Infrastructure Audit

Audit the command definitions, hooks, and shell scripts that Claude Code relies on for reliability issues that cause **silent failures** (commands that fail but get worked around in-session without fixing the root cause).

1. **Commands** — Read every file in `~/Projects/claude-config/commands/`. For each:
   - Does it prescribe shell pipelines? Test a representative call for each pipeline pattern (don't skip this — "it probably works" is how broken pipes persist across maintenance windows).
   - Does it use external tools (`jq`, `agy`, `gh`, `python3`)? Verify the tool is available and the invocation pattern works. (Cross-model review uses `agy`, the Antigravity CLI — `gemini` is dead per issue #823.)
   - Does it handle errors? A pipeline that silently drops output on failure is worse than one that crashes.

2. **Hooks** — Read every file in `~/.claude/hooks/`. For each:
   - Run it with sample input and verify it produces expected output.
   - Check if the hook's exit code handling matches what Claude Code expects.

3. **Shell scripts in dev-reference** — `ls ~/Projects/dev-reference/agents/*.sh ~/Projects/dev-reference/tests/**/*.sh`. For each:
   - Does it use `--output-format json` piped through `jq`? Flag as fragile — LLM output can contain control characters that break `jq` (evidence: 2026-04-01 `/second-opinion` recurring silent failures).
   - Does it have a fallback for tool unavailability?

4. **Cross-reference with session telemetry** — Look for "retry" or "dead-end" patterns in tool telemetry that recur across 2+ sessions targeting the same tool. These indicate a systematic infrastructure issue, not a one-off.

5. **Security audit logs** — Scan `~/.claude/logs/security-alerts.log` and `~/.claude/logs/tool-audit.log` for the maintenance window:
   - **Alerts:** Count and categorize any `SECRET_IN_OUTPUT` or `SECRET_DETECTED` entries. Even zero is worth reporting — it confirms the scanner is running. If alerts fired, check whether the secret exposure was accidental (file read) or suspicious (command output).
   - **Blocks:** `grep BLOCKED ~/.claude/logs/tool-audit.log` — count pre-tool-use blocks by reason. Frequent blocks on the same pattern may indicate a workflow habit that needs adjusting (e.g., always triggering the base64 check on legitimate encode/decode work).
   - **External fetches:** Count `EXTERNAL_FETCH` entries. Unusual volume or unexpected domains may indicate prompt injection attempts from fetched content.
   - **Agent spawns:** Count `AGENT_SPAWNED` entries. Cross-reference with session count to get agents-per-session rate. A sharp increase may indicate unnecessary delegation.
   - Present as a summary table, not raw log dumps.

Present findings as:
```
| File | Issue | Severity | Fix |
|------|-------|----------|-----|
```

(Evidence: 2026-04-01 — `second-opinion.md` prescribed `--output-format json | jq` for Gemini calls. `jq` failed on control characters in long responses (exit code 5). Workaround succeeded each session, so telemetry only logged "1 retry" — never triggered the 3+ chronic threshold. The broken pattern persisted for multiple maintenance windows until USER noticed the recurring workaround.)

## Phase 4: Take Action

**Automated actions (do these immediately):**

These writes touch `~/.claude/projects/*/memory/*`, which the memory-capture gate (`~/.claude/hooks/memory-capture-gate.sh`) blocks by default. Before item 1, run `touch ~/.claude/memory-disposition.active`; after item 3, run `rm ~/.claude/memory-disposition.active`. This is an approved-commit flow, not a staging write — the flag tells the gate to allow it.

1. Update MEMORY.md — add confirmed patterns, remove stale entries, correct inaccuracies
2. Promote misplaced memory entries — move general-purpose knowledge from memory files to dev-reference docs (per 3a memory-transfer analysis). Delete the memory file and MEMORY.md pointer after promoting.
3. Note the date of this maintenance run in MEMORY.md under a `## Last Maintenance` section
4. Write the refreshed Measurement Targets for the next run to `~/.claude/maintenance/measurement-targets-<this-date>.md` (the full numbered block, scored and updated this run), and repoint MEMORY.md's `## Last Maintenance` line at it. Keep the targets in this file, NOT inline in MEMORY.md — MEMORY.md is re-read on every turn of every session, so the block belongs in the maintenance dir where only `/maintenance` reads it. This is the file Phase 1 of the next run will pick up.

**Proposed actions (present to USER for approval):**

IMPORTANT: Proposed rule/protocol changes go into `~/Projects/dev-reference/` files (workflows, conventions, patterns, checklists), NOT directly into `~/.claude/CLAUDE.md`. CLAUDE.md references dev-reference — it's the pointer, not the content. This keeps protocols portable across projects.

1. Dev-reference updates — new or strengthened protocols/checklists for chronic issues (3+ occurrences)
2. New dev-reference files — for patterns that deserve their own doc
3. CLAUDE.md path additions — only if a new dev-reference file needs to be wired in
4. Rules to retire — any that haven't been referenced or followed (evidence of irrelevance)
5. Session format changes — if the data suggests better ways to capture reflections

## Phase 5: Output

Save a maintenance report to `~/.claude/maintenance/maintenance-YYYY-MM-DD.md`, then copy it to `~/Projects/claude-config/maintenance/maintenance-YYYY-MM-DD.md` so USER can read it from the config repo. Both locations must have the same file — `~/.claude/maintenance/` is the canonical working copy; `~/Projects/claude-config/maintenance/` is the reviewable mirror.

The report should include:
1. **Window analyzed** — date range, session count, how many had reflections
2. **Headline findings** — 3-5 bullet points: what's improving, what's regressing, what's new
3. **Reflection frequency table** (from 2a)
4. **Telemetry trends table** (from 2b)
5. **Top redirection themes** (from 2c) with the #1 improvement target
6. **Protocol gap status** (from 2d) — especially any critical open gaps
7. **Win patterns** (from 2e) — what's working, keep doing it
8. **Actions taken** — what was updated in MEMORY.md
9. **Proposed actions** — what needs USER's approval (specifying which dev-reference file each change targets)
10. **Security audit summary** (from 3d.5) — alerts, blocks, external fetches, agent spawn rate
11. **Comparison to last run** — if a previous maintenance report exists, compare trends
12. **Community contribution candidates** (from Phase 6) — what was pushed and what was skipped

After saving, present a concise summary to USER with the headline findings and any proposed actions that need approval.

## Phase 6: Community Contributions (community-repo)

After the maintenance report is saved, scan for content worth sharing to the `community-repo` repo (`~/Projects/community-repo`).

**Reference:** Read `~/Projects/community-repo/.contribution-guide.md` first. It maps what's shareable, what needs sanitization, and what should never be published. Use it as the filter for all candidates below.

### 6a. Identify Candidates

Scan three sources for shareable content:

1. **New/updated dev-reference files** — `git log --since="<last-maintenance-date>" --name-only ~/Projects/dev-reference/` to see what was added or changed. New files and significantly rewritten files are candidates. Minor tweaks (typos, path fixes) are not.

2. **Win patterns and new protocols from this maintenance report** — Phase 2e wins and Phase 4 proposed actions often contain generalizable insights. If a new protocol was created or an existing one was significantly strengthened, it may be worth sharing.

3. **Hook or settings changes** — `git log --since="<last-maintenance-date>" --name-only ~/.claude/hooks/` and check if `~/.claude/settings.json` was modified. New hooks or hook improvements are high-value contributions.

### 6b. Filter for Shareability

For each candidate, check:
- **Not project-specific** — Skip files with example-specific paths, business logic, database schemas, or credentials
- **Self-contained** — The file should make sense to someone who doesn't know this project
- **Not already contributed** — Check `contributors/USER/index.md` in community-repo to avoid duplicates
- **Substantive** — Skip single-paragraph tips or config-only changes unless they solve a common problem

If a file is valuable but project-specific, note it as "shareable with generalization" — it needs project paths and examples replaced with generic ones.

### 6c. Present Candidates

Present USER with a table:

```
| File | Category | Action Needed | Why It's Shareable |
|------|----------|---------------|-------------------|
| workflows/self-validation-protocol.md | workflows | Generalize paths | Prevents "I made the changes" without proof |
| hooks/secret-scan.sh | scripts | Ready as-is | Few people know hooks exist |
```

Wait for approval before pushing anything.

### 6d. Contribute Approved Items

For each approved item:

1. **Generalize if needed** — Replace project-specific paths (e.g., `~/Projects/example-app`) with placeholders like `~/Projects/<your-project>`. Replace project-specific examples with generic ones. Keep the structure and insights intact.
2. **Add front matter** per `community-repo/CONTRIBUTING.md`:
   ```
   ---
   contributor: USER
   date: [today's date]
   category: [from tags.yaml]
   topics: [from tags.yaml]
   ai_tools: [from tags.yaml]
   summary: [one sentence]
   ---
   ```
3. **Place the file** in `contributors/USER/[category]/[filename]`
4. **Update indexes** — personal `index.md`, root `INDEX.md`, `CHANGELOG.md`
5. **Commit** with format: `USER — add [filename] ([category])`
6. **Push** to origin

### 6e. Track in Report

Add a section to the maintenance report:

```markdown
## Community Contributions (community-repo)

**Pushed:**
- `workflows/self-validation-protocol.md` — generalized from dev-reference

**Skipped:**
- `workflows/schedule-update-runbook.md` — too project-specific

**Candidates for next run:**
- `guides/autonomous-agents.md` — needs generalization, deferred
```

## Guidelines

- **Evidence-based only** — Every finding must cite specific session dates and reflection entries. No speculation.
- **Trends matter more than snapshots** — A single occurrence is noise. Three occurrences is a pattern. Five is chronic.
- **Celebrate wins** — Don't make this a blame report. Protocol-followed and efficiency-win reflections are just as important to track as failures.
- **Actionable output** — Every finding should lead to a specific action (update rule, strengthen protocol, add memory entry, or explicitly "no action needed").
- **Conservative MEMORY.md changes** — Only add entries confirmed across multiple sessions. Remove entries only when contradicted by evidence, not just unused.
- **Don't duplicate session content** — The report should aggregate and analyze, not copy-paste session reflections. Reference sessions by date, don't quote them in full.
- **Compare to prior runs** — Check `~/.claude/maintenance/` for the most recent report and compare trends. This is how we know if we're actually improving.
- **Proposed changes target dev-reference** — Never propose writing rules directly into CLAUDE.md. Propose updates to the specific dev-reference file (e.g., `workflows/pre-implementation-checklist.md`, `workflows/self-validation-protocol.md`). If no appropriate file exists, propose a new one.
