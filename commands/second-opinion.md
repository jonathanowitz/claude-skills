Get an independent second opinion from Gemini (via the Antigravity CLI `agy`) on $ARGUMENTS.

## Preflight — fail loudly if the cross-model leg is unavailable

Run this FIRST. `agy` is the Antigravity CLI (`gemini` is dead — its free tier was retired 2026-06; see issue #823). If `agy` is missing or unauthed, STOP and tell USER — do not silently fall back to a Claude-only review and present it as cross-model.

```bash
command -v agy >/dev/null || { echo "PREFLIGHT FAIL: 'agy' (Antigravity CLI) not installed — cross-model review is OFFLINE. Install: curl -fsSL https://antigravity.google/cli/install.sh | bash"; exit 1; }
# Auth/liveness probe — a real one-shot. Empty output or an auth error means STOP.
agy --model "Gemini 3.5 Flash (Medium)" -p "reply with the single word: ok" 2>&1
```
If the probe doesn't print `ok` (auth error, ineligible-tier, empty), the cross-model leg is offline — report that instead of a degraded review.

## Workflow

1. **Form your own analysis first** — complete your review/assessment before calling `agy`. Don't anchor on its output.

2. **Build a focused prompt file** — avoid quoting issues by writing to a temp file:
   ```bash
   cat <<'PROMPT' > /tmp/agy-prompt.txt
   [Role prime]. [Specific task description].
   PROMPT
   ```
   **Inline file contents** with `$(cat /abs/path)` appended to the prompt file (see step 3) — do NOT rely on `@file`. `@file` is workspace-relative and silently drops paths outside the cwd repo (git worktrees, sibling dirs). For large inputs, truncate (`tail -n 200`).

3. **Call `agy` directly** — plain text output (the default):
   ```bash
   agy --model "Gemini 3.1 Pro (High)" -p "$(cat /tmp/agy-prompt.txt)" 2>&1
   ```
   **`--model` is mandatory and takes the exact display string from `agy models`** (e.g. `"Gemini 3.1 Pro (High)"`, `"Gemini 3.1 Pro (Low)"`). There is **no `-m` short flag** — that was gemini-cli. Plain text is the default and is reliable; don't try to JSON-parse the output.

   **HARD RULE — worktree / out-of-cwd files: inline them, or add their dir with `--add-dir`.** `agy` reads `@file` paths only inside its workspace root (the repo at cwd). Any path outside it — a **git worktree** (`../<repo>-<feature>/`) or sibling dir — is **silently dropped**, and the model reviews a reverse-engineered guess while emitting confident `[BLOCKER]`s about code it never saw. Because the worktree-first workflow runs `/second-opinion` from the main-repo cwd, the files under review are usually outside the workspace. The robust fix is to **inline via `$(cat /abs/path)`** (shell reads the file before `agy` ever runs — workspace boundary is irrelevant). If you must use `@file`, add the directory explicitly:
   ```bash
   agy --add-dir /Users/.../<repo>-<feature>/path \
     --model "Gemini 3.1 Pro (High)" -p "$(cat /tmp/agy-prompt.txt)" 2>&1
   ```
   **Then verify it actually saw the code:** the model must quote a real snippet. If its findings cite identifiers that don't exist in the files, the review is blind — re-run inlining the content before relaying a single finding. (Evidence: `~/Projects/dev-reference/patterns/shell-llm-prompt-composition.md`, 2026-06-06 #842.)

4. **Synthesize — don't passthrough:**
   - **Consensus** (both agree) → high confidence, present as solid findings
   - **Claude only** (you found it, the model didn't) → medium confidence, present with rationale
   - **Model only** (it found it, you missed it) → investigate before presenting
   - **Contradiction** (direct disagreement) → flag for USER with both perspectives

5. **Clean up** — `rm -f /tmp/agy-prompt.txt`

## Role Priming

Every prompt must start with a role. `agy -p` is invoked statelessly — it has no project context.

| Task | Role prefix |
|---|---|
| Code review | "Act as a senior software engineer performing a code review." |
| Security audit | "Act as a senior security engineer." |
| Architecture | "Act as a principal engineer evaluating system design." |
| Test review | "Act as a QA engineer reviewing test coverage." |
| Debugging | "Act as a senior engineer performing root cause analysis." |
| Brief/design review | "Act as a principal engineer reviewing a product brief." |
| Prose / docs | "Act as a technical editor reviewing documentation." |

## Model Selection

Pass the exact display string from `agy models` to `--model`. For a true cross-model second opinion, use a **Gemini** model — `agy` also serves Claude (Opus/Sonnet 4.6) and GPT-OSS, but Claude is not a second opinion *to Claude*.

| Task type | Model | Why |
|---|---|---|
| Deep code analysis, architecture, security | `Gemini 3.1 Pro (High)` | Strongest reasoning |
| Standard review, breadth-first analysis | `Gemini 3.1 Pro (Low)` | Reliable, good finding volume, faster |
| Quick lookups, lightweight review | `Gemini 3.5 Flash (Medium)` | Low latency |
| Fast, high-quality review | `Gemini 3.5 Flash (High)` | Flash successor — faster, stronger |

**Default for most reviews:** `Gemini 3.5 Flash (High)` — good balance of speed and quality.

**Fallback chain:** If a model fails (capacity errors), try the next:
`Gemini 3.1 Pro (High)` → `Gemini 3.1 Pro (Low)` → `Gemini 3.5 Flash (High)` → `Gemini 3.5 Flash (Medium)`

## Scope Discipline

- Send targeted files, not entire repos — inline `$(cat /abs/src/auth.ts)`, not `@.`
- Truncate logs: inline `$(tail -n 200 error.log)` into the prompt file (`agy -p` takes the prompt as an argument, NOT piped stdin)
- Use `--add-dir` for cross-cutting reviews and for any `@file` outside the cwd repo (git worktrees, sibling dirs) — see the HARD RULE in step 3. Inlining is still preferred.
- For background calls, redirect to a file: `agy --model "<model>" -p "..." > /tmp/agy-out.txt 2>&1`

## Severity Tags

Ask the model to classify findings as:
- `[BLOCKER]` — must fix before proceeding
- `[WARNING]` — should fix, risk if ignored
- `[SUGGESTION]` — optional improvement

## Key Principles

- The cross-model review is a **complement**, not a replacement — Claude owns the final synthesis
- Don't treat the output as ground truth — it's a second opinion, verify claims with `grep`
- Prime every prompt with a role that matches the task
- Mind latency (a few seconds to a couple minutes; `--print-timeout` defaults to 5m) — parallelize batch operations when possible
