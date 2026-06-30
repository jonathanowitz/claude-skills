#!/usr/bin/env bash
# Install these skills into your ~/.claude/ directory via symlinks.
#
# Symlinks (not copies) so `git pull` in this repo updates your local install.
# Existing files are backed up to ~/.claude/backup-<timestamp>/ before linking.

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
BACKUP="$CLAUDE/backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$CLAUDE/commands" "$CLAUDE/skills"

link_dir() {
  local src="$1" dst="$2"
  [[ ! -d "$src" ]] && return
  for f in "$src"/*; do
    local name
    name="$(basename "$f")"
    local target="$dst/$name"
    if [[ -e "$target" && ! -L "$target" ]]; then
      mkdir -p "$BACKUP/$(basename "$dst")"
      mv "$target" "$BACKUP/$(basename "$dst")/"
      echo "  backed up existing $target"
    elif [[ -L "$target" ]]; then
      rm "$target"
    fi
    ln -s "$f" "$target"
    echo "  linked $name"
  done
}

echo "→ Installing commands..."
link_dir "$REPO/commands" "$CLAUDE/commands"

echo "→ Installing skills..."
link_dir "$REPO/skills" "$CLAUDE/skills"

echo
echo "Done. Existing files (if any) were moved to: $BACKUP"
echo "Hooks and reference/ are NOT symlinked — they're examples to adapt."
echo "See README.md for how to adapt hooks/CLAUDE.md for your setup."
