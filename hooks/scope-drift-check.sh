#!/bin/bash
set -e

# PreToolUse hook for Edit/Write: blocks edits to files outside the declared
# implementation scope. Prevents unplanned changes to shared infrastructure
# (auth.js, app.js, etc.) without writing tests first.
#
# How it works:
# - If tmp/scope.txt exists in the project, every Edit/Write must target
#   a file listed there (one path per line, relative to project root).
# - Files in tmp/, test*, e2e/, .claude/ are always allowed (tests/config).
# - If the file isn't in scope, the edit is blocked with a prompt to
#   write a test spec first.
#
# To use: create tmp/scope.txt from the brief's file list before implementation.
# Lines starting with # are comments. Blank lines are ignored.
#
# Evidence: 2026-04-01 #381 — unplanned auth.js async change broke 48 e2e tests.
# The change wasn't in the brief, had no test spec, and introduced a race condition.

hook_input=$(cat)

# Get the file path from the tool input
file_path=$(echo "$hook_input" | jq -r '.tool_input.file_path // ""')

if [ -z "$file_path" ]; then
  exit 0
fi

# Find the project root by looking for common markers
# Walk up from the file's directory
dir=$(dirname "$file_path")
project_root=""
while [ "$dir" != "/" ] && [ "$dir" != "." ]; do
  if [ -f "$dir/package.json" ] || [ -f "$dir/CLAUDE.md" ] || [ -d "$dir/.git" ]; then
    project_root="$dir"
    break
  fi
  dir=$(dirname "$dir")
done

if [ -z "$project_root" ]; then
  exit 0
fi

scope_file="$project_root/tmp/scope.txt"

# No scope file = no enforcement
if [ ! -f "$scope_file" ]; then
  exit 0
fi

# Make file_path relative to project root
rel_path="${file_path#$project_root/}"

# Always-allowed paths (tests, config, tmp, e2e, .claude, tracking docs)
if echo "$rel_path" | grep -qE '^(tmp/|test|e2e/|\.claude/|node_modules/)'; then
  exit 0
fi
# Always-allowed files (project tracking, not production code)
if echo "$rel_path" | grep -qE '^(next-steps\.md|ROADMAP\.md|CLAUDE\.md|CODEBASE-MAP\.md|\.gitignore)$'; then
  exit 0
fi

# Check if the file is in scope
# Strip comments and blank lines, then check for exact match or prefix match
in_scope=false
while IFS= read -r line; do
  # Skip comments and blanks
  line=$(echo "$line" | sed 's/#.*//' | xargs)
  [ -z "$line" ] && continue

  if [ "$rel_path" = "$line" ]; then
    in_scope=true
    break
  fi
done < "$scope_file"

if [ "$in_scope" = false ]; then
  jq -n --arg file "$rel_path" --arg scope "$scope_file" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("SCOPE DRIFT: " + $file + " is not in " + $scope + ". This file was not planned for modification. Before editing:\n1. Add a behavior spec/test for this change\n2. Add the file to tmp/scope.txt\n3. Then proceed with the edit\nDo NOT skip this gate — unplanned changes to shared code cause regressions.")
    }
  }'
  exit 0
fi
