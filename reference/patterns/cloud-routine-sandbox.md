# Cloud Routine Sandbox — What's Actually Available

What a Claude Code **cloud routine** (scheduled agent) can and cannot do inside its container. Verified across two live firings, 2026-07-24 and 2026-07-25. These are environment facts, not preferences — a routine written against the wrong assumptions fails silently or, worse, reports confidently wrong findings.

## No `gh` binary

GitHub is reachable **only via the MCP connector**. The connector is model-callable and **never callable from a script**.

Consequence: any script a routine runs that needs GitHub state — issue lists, PR status, labels, project fields — must have that state **injected as an argument** by the model before the script runs. A routine that shells out to `gh` inside a bash script does not degrade gracefully; the binary is absent.

Design a routine as: model calls MCP → model passes the results into the script → script does the local work.

## `git clone` does not preserve mtime

Every file in a freshly cloned repo has the clone's timestamp, so **file mtime is useless as an age signal** inside a routine. Anything that reasons about "how stale is this doc" must use git:

```bash
git log -1 --format=%ct -- <path>    # last-commit unix timestamp for that path
```

## The checkout is a DETACHED HEAD that can be BEHIND origin/main

The container hands out a detached HEAD at whatever commit it was provisioned with. That commit is **not guaranteed to be `origin/main`** and in practice has been behind it.

A routine that scans the working tree without fetching first is scanning a stale snapshot — and because the scan *succeeds*, it reports its findings with full confidence. This is the highest-consequence fact on this page: it produces wrong answers, not errors.

**Always, as the first action of any scanning routine:**

```bash
git fetch origin
git checkout origin/main
```

## Permissions and scheduling

- **Zero permission prompts** across Bash / Write / MCP — the sandbox runs unattended by design. There is no human to approve anything mid-run, so a routine must never be written to depend on one.
- **Cron fires with the laptop asleep.** The routine runs in the cloud, not on the local machine, so schedule freely without worrying about machine state.

## Related

- `~/Projects/dev-reference/guides/autonomous-agents.md` — agent definitions, dispatch patterns, debrief convention
- `~/Projects/claude-config/references/hooks-and-agents-detail.md` — the model policy table for agent spawns
