#!/usr/bin/env bash
# TEMPLATE for scrub.sh (which is gitignored). Copy this to scrub.sh and fill in
# your own identifier mappings, then sync.sh will use it.
#
#   cp scrub.example.sh scrub.sh   # then edit scrub.sh with your real mappings
#
# The real scrub.sh is gitignored on purpose: its rules name the very personal /
# project identifiers you're scrubbing, so committing it would defeat the point.
# This template carries only placeholders.
#
# Usage: bash scrub.sh <repo-root>   (called by sync.sh)
#
# Order matters: more-specific rules must precede the broad catch-alls that would
# otherwise clobber them (e.g. a "Company, LLC" rule before a bare brand rule;
# an email rule before a bare-surname rule).
set -euo pipefail
REPO="${1:?usage: scrub.sh <repo-root>}"

# ---- Global pass: every managed .md/.sh/.json ----------------------------
find "$REPO/commands" "$REPO/skills" "$REPO/hooks" "$REPO/reference" \
  -type f \( -name '*.md' -o -name '*.sh' -o -name '*.json' \) -print0 \
  | while IFS= read -r -d '' f; do
    sed -i '' \
      `# --- paths & personal identifiers ---` \
      -e 's|/Users/YOUR_UNIX_USER|$HOME|g' \
      -e 's|YOUR_UNIX_USER|USER|g' \
      -e 's|Your Full Name|YOUR NAME|g' \
      -e 's|your-github-username|USER|g' \
      -e 's|you@example\.com|you@example.com|g' \
      `# --- private project / repo / company names ---` \
      -e 's|your-private-repo|example-repo|g' \
      -e 's|Your Company, LLC|Example Co.|g' \
      `# --- vendor account ids, infra refs, etc. ---` \
      -e 's|account_id: 000000|account_id: <ACCOUNT_ID>|g' \
      "$f"
  done

# ---- Per-file passes: project-specific example data ----------------------
# Add one block per file that contains domain examples (test fixtures, sample
# URLs, brand names) that a global rule shouldn't touch. Example:
#
# EXAMPLE_FILE="$REPO/commands/some-command.md"
# if [[ -f "$EXAMPLE_FILE" ]]; then
#   sed -i '' \
#     -e 's|your-real-example|a-generic-example|g' \
#     "$EXAMPLE_FILE"
# fi
