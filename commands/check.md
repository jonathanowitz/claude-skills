---
description: Check GitHub issues, recent commits, PRs, branches, and overall project health
allowed-tools: [Bash, Read, Glob, AskUserQuestion]
---

# Status

Get a comprehensive snapshot of the current project's GitHub state: issues, PRs, recent commits, branches, and staleness signals.

## Step 1: Identify the Repo

Run from the current working directory (or the primary code repo if in a docs-only repo):

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

- If this is a docs-only repo in the example-app issue-tracker orbit (`example-context`, `dev-reference`, `claude-config` — see `references/product-json.md`'s orbit rule) and has no issues of its own, target `USER/example-app` instead. Any other repo — including one with its own `.claude/product.json` `issue_tracker` declaration — uses its own remote/declared tracker.
- Store the repo identifier for all subsequent commands

## Step 2: Open Issues Summary

```bash
gh issue list --repo <repo> --state open --json number,title,labels,assignees,createdAt,updatedAt --limit 50
```

Group and display issues by type label (`bug`, `feature`, `task`, `enhancement`, `idea`). Within each group, sort by most recently updated.

For each issue show:
```
#NN: Title [labels] (updated N days ago)
```

Flag staleness:
- Issues with `in-progress` label but no update in 7+ days — mark as **STALE**
- Issues with `idea` label and no activity in 14+ days — mark as **AGING**

Show a count summary at the top:
```
Open issues: NN total (bugs: N, features: N, tasks: N, enhancements: N, ideas: N)
In-progress: N | Blocked: N | Stale: N
```

## Step 3: Pull Requests

```bash
gh pr list --repo <repo> --state open --json number,title,headRefName,createdAt,isDraft,reviewDecision --limit 20
```

For each open PR show:
```
#NN: Title (branch: <branch>) — draft/ready, N days old
```

Also check for recently merged PRs (last 7 days):
```bash
gh pr list --repo <repo> --state merged --json number,title,headRefName,mergedAt --limit 10
```

Show recent merges:
```
#NN: Title — merged N days ago
```

## Step 4: Recent Commits on Main

```bash
gh api repos/<repo>/commits --jq '.[0:10] | .[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0]) (\(.commit.author.date[0:10]))"'
```

Show the last 10 commits on the default branch with short SHA, first line of message, and date.

Flag any commits missing issue references (`#NN`) — these violate the commit convention.

## Step 5: Active Branches and Worktrees

```bash
git branch -a --sort=-committerdate --format='%(refname:short) %(committerdate:relative) %(upstream:trackshort)'
```

Show branches updated in the last 14 days. Flag branches that:
- Have no upstream tracking (local-only)
- Are ahead of main by more than 5 commits (potentially stale feature branch)

Also check for active worktrees:
```bash
git worktree list
```

Show any worktrees beyond the main one, with their branch names.

## Step 6: Open Briefs

List all non-archived briefs in the context repo:

```bash
ls -1 <context-repo>/briefs/*.md 2>/dev/null | grep -v archive
```

For the `example-context` repo, the path is the current working directory. Otherwise, check for a sibling `*-context` directory or skip this step.

For each brief:
1. Read the first 10 lines to extract the title and status
2. Cross-reference against open GitHub issues — check if any issue title matches the brief name
3. Check git log for last modification date: `git log -1 --format='%ai' -- <file>`

Display each brief as:
```
- Brief Name — last modified N days ago | linked issue: #NN or "no issue"
```

Flag briefs that:
- Have **no linked GitHub issue** — may be orphaned or pre-issue work
- Haven't been modified in **30+ days** — potentially stale
- Are linked to a **closed issue** — candidate for archiving

## Step 7: Deployment Check (Vercel)

Check if the most recent commit on main matches what's deployed:
```bash
gh api repos/<repo>/deployments --jq '.[0] | "\(.sha[0:7]) \(.environment) \(.created_at[0:10])"'
```

If the latest deployment SHA doesn't match the latest main commit SHA, flag as:
```
NOTICE: Latest main commit (abc1234) is not yet deployed. Last deployment: def5678 (YYYY-MM-DD)
```

If the API call fails (no deployments API access), skip silently.

## Step 8: Present the Report

Combine all sections into a single report:

```
# Project Status: <repo>
Generated: YYYY-MM-DD HH:MM

## Issues
[Step 2 output]

## Pull Requests
[Step 3 output — open and recently merged]

## Recent Commits (main)
[Step 4 output with convention violations flagged]

## Active Branches & Worktrees
[Step 5 output]

## Briefs
[Step 6 output]

## Deployment
[Step 7 output, or "Up to date" if matching]

## Alerts
[Aggregate all flags: stale issues, aging ideas, convention violations, undeployed commits, orphan branches, orphaned/stale briefs]
```

## Guidelines

- **Read-only** — This command never modifies anything. No issue updates, no git operations, no file writes.
- **Fail gracefully** — If `gh` auth fails or a specific API call errors, show what you can and note what failed.
- **Repo detection** — Apply the same rule as Step 1: orbit repos (`example-context`, `dev-reference`, `claude-config`) default to `USER/example-app` per the issue-tracker orbit rule; every other repo uses its own remote or declared `issue_tracker`.
- **Keep it scannable** — Use short lines, consistent formatting, and group by section. The point is a quick glance, not a deep dive.
- **No file output** — Display directly to the user. Don't save to a file unless explicitly asked.
