#!/usr/bin/env bash
# PreToolUse(Bash) gate for `supabase db push`: ALLOW only when the target worktree
# is linked to the e2e branch (<E2E_PROJECT_REF>). Any other linked ref — prod
# (<PROD_PROJECT_REF>), unknown, or unreadable — is DENIED.
#
# Why a hook and not a permission rule: the e2e-vs-prod target lives in the link
# config (supabase/.temp/project-ref), NOT the command string — `supabase db push
# --workdir <path>` is byte-identical for e2e and prod. So we read the actual linked
# ref at call time and decide. Wired ONLY in the example-app project settings.local.json
# (so it never fires in other repos). Prod still ships via the merge auto-apply Action.
# (#941 follow-up — second time the e2e push was blocked by the auto-mode classifier.)

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"

# Resolve the repo's own declared e2e ref instead of assuming example-app's. A
# repo that doesn't declare supabase_e2e_ref gets no gate — let the command
# pass rather than block a repo that never opted into this protection
# (example-app/#1201).
RESOLVER="$(dirname "${BASH_SOURCE[0]}")/resolve-product.sh"
[ -f "$RESOLVER" ] && . "$RESOLVER"
E2E_REF=""
if command -v resolve_product_field >/dev/null 2>&1; then
  E2E_REF="$(cd "${cwd:-.}" 2>/dev/null && resolve_product_field supabase_e2e_ref 2>/dev/null)" || E2E_REF=""
fi
[ -n "$E2E_REF" ] || exit 0

# Self-guard. This hook is wired via the matcher `Bash(supabase db push:*)`, but the
# harness routes compound/unparseable commands (for-loops, `;`/`&&` chains) to ALL
# matchers, so a read-only command can reach here and then be DENIED by the
# prod-linked-ref check below. Only act on commands that actually run `supabase db push`.
# (2026-07-06 maintenance: this gate denied a read-only `for` loop over checkpoint files.)
case "$cmd" in
  *"supabase db push"*) : ;;
  *) exit 0 ;;
esac

# Resolve the workdir: `--workdir <path>` if present, else the session cwd (the main
# checkout, which is linked to prod — so a bare `db push` there correctly denies).
workdir="$(printf '%s' "$cmd" | sed -nE 's/.*--workdir[[:space:]]+([^[:space:]]+).*/\1/p')"
[ -z "$workdir" ] && workdir="$PWD"

ref_file="$workdir/supabase/.temp/project-ref"

emit() { # $1=decision  $2=reason
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
}

if [ ! -f "$ref_file" ]; then
  emit deny "e2e-only push gate: no linked project-ref at $ref_file — refusing. Link the worktree to e2e (supabase link --project-ref $E2E_REF --workdir <WT>) first."
  exit 0
fi

ref="$(tr -d '[:space:]' < "$ref_file" 2>/dev/null)"
if [ "$ref" = "$E2E_REF" ]; then
  emit allow "e2e-only push gate: worktree linked to e2e ($E2E_REF)."
else
  emit deny "e2e-only push gate: worktree linked to '$ref', not e2e ($E2E_REF). Prod/other db push is blocked here — prod auto-applies on merge."
fi
exit 0
