---
description: Create a GitHub Issue for the current project (bug, task, idea, enhancement, etc.)
argument-hint: <label>: <title and description>
---

# Create GitHub Issue

Create a GitHub Issue from the user's input: $ARGUMENTS

## Determine the Repo

1. Try to detect the repo from the current working directory: `gh repo view --json nameWithOwner -q .nameWithOwner`
2. If that fails (not a git repo, no remote), check if the user is working in a known project directory and use the mapped repo:
   - `example-app` or `example-context` directories -> `USER/example-app`
3. If still unclear, ask the user which repo to use

## Parse the Input

The argument format is flexible. Parse it to extract:

- **Label** — Look for a label prefix like `bug:`, `task:`, `idea:`, `enhancement:`, `planning:`, `deferred:`
  - If no prefix, ask the user to pick a label
  - Map common synonyms: `feature` -> `enhancement`, `debt` -> `task`
- **Title** — The first sentence or phrase after the label
- **Description** — Any additional detail after the title. If the user gave a long description, use the first sentence as the title and the rest as the body.

**Available labels:** `bug`, `enhancement`, `idea`, `task`, `planning`, `deferred`, `documentation`, `question`

## Examples

These should all work:

- `/issue bug: Search bar cursor gets covered by autofill dropdown`
- `/issue task: Run Acmes SQL fix - merge duplicate Springfield entries in gyms table`
- `/issue idea: Calendar export for Google Calendar and Apple Calendar`
- `/issue The notifications inbox looks terrible` (no label -> ask)
- `/issue enhancement: Add loading animations for page transitions. Currently the app feels sluggish when switching between views because there's no visual feedback.`

## Create the Issue

1. Run: `gh issue create --repo <owner/repo> --title "<title>" --label "<label>" --body "<description>"`
2. If the body is empty (user only gave a title), omit the `--body` flag
3. Capture the returned issue URL

## Output

Show a brief confirmation:

```
Created #<number>: <title> [<label>]
<issue URL>
```

Do not add extra commentary. Keep it quick — this command should feel like firing off a quick note.
