---
description: Convert content to Slack mrkdwn format and copy to clipboard
argument-hint: <file path, text, or "last" for most recent output>
---

# Slack-Copy

Convert the specified content to Slack-compatible mrkdwn and copy it to the macOS clipboard via `pbcopy`.

## Input

Determine the source content from `$ARGUMENTS`:

- **File path** (e.g., `briefs/feature-x.md`) — read the file
- **"last"** or empty — use the most recent substantial output from this conversation (last code block, summary, or generated text)
- **Inline text** — use the argument directly as the content to convert

## Conversion Rules

Apply these transformations:

| Standard Markdown | Slack mrkdwn |
|---|---|
| `**bold**` or `__bold__` | `*bold*` |
| `*italic*` or `_italic_` | `_italic_` |
| `## Heading` | `*Heading*` (bold, on its own line) |
| `### Subheading` | `*Subheading*` |
| `- bullet` or `* bullet` | ` ▸ bullet` |
| `  - nested` | `    ▸ nested` |
| `1. item` | `1. item` (keep as-is) |
| `[text](url)` | `<url\|text>` |
| `---` or `***` (horizontal rule) | `━━━━━━━━━━━━━━━━━━━` |
| `> blockquote` | `> blockquote` (keep as-is) |
| `` `inline code` `` | `` `inline code` `` (keep as-is) |
| ````code block```` | ````code block```` (keep as-is) |
| Markdown tables | Convert to plain text lists |

Additional rules:
- Remove any image references (`![alt](url)`)
- Remove HTML tags
- Remove YAML frontmatter (`---` blocks at top of file)
- Collapse triple+ blank lines to double
- Don't wrap lines — let Slack handle wrapping
- Preserve emoji shortcodes (`:rocket:`, etc.)

## Table Conversion

Convert markdown tables to labeled lists:

**Before:**
```
| Name | Status | Date |
|------|--------|------|
| Auth | Done | Mar 5 |
| Nav | In Progress | Mar 10 |
```

**After:**
```
 ▸ *Auth* — Done (Mar 5)
 ▸ *Nav* — In Progress (Mar 10)
```

## Output

1. Perform the conversion
2. Copy the result to clipboard:
   ```bash
   echo "<converted content>" | pbcopy
   ```
   Use a heredoc if the content contains quotes or special characters.
3. Print a short confirmation:

```
Copied to clipboard (Slack format) — <line count> lines
```

If the content is short (under 20 lines), also display the converted output so the user can preview it. Otherwise just confirm the copy.
