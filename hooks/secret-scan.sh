#!/bin/bash
set -e

# PreToolUse hook: block Bash commands that contain hardcoded secrets.
# Scans for known secret key prefixes/patterns from all project .env files.

hook_input=$(cat)
command=$(echo "$hook_input" | jq -r '.tool_input.command // ""')

# Known secret prefixes and patterns:
#   sb_secret_        Supabase service role keys
#   sb_publishable_   Supabase anon keys (still shouldn't be hardcoded)
#   eyJhbGciOi        Base64 JWT tokens (Vercel OIDC, etc.)
#   sk_live_          Stripe live secret keys
#   sk_test_          Stripe test secret keys
#   xkeysib-          Brevo/Sendinblue API keys
#   SG.               SendGrid API keys
#   ghp_              GitHub personal access tokens
#   gho_              GitHub OAuth tokens
#   github_pat_       GitHub fine-grained PATs
#
# Also catches:
#   64-char hex strings (ADMIN_SECRET format)
#   32-char hex strings (LOOPS_API_KEY format)

# Pattern 1: Known service key prefixes + credential-bearing patterns
#   PGPASSWORD=         Postgres password inline in command
#   postgresql://...:.. Connection strings with embedded passwords
prefix_pattern='sb_secret_[A-Za-z0-9_-]{10,}|sb_publishable_[A-Za-z0-9_-]{10,}|eyJhbGciOi[A-Za-z0-9_=-]{20,}|sk_live_[A-Za-z0-9]{10,}|sk_test_[A-Za-z0-9]{10,}|xkeysib-[A-Za-z0-9]{10,}|SG\.[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|PGPASSWORD=[^ ]{4,}|postgresql://[^:]+:[^@]{4,}@'

# Pattern 2: Bare 64-char hex strings (likely ADMIN_SECRET)
hex64_pattern='"[0-9a-f]{64}"'

# Pattern 3: Bare 32-char hex strings (likely API keys)
hex32_pattern='"[0-9a-f]{32}"'

# Exclude safe patterns: reading .env, grep/cat of .env, env var references
# These are legitimate uses that don't expose the actual value
safe_pattern='(\$\{?[A-Z_]+\}?|process\.env\.|grep.*\.env|cat.*\.env|head.*\.env|export.*\.env|source.*\.env|\.env\.example)'

# Skip if the command is just reading/exporting .env (not hardcoding)
if echo "$command" | grep -qE "$safe_pattern" && ! echo "$command" | grep -qE "$prefix_pattern"; then
  exit 0
fi

# Check for hardcoded secrets
if echo "$command" | grep -qE "$prefix_pattern"; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "BLOCKED: Hardcoded secret detected in command. NEVER put API keys, tokens, passwords, or connection strings directly in commands. Use: export $(grep -v '"'"'^#'"'"' .env | xargs) to load env vars, or use CLI tools that handle auth internally (e.g. supabase link + db push)."
    }
  }'
  exit 0
fi

if echo "$command" | grep -qE "$hex64_pattern"; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "ask",
      "permissionDecisionReason": "SUSPICIOUS: Command contains a 64-character hex string that may be a hardcoded secret (ADMIN_SECRET format). Verify this is not a credential before allowing."
    }
  }'
  exit 0
fi

if echo "$command" | grep -qE "$hex32_pattern"; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "ask",
      "permissionDecisionReason": "SUSPICIOUS: Command contains a 32-character hex string that may be a hardcoded API key. Verify this is not a credential before allowing."
    }
  }'
  exit 0
fi
