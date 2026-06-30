#!/bin/bash
# PostToolUse hook: log bash commands with timestamp to ~/.claude/bash-commands.log
# Sanitizes tokens/secrets before writing to avoid credential leakage.

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // ""')

# Sanitize known secret patterns before logging
sanitized=$(echo "$command" | sed -E \
  -e 's/(sb_secret_|sb_publishable_|sk_live_|sk_test_|xkeysib-|ghp_|gho_|github_pat_)[A-Za-z0-9_=-]+/\1[REDACTED]/g' \
  -e 's/eyJhbGciOi[A-Za-z0-9_=+/-]{20,}/[REDACTED_JWT]/g' \
  -e 's/SG\.[A-Za-z0-9_-]{20,}/SG.[REDACTED]/g' \
  -e 's/(Bearer |Authorization: )[^ "'"'"']*/\1[REDACTED]/g' \
  -e 's/([Tt]oken[= :][ ]?)[A-Za-z0-9_-]{20,}/\1[REDACTED]/g' \
  -e 's/([Kk]ey[= :][ ]?)[A-Za-z0-9_-]{20,}/\1[REDACTED]/g' \
  -e 's/"[0-9a-f]{64}"/[REDACTED_HEX64]/g' \
  -e 's/"[0-9a-f]{32}"/[REDACTED_HEX32]/g' \
)

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $sanitized" >> ~/.claude/bash-commands.log
