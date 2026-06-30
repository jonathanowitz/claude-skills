#!/bin/bash
# PreToolUse hook: block dangerous command patterns that bypass the deny list.
# Complements secret-scan.sh (which catches hardcoded secrets) and the
# settings.json deny list (which catches simple glob patterns like "curl *|sh*").
# This hook uses regex to catch obfuscated/variant injection patterns.
#
# Exit conventions: exit 0 = allow, structured JSON with deny = block.

set -e

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")

# Only inspect Bash commands and WebFetch URLs
[[ "$TOOL_NAME" != "Bash" && "$TOOL_NAME" != "WebFetch" ]] && exit 0

block() {
  local reason="$1"
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("BLOCKED (security): " + $reason)
    }
  }'
  exit 0
}

# --- Bash command checks ---
if [[ "$TOOL_NAME" == "Bash" ]]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
  [[ -z "$CMD" ]] && exit 0

  # Base64 decode piped to shell or another command (obfuscated injection)
  if echo "$CMD" | grep -qE 'base64[[:space:]]+(--decode|-d)[^|]*\|'; then
    block "Base64-decode pipe pattern detected — possible obfuscated command injection"
  fi

  # Environment variable exfiltration via network tools
  if echo "$CMD" | grep -qE '(env|printenv|set|echo[[:space:]]+\$)[^;|]*\|[^;]*(curl|wget|nc|ncat)'; then
    block "Environment variable exfiltration pattern detected (piping env to network tool)"
  fi

  # Specific credential env vars referenced alongside network commands
  if echo "$CMD" | grep -qiE '(ANTHROPIC_API_KEY|AWS_SECRET_ACCESS_KEY|SUPABASE_SERVICE_ROLE_KEY|VERCEL_TOKEN|STRIPE_SECRET_KEY)[^;]*\|?[[:space:]]*(curl|wget|nc)'; then
    block "Credential exfiltration attempt — known secret env var referenced in network command"
  fi

  # Python/perl/ruby one-liner executing downloaded content
  if echo "$CMD" | grep -qE '(python3?|perl|ruby)[[:space:]]+-[ce][[:space:]]+.*\b(curl|wget)\b'; then
    block "Script interpreter executing downloaded content"
  fi

  # Netcat / socat reverse shell patterns
  if echo "$CMD" | grep -qE '(nc|ncat|netcat|socat)[[:space:]].*(-e[[:space:]]+|exec=)(ba)?sh'; then
    block "Reverse shell pattern detected (nc/socat with shell exec)"
  fi

  # eval with command substitution (common injection vector)
  if echo "$CMD" | grep -qE '\beval[[:space:]]+\$\(|\beval[[:space:]]+`'; then
    block "eval with command substitution — potential injection vector"
  fi

  # chmod world-writable
  if echo "$CMD" | grep -qE 'chmod[[:space:]]+([0-9]*7[0-9]*)[[:space:]]|chmod[[:space:]]+-R[[:space:]]+[0-9]*7'; then
    block "chmod world-writable permissions detected"
  fi

  # Writes to system directories via Bash redirection
  if echo "$CMD" | grep -qE '>>?[[:space:]]*/etc/|>>?[[:space:]]*/bin/|>>?[[:space:]]*/usr/'; then
    block "Attempt to write to system directory (/etc, /bin, /usr)"
  fi

  # Git credential extraction
  if echo "$CMD" | grep -qE 'git[[:space:]]+credential[[:space:]]+(fill|get)'; then
    block "Git credential extraction command detected"
  fi

  # SSH key piped to network tool
  if echo "$CMD" | grep -qE '(cat|head|tail)[[:space:]]+~?/.ssh/[^;|]*(&&|\||;)[[:space:]]*(curl|wget|nc)'; then
    block "SSH key exfiltration pattern detected"
  fi

  # npx -y with remote URL (unreviewed package execution)
  if echo "$CMD" | grep -qE 'npx[[:space:]]+-y' && echo "$CMD" | grep -qE 'https?://'; then
    block "npx -y with remote URL — unreviewed package execution"
  fi

  # Zero-width Unicode character obfuscation (if perl available)
  if command -v perl &>/dev/null; then
    if echo "$CMD" | perl -ne 'exit 1 if /[\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{FEFF}]/' 2>/dev/null; then
      : # no match, fine
    else
      block "Zero-width Unicode characters detected in command (obfuscation attempt)"
    fi
  fi
fi

# --- WebFetch checks ---
if [[ "$TOOL_NAME" == "WebFetch" ]]; then
  URL=$(echo "$INPUT" | jq -r '.tool_input.url // ""' 2>/dev/null || echo "")

  if echo "$URL" | grep -qiE '^data:'; then
    block "data: URI blocked in WebFetch — can contain embedded executable content"
  fi

  if echo "$URL" | grep -qiE '^file://'; then
    block "file:// URI blocked in WebFetch — use Read tool for local files"
  fi
fi

exit 0
