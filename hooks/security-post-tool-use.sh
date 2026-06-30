#!/bin/bash
# PostToolUse hook: scan tool output for leaked secrets + maintain audit trail.
# Complements bash-audit-log.sh (which logs sanitized commands).
# This hook scans RESULTS for credentials that shouldn't be in output.
#
# Performance: caps output scan at 50KB. Audit logging is a single append.

set -e

LOG_DIR="$HOME/.claude/logs"
AUDIT_LOG="$LOG_DIR/tool-audit.log"
ALERT_LOG="$LOG_DIR/security-alerts.log"
mkdir -p "$LOG_DIR"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")

# --- Audit trail: log all tool completions ---
case "$TOOL_NAME" in
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
    echo "$TS | $TOOL_NAME | cmd=${CMD:0:200}" >> "$AUDIT_LOG"
    ;;
  Write|Edit)
    FPATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || echo "")
    echo "$TS | $TOOL_NAME | path=$FPATH" >> "$AUDIT_LOG"
    ;;
  Agent)
    DESC=$(echo "$INPUT" | jq -r '.tool_input.description // ""' 2>/dev/null || echo "")
    echo "$TS | AGENT_SPAWNED | desc=${DESC:0:200}" >> "$AUDIT_LOG"
    ;;
  WebFetch)
    URL=$(echo "$INPUT" | jq -r '.tool_input.url // ""' 2>/dev/null || echo "")
    echo "$TS | $TOOL_NAME | url=${URL:0:200}" >> "$AUDIT_LOG"
    ;;
  *)
    echo "$TS | $TOOL_NAME" >> "$AUDIT_LOG"
    ;;
esac

# --- Secret leak detection in tool output ---
# Only scan Bash and Read results (highest risk of exposing secrets)
if [[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "Read" ]]; then
  exit 0
fi

# Extract result, cap at 50KB to avoid lag on large file reads
RESULT=$(echo "$INPUT" | jq -r '.tool_result // ""' 2>/dev/null | head -c 51200 || echo "")
[[ -z "$RESULT" ]] && exit 0

# Check for secret patterns in output
SECRET_TYPE=""

check() {
  local pattern="$1" label="$2"
  if echo "$RESULT" | grep -qE "$pattern" 2>/dev/null; then
    SECRET_TYPE="$label"
    return 0
  fi
  return 1
}

# AWS keys
check 'AKIA[0-9A-Z]{16}' "AWS Access Key ID" ||
# Anthropic API key
check 'sk-ant-[a-zA-Z0-9_-]{90,}' "Anthropic API Key" ||
# OpenAI API key
check 'sk-[a-zA-Z0-9]{48,}' "OpenAI API Key" ||
# GitHub tokens
check 'gh[ps]_[a-zA-Z0-9]{36,}' "GitHub Token" ||
# Slack tokens
check 'xox[baprs]-[0-9a-zA-Z-]{10,}' "Slack Token" ||
# Stripe secret keys
check 'sk_(live|test)_[A-Za-z0-9]{10,}' "Stripe Secret Key" ||
# Supabase service role key (eyJ prefix + long)
check 'eyJhbGciOi[A-Za-z0-9_=-]{100,}' "Long JWT (possible service role key)" ||
# Private keys
check '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' "Private Key" ||
# Passwords in config (key = "value" patterns)
check 'password[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']{8,}' "Password in config" ||
true

if [[ -n "$SECRET_TYPE" ]]; then
  ALERT="$TS | SECRET_IN_OUTPUT | type=$SECRET_TYPE | tool=$TOOL_NAME"
  echo "$ALERT" >> "$ALERT_LOG"
  echo "$ALERT" >> "$AUDIT_LOG"
  # Warn Claude — informational only (tool already ran)
  echo "WARNING: Possible $SECRET_TYPE detected in tool output. Review for accidental credential exposure before proceeding."
fi

exit 0
