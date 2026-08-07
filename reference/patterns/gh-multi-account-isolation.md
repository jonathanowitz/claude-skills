# Running parallel sessions under two GitHub accounts

**Problem:** Two Claude Code sessions in different repos, one needing the `USER`
account and one needing `witzcraft`, fight over global state. Reaching for Docker is
over-engineering — nothing here needs a kernel, a filesystem, or a container.

There are **two independent singletons**, and fixing only one leaves you half-broken.

| Axis | The singleton | What contends |
|---|---|---|
| `gh` CLI | `Active account: true` in `~/.config/gh/hosts.yml` | `gh issue create`, `gh pr create`, `gh repo view` |
| `git push` | `credential.helper=osxkeychain`, inherited from Xcode's **system** gitconfig | `git push`, `git fetch` over HTTPS |

`gh auth switch` mutates the first globally — which is precisely the race. And it does
nothing at all about the second, because `git` never reads `hosts.yml`.

## Fix, axis 1 — a per-account `gh` config dir

Both accounts' tokens already live in the macOS keyring. Only the *index* (`hosts.yml`)
is contested, so give the second account its own index. Bootstrap it with `gh` itself —
the token moves keyring→keyring through a pipe and never touches disk:

```sh
gh auth token -u witzcraft | env GH_CONFIG_DIR=~/.config/gh-witzcraft \
  gh auth login --hostname github.com --with-token
```

Confirm it landed in the keyring, not a plaintext fallback file — `--with-token` will
silently fall back to plaintext if no credential store is found:

```sh
env GH_CONFIG_DIR=~/.config/gh-witzcraft gh auth status   # expect "(keyring)"
```

Then make it automatic per-project, in **`.claude/settings.local.json`** (gitignored —
the value is an absolute machine-specific path, and it must not ship in a public repo):

```json
{ "env": { "GH_CONFIG_DIR": "$HOME/.config/gh-witzcraft" } }
```

Add `.claude/settings.local.json` to `.gitignore`; the Write tool does not do it for you.
The env var loads at **session start** — it is not live in the session that created it.

## Fix, axis 2 — a per-repo git credential helper

Do *not* use `gh auth setup-git`: it installs a **global** helper and re-creates the
conflict. Do not reach for an SSH host alias either unless you also convert the remote
to SSH. Scope the helper to the one repo instead. The empty first value resets the
inherited `osxkeychain` chain; the second routes to the witzcraft config dir explicitly:

```sh
git -C <repo> config --local --add credential.helper ""
git -C <repo> config --local --add credential.helper \
  '!GH_CONFIG_DIR=$HOME/.config/gh-witzcraft gh auth git-credential'
```

Because the path is hardcoded in the repo's `.git/config`, this works in **any** shell —
a plain terminal, a hook, a subagent — not just a session where `GH_CONFIG_DIR` happens
to be exported. That is the reason to prefer it over relying on the env var alone.

## Verify — never assume, and never print the token

`git credential fill` emits `password=<token>` on stdout. Filter to `username=` so the
token stays out of the transcript:

```sh
printf 'protocol=https\nhost=github.com\n\n' | git -C <repo> credential fill 2>/dev/null | grep '^username='
```

Check all four cells, not just the one you changed — the failure mode is silently
converting *both* repos to one account:

```sh
env GH_CONFIG_DIR=~/.config/gh-witzcraft gh api user -q .login   # witzcraft
gh api user -q .login                                            # USER
```

## Commit identity is a third, separate thing

`user.name` / `user.email` come from `~/.gitconfig` and are untouched by any of the
above. Commits in a witzcraft repo are still authored as `USER`. If a repo
needs a different author, set `user.email` per-repo — deliberately, not as a side
effect of fixing push auth.

**Evidence:** 2026-07-08, decidr. Diagnosed as a Docker candidate; turned out to be one
YAML field plus one inherited helper. Both fixed and verified in under ten commands.
