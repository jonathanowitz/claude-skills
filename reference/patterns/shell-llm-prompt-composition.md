# Shell + LLM Prompt Composition

> How to safely build prompts from dynamic content (LLM output, diffs, file contents) in shell scripts.

## The Problem

LLM output routinely contains single quotes (`Don't`, `it's`), backticks, heredoc terminators, and other shell metacharacters. Expanding this content inside heredocs or shell variables breaks parsing:

```bash
# BROKEN — if claude-review.md contains a single quote, the shell chokes
REVIEW=$(cat <<EOF
$(cat /tmp/claude-review.md)
EOF
)
```

## The Fix: Temp File Composition

Build the prompt in a temp file. Use quoted heredoc markers (`<<'EOF'`) for static parts, and plain `cat` for dynamic parts:

```bash
PROMPT=$(mktemp)

# Static header — quoted heredoc prevents any expansion
cat > "$PROMPT" <<'EOF'
You are a code reviewer. Analyze the following diff:
EOF

# Dynamic content — no shell interpretation, just file concatenation
cat /tmp/some-llm-output.md >> "$PROMPT"

# More static instructions
cat >> "$PROMPT" <<'EOF'

Organize findings by severity: Blockers > Warnings > Notes.
EOF

# Pipe to LLM
RESULT=$(claude -p --output-format text < "$PROMPT")
rm -f "$PROMPT"
```

## Why Not Just Quote the Heredoc?

Quoting the heredoc marker (`<<'EOF'`) prevents `$variable` expansion, but it doesn't help when the content is injected via `$(command substitution)` — that expansion happens *before* the heredoc is processed.

**Worse failure mode** — when you WANT substitution but use a quoted heredoc anyway:

```bash
# DOES NOT WORK — single-quoted PROMPT blocks substitution
agy --model "Gemini 3.1 Pro (Low)" -p "$(cat <<'PROMPT'
Review these files:
$(cat /path/to/file1)
$(cat /path/to/file2)
PROMPT
)"
```

The `$(cat /path/to/file1)` is passed to gemini as **literal text** — not expanded. Gemini then either (a) tries to read the files itself and hits workspace-scope errors, or (b) silently fabricates findings based on context clues in the prompt. Either way you get garbage you might not immediately recognize as garbage.

**The right form when you need substitution AND control** is temp-file composition (above) — `cat` (unquoted) and `cat >> "$FILE"` from the file system, which always expand `$()` because they're regular command invocations, not heredoc bodies.

## How to detect that prompt building silently failed

When the LLM output looks plausible but you suspect file contents didn't actually reach it, check for these tells:

1. **The LLM quotes content that doesn't match your files.** If you asked Gemini to review `tests/foo.test.js` and its response mentions test names like `"should handle X gracefully"` that don't exist in your file, the file contents weren't inlined.
2. **The LLM hits workspace/path errors in its tool calls** (visible in the CLI output before its final response). Means it received a literal path string and tried to resolve it itself.
3. **The response is suspiciously generic** — applies equally to "any file of this type" rather than citing specific line numbers or quoting actual code.

**Validation rule:** when reviewing dynamic content with an LLM, ask it to **quote** something specific from the inlined material. If it can't, the inlining failed.

## Gemini `@file` silently drops paths outside the workspace root

Distinct from the quoting problem above: even with a correctly composed prompt and
proper `@file` syntax, `gemini` only reads `@file` references that resolve INSIDE
its workspace root (the repo at cwd) or `~/.gemini/tmp/<project>/`. A path outside
that — most commonly a **git worktree or sibling directory** — is silently skipped
with a `Path not in workspace ... resolves outside the allowed workspace
directories` line, and Gemini then **reviews a reverse-engineered guess of the
missing file** while sounding fully confident (it will emit `[BLOCKER]` findings
about code it never saw).

This is a STANDING trap for the worktree-first workflow: running `/second-opinion`
from the main-repo cwd on an artifact that lives in `../<repo>-<feature>/` means the
files under review are *always* outside the workspace.

**Fix:** pass every out-of-workspace directory explicitly with `--add-dir`:

```bash
agy --model "Gemini 3.1 Pro (High)" -p "$(cat /tmp/prompt.txt)" \
  @/abs/path/inside/repo.ts \
  --add-dir /Users/.../<repo>-<feature>/contract
```

**Detection (do this BEFORE trusting any finding):**
- Scan the top of Gemini's output for `Path not in workspace` / `resolves outside
  the allowed workspace directories`, or a note that it "reverse-engineered" or
  "omitted" a file. If present, the review is partly or wholly blind — re-run with
  `--add-dir` before relaying anything.
- Confidence is not evidence the file was read. Apply the "ask it to quote
  something specific" rule to the file *under review*, not just the prompt.

## Also Applies To

- `agy -p "..."` — same quoting risks with `-p` flag
- `gh pr comment --body "..."` — use `--body-file -` with piped input instead
- Any script that passes LLM-generated text through shell string handling

## Evidence

- 2026-03-15 — file created (original case: claude review output containing single quotes broke heredoc parsing).
- 2026-05-19 — `/review-tests` Gemini calls in example-app #795 Slice 2. First attempt used `gemini -p "$(cat <<'PROMPT' ... $(cat /path) ... PROMPT)"`. The single-quoted `'PROMPT'` blocked substitution, so Gemini received literal `$(cat /path)` strings and either fabricated findings (breadth call invented test names that didn't exist) or hit workspace-scope errors and fell back to scanning reference files (depth call gave conclusions about a file it never read). Detection signal: the breadth call's "findings" cited test names like `"should handle Mercury API failure gracefully"` that did not exist in the actual file. Fix: switched to temp-file composition via a shell script that uses `cat >> "$PROMPT_FILE"` (which always expands `$()`). Second attempt's findings quoted actual test code, confirming the file was read.
- 2026-06-06 — `/second-opinion` on the IS-3 bridge contract (#842), built in worktree `../example-app-is3-bridge-contract/contract/` and run from the example-app main-repo cwd. Prompt composition was correct (temp file + `@file`), and the in-workspace `@files` (example-app/web, ios) were read fine — but the two `@`-referenced CONTRACT files were silently dropped as outside the workspace. Gemini reverse-engineered the contract from the deployed source it COULD read and returned confident `[BLOCKER]`s, most of them spurious (the real contract already handled them). Caught from the `Error executing tool read_file: Path not in workspace` lines at the top of the response — relayed them to USER as a caveat instead of passing the blockers through. Re-ran with `--include-directories <worktree>/contract`; Gemini then read the real file and found a genuine blocker (over-permissive `Date.parse` in an `isoDateTime` refine that would let non-`T`/`Z` strings pass while rendering `nil` in Swift). The worktree-first workflow makes this the default failure mode, not an edge case.

## See Also

- `~/Projects/dev-reference/patterns/cross-model-review-depth-breadth.md` — uses this pattern for Gemini reviews; documents Gemini-specific failure modes
