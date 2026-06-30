---
description: Scan a URL (article, GitHub repo, blog post) for useful dev workflow insights
argument-hint: <url>
allowed-tools: [WebFetch, WebSearch, Bash, Read, Write, Edit, Glob, Grep, Agent]
---

# Scan

Deep-scan the URL provided in `$ARGUMENTS` for actionable insights applicable to the dev-reference workflow system.

## Step 1: Fetch and Classify the Source

Fetch the URL with WebFetch:
- **Prompt:** "Extract the full content of this page. Include: title, author, date, all headings, all body text, and all hyperlinks (as markdown links). If this is a GitHub repo, include the README content and note the repo's purpose, star count, and last update."

Classify the source type:
- **Article/blog post** — technical writing, tutorials, opinion pieces
- **GitHub repo** — tool, library, framework, template, or reference
- **Documentation** — official docs for a tool or pattern
- **Discussion** — HN thread, Reddit post, forum thread
- **Other** — video transcript, podcast notes, etc.

## Step 2: Extract Key Links

From the fetched content, identify the 3-8 most promising linked resources — things like:
- Referenced tools, libraries, or GitHub repos
- Linked articles that go deeper on a technique
- Documentation pages for mentioned patterns

Fetch each promising link with WebFetch using the prompt: "Summarize this page in 2-3 sentences. What is it, what problem does it solve, and what's the key takeaway?"

Skip links that are clearly tangential (author bios, unrelated ads, social media profiles).

## Step 3: Analyze for Dev Workflow Relevance

For the primary source AND each fetched linked resource, evaluate against these categories:

### A. Workflow Improvements
Could this improve any existing workflow in `~/Projects/dev-reference/workflows/`?
- Session management, pre-implementation, pre-PR, post-merge
- Testing, validation, debugging protocols
- Planning and shaping processes

### B. New Patterns
Does this describe a reusable pattern worth capturing in `~/Projects/dev-reference/patterns/`?
- Code patterns, UI patterns, architecture patterns
- Shell/CLI patterns, prompt engineering patterns

### C. Tool or Convention Updates
Does this introduce a tool, library, or convention that could improve the stack?
- Claude Code / AI coding workflow enhancements
- Testing tools, debugging tools, CLI tools
- Conventions for code quality, naming, structure

### D. Methodology Insights
Does this challenge or reinforce the Shape Up / vertical slice approach?
- Planning methodology, scope management
- Agent delegation patterns, parallelism strategies

### E. Guide Material
Does this contain domain knowledge worth preserving in `~/Projects/dev-reference/guides/`?
- Model selection, prompt engineering, MCP usage
- Deployment, infrastructure, environment setup

## Step 4: Present Findings

Structure the output as:

```
# Scan: <title of primary source>
**Source:** <url>
**Type:** <classification>
**Date:** <publication date if available>

## TL;DR
[2-3 sentence summary of what this is and why it matters]

## Key Takeaways

### Directly Actionable
[Things that can be applied to the dev workflow NOW — specific files to update, patterns to adopt, tools to try. Each item should name the target file in dev-reference.]

 ▸ <Takeaway> → update `<dev-reference file path>`
 ▸ <Takeaway> → new file `<suggested path>`

### Worth Exploring
[Things that look promising but need more investigation or USER's input before acting]

 ▸ <Item> — <why it's interesting, what to investigate>

### Context / FYI
[Interesting background that informs thinking but doesn't require action]

 ▸ <Insight>

## Notable Linked Resources
[Only include links that added value beyond the primary source]

 ▸ **<Title>** (<url>) — <one-line summary of relevance>

## Recommendation
[One of: "Update now" / "Explore further" / "File for reference" / "Not relevant"]
[If "Update now" — name the specific files and describe the changes]
```

## Guidelines

- **Be specific about where insights land** — don't say "could improve testing." Say "add to `e2e-test-conventions.md` under Timing and Waits section."
- **Filter aggressively** — most articles have 1-2 genuinely useful takeaways, not 10. Quality over quantity.
- **Match the dev-reference voice** — actionable, evidence-backed, no fluff. If something is speculative, label it as "Worth Exploring" not "Directly Actionable."
- **Don't fetch more than 8 linked resources** — diminishing returns. Pick the most promising ones.
- **GitHub repos get extra scrutiny** — check star count, last commit date, and whether it solves a problem the workflow actually has. Don't recommend tools for hypothetical needs.
- **Flag conflicts** — if a recommendation contradicts an existing convention or workflow, call it out explicitly. The existing system was built from hard-won lessons.
- **Read-only by default** — present findings, don't modify files. If USER says "apply it," then make the edits.
