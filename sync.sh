#!/usr/bin/env bash
# Rebuild the public claude-skills tree from private sources.
#
# Sources (source of truth — edit there, not here):
#   ~/Projects/claude-config/{commands,skills,hooks}
#   ~/Projects/dev-reference/{workflows,conventions,templates,methodology,patterns,guides}
#
# Flow:
#   1. Wipe the managed subtrees in this repo
#   2. Copy fresh from sources
#   3. Apply .syncignore exclusions
#   4. Run scrub sed passes to strip personal/project identifiers
#   5. Prepend auto-generated banner to every .md/.sh file
#   6. Leave the result staged — you review `git diff` and commit manually

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$HOME/Projects/claude-config"
REF="$HOME/Projects/dev-reference"

if [[ ! -d "$CONFIG" || ! -d "$REF" ]]; then
  echo "ERROR: expected ~/Projects/claude-config and ~/Projects/dev-reference to exist" >&2
  exit 1
fi

echo "→ Wiping managed subtrees..."
rm -rf "$REPO/commands" "$REPO/skills" "$REPO/hooks" "$REPO/reference"

echo "→ Copying from claude-config..."
cp -R "$CONFIG/commands" "$REPO/commands"
cp -R "$CONFIG/skills"   "$REPO/skills"
cp -R "$CONFIG/hooks"    "$REPO/hooks"

echo "→ Copying from dev-reference..."
mkdir -p "$REPO/reference"
for d in workflows conventions templates methodology patterns guides voice prompts tests tmp; do
  [[ -d "$REF/$d" ]] && cp -R "$REF/$d" "$REPO/reference/$d"
done

echo "→ Applying .syncignore..."
if [[ -f "$REPO/.syncignore" ]]; then
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
    clean="${pattern%'/**'}"
    if [[ "$clean" != "$pattern" ]]; then
      [[ -e "$REPO/$clean" ]] && rm -rf "$REPO/$clean"
    else
      [[ -e "$REPO/$pattern" ]] && rm -f "$REPO/$pattern"
    fi
  done < "$REPO/.syncignore"
fi

echo "→ Scrubbing personal identifiers..."
# Scrub rules live in scrub.sh (gitignored) so the public repo never carries a
# plaintext catalog of the personal/project identifiers being scrubbed. See
# scrub.example.sh for the template; copy it to scrub.sh and fill in your real
# mappings.
SCRUB="$REPO/scrub.sh"
if [[ ! -f "$SCRUB" ]]; then
  echo "ERROR: $SCRUB not found. Copy scrub.example.sh to scrub.sh and add your" >&2
  echo "       identifier mappings before running sync." >&2
  exit 1
fi
bash "$SCRUB" "$REPO"

echo "→ Done. Review with: git -C $REPO status && git -C $REPO diff"
