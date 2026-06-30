# Git fsck Recovery — finding lost work in unreachable blobs

## When to use

A file or set of changes seems to have vanished — stashed and popped with a conflict, branch abandoned, worktree deleted, commit amended away, `git reset --hard` ran. The commits and blobs are no longer reachable from any ref, but git keeps unreachable objects for 90 days before GC. If the work is less than 90 days old, it is almost certainly still in `.git/objects/`.

**Signals:**
- "I'm sure I wrote this, I can't find it anywhere."
- USER: "It got swept out of a tmp file in a worktree or something."
- A session capture references a file that no longer exists at the path.
- A stash pop conflict was resolved and the other side was lost.

## Recovery procedure

```bash
# 1. List every unreachable object
git -C <repo> fsck --unreachable --no-reflogs

# Output is many lines of:
#   unreachable commit <sha>
#   unreachable blob <sha>
#   unreachable tree <sha>
```

```bash
# 2. For each candidate, inspect the content
git -C <repo> cat-file -p <sha>

# Blobs are raw file content
# Commits show the commit message + parent + tree
# Trees show the directory listing
```

```bash
# 3. Scan blob contents for markers unique to the lost work
# If you know the title, a heading, a function name, or a distinctive
# phrase — scan every unreachable blob for it
for sha in $(git -C <repo> fsck --unreachable --no-reflogs 2>/dev/null \
  | grep 'unreachable blob' | awk '{print $3}'); do
  if git -C <repo> cat-file -p "$sha" 2>/dev/null | grep -l "<unique-marker>" > /dev/null; then
    echo "MATCH: $sha"
    git -C <repo> cat-file -p "$sha" | head -20
  fi
done
```

```bash
# 4. Recover the content
git -C <repo> cat-file -p <sha> > <path>/<filename>

# Or restore via git cat-file into a known location, then git add + commit
```

## Reading the evidence

Unreachable objects often come in pairs:

- **A clean blob** containing the lost work
- **A conflict-marker blob** containing the work with `<<<<<<<`/`=======`/`>>>>>>>` markers

If both are present, the conflict blob tells you HOW the work was lost (stash pop + conflict resolved against the older side). The clean blob is what you want to restore.

## After recovery

Commit immediately — unreachable objects still get GC'd after 90 days. Track the recovery in a commit message:

```
Recover <filename> from unreachable blob <sha>

Lost during <approximate event> on <date>. Scanned unreachable blobs
for <unique marker>, found <sha>. Conflict-marker blob <sha2> confirms
the loss mechanism was a stash pop conflict resolved against the older side.
```

## When this does NOT work

- More than 90 days since loss → run `git gc` history and hope a pack file still has it. Check `.git/packed-refs` and `.git/packed-objects/`.
- The content was never committed AND never stashed AND never landed in a branch — git had no reason to create an object for it. Editor history / time machine / OS file recovery is the only path.
- `git gc --aggressive --prune=now` was run after the loss. The objects are gone.

## Evidence

**2026-04-09:** Plus/Pro tier model work from the 2026-04-01 session vanished from `feature-tiers.md`. `git log` showed only the old content; reflog was empty. `git fsck --unreachable` listed ~40 dangling blobs. Scanned for "Plus" + "Pro" + "Family" markers → found `eca9de2` (feature-tiers.md) and `21889963` (business-overview.md). A third blob `c0cab768` contained `<<<<<<<` markers — confirmed stash-pop conflict resolved against the 2026-02-22 version. Both clean blobs restored and committed as `4890018`. Total time from "I think I lost it" to "it's back in main" was under 10 minutes.

## See also

- `git reflog` — first place to check for recent ref moves. If the commit sha is in the reflog, `git checkout <sha>` is simpler than fsck.
- `git stash list` — if the work was stashed but never popped, it's still there.
- `patterns/git-ignore-levels.md` — preventing the loss in the first place: ignore levels, the already-tracked gotcha, and triaging untracked files before a `--force` worktree removal eats them.
