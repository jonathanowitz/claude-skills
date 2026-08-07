#!/bin/bash
# Resolve a per-repo product fact (GitHub slug, Supabase refs, dev port, …) for
# the repo a command is operating on, instead of assuming it is example-app.
# Sourced by the hooks in this directory (bash-post-hook, supabase-ops-protocol,
# wip-*, example-now, …) and, cross-repo, by dev-reference review scripts.
#
# WHY THIS EXISTS (example-app/#1201):
# The automation was written when example-app was the only product. Roughly 56
# sites hardcoded it as the operating target — paths, the `USER/
# example-app` slug, Supabase project-refs, the dev port. When the same hook or
# script ran while the working repo was example-b, decidr, example-c (a DIFFERENT
# GitHub org), or example-d, it operated against example-app anyway, silently:
# linking foreign worktrees to example-app's e2e database, killing example-app's
# dev port on every worktree-add, injecting example-app's project-refs into an
# unrelated `supabase` command, filing issues to the wrong org.
#
# THE IDIOM (matches resolve-behavior-map.sh / resolve-diff-base.sh):
# env override -> a committed per-repo declaration at the repo root -> graceful
# miss. The declaration is `.claude/product.json` in the repo under operation;
# `git rev-parse --show-toplevel` finds it, which is worktree-correct (a linked
# worktree has its own checked-out copy). A repo that declares nothing gets a
# clean miss, and the caller keeps its prior behavior — a miss is NORMAL, not
# degraded, exactly as most repos have no behavior map.
#
# WHY VALUES ARE SHAPE-VALIDATED:
# Unlike a behavior map (which is read and shown), these values are INTERPOLATED
# INTO COMMANDS: `supabase link --project-ref "$ref"`, `gh ... --repo "$slug"`,
# `kill` against "$port". `.claude/product.json` is committed repo content, so it
# is user-controlled and trusted for INTENT — but a typo or a CRLF checkout that
# smuggled a newline into a ref would otherwise reach a command. So each field is
# validated against the shape it must have; a value that fails validation is a
# miss with a word on stderr, never a passed-through string that detonates later
# in a hook running unattended. This is the resolve-diff-base.sh lesson: never
# hand back a value that only fails downstream.
#
# CONTRACT: resolve_product_field <field>
#   Prints the value on stdout and returns 0, OR prints NOTHING and returns 1.
#   A return of 1 is NORMAL and means "this repo does not declare that field" —
#   callers MUST fall back to their prior behavior, never abort on it. Array
#   fields (shared_init) print one element per line. Diagnostics go to stderr
#   and are informational.
#
# Because a miss returns non-zero, a DIRECT call under `set -e` kills the caller.
# Call it in an `if`, capture with `$( ... ) || true`, or test the return.

# Field -> validation regex (BRE-free; used with bash [[ =~ ]]). A field absent
# from this table is rejected outright, so a caller cannot fish out an arbitrary
# JSON key. shared_init is validated per-element below, not here.
_product_field_pattern() {
  case "$1" in
    gh_slug|issue_tracker) printf '%s' '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ;;
    supabase_e2e_ref|supabase_prod_ref) printf '%s' '^[a-z]{20}$' ;;
    dev_port) printf '%s' '^[0-9]{1,5}$' ;;
    context_repo) printf '%s' '^[A-Za-z0-9_.-]+$' ;;
    stack) printf '%s' '^[a-z][a-z0-9-]*$' ;;
    shared_init) printf '%s' 'ARRAY' ;;
    *) return 1 ;;
  esac
}

# Resolve a product field. Usage: resolve_product_field <field>
resolve_product_field() {
  local field="${1:-}" pattern envvar envval root file raw
  [ -n "$field" ] || { echo "resolve_product_field: no field named." >&2; return 1; }

  # A field must be one this resolver knows how to validate. An unknown field is
  # a programming error, not a miss — say so, so a typo'd call is caught rather
  # than silently returning "this repo doesn't declare xyz".
  pattern=$(_product_field_pattern "$field") || {
    echo "resolve_product_field: unknown field '$field'." >&2
    return 1
  }

  # 1. An explicit PRODUCT_<FIELD> env override wins, for ad-hoc runs and tests.
  #    VERIFIED, not trusted: an override that fails the field's shape means the
  #    caller meant to supply a value and fat-fingered it — worth a word, still
  #    a miss so nothing malformed reaches a command.
  envvar="PRODUCT_$(printf '%s' "$field" | tr '[:lower:]' '[:upper:]')"
  envval="${!envvar:-}"
  if [ -n "$envval" ]; then
    if [ "$pattern" = "ARRAY" ]; then
      # An array override is newline-separated; validate + emit each element.
      _emit_shared_init_lines "$envval" "$envvar" && return 0
      return 1
    fi
    if [[ "$envval" =~ $pattern ]]; then
      printf '%s\n' "$envval"
      return 0
    fi
    echo "resolve_product_field: $envvar='$envval' fails the shape for '$field' — ignoring it." >&2
    return 1
  fi

  # 2. The repo under operation declares its own facts. --show-toplevel is
  #    worktree-correct: a linked worktree returns its OWN root, where its
  #    committed .claude/product.json is checked out like any other file.
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$root" ] || return 1
  file="$root/.claude/product.json"
  [ -f "$file" ] || return 1

  command -v jq >/dev/null 2>&1 || {
    echo "resolve_product_field: jq not found — cannot read $file." >&2
    return 1
  }

  # jq validates the JSON itself; a malformed product.json is a miss with a word,
  # never a partial parse. `// empty` distinguishes "key absent/null" (clean
  # miss, no message) from a present-but-wrong-shape value (message below).
  if [ "$pattern" = "ARRAY" ]; then
    raw=$(jq -r --arg f "$field" '(.[$f] // empty) | if type=="array" then .[] else . end' "$file" 2>/dev/null) || {
      echo "resolve_product_field: $file is not valid JSON." >&2
      return 1
    }
    [ -n "$raw" ] || return 1
    _emit_shared_init_lines "$raw" "$file" && return 0
    return 1
  fi

  raw=$(jq -r --arg f "$field" '.[$f] // empty' "$file" 2>/dev/null) || {
    echo "resolve_product_field: $file is not valid JSON." >&2
    return 1
  }
  [ -n "$raw" ] || return 1

  if [[ "$raw" =~ $pattern ]]; then
    printf '%s\n' "$raw"
    return 0
  fi
  echo "resolve_product_field: $file declares $field='$raw', which fails its expected shape — ignoring it." >&2
  return 1
}

# shared_init elements are repo-relative paths that get `git add`ed / diffed, so
# the guard is: non-empty, no absolute paths, no `..` traversal, no shell
# metacharacters. A single bad element rejects the whole list — a partial
# shared-init set is a silently-wrong protection surface, the same failure class
# this file exists to prevent.
_emit_shared_init_lines() {
  local blob="$1" origin="$2" line out=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      /*|*..*|*'$'*|*'`'*|*';'*|*'&'*|*'|'*)
        echo "resolve_product_field: shared_init in $origin has an unsafe element '$line' — ignoring the whole list." >&2
        return 1 ;;
    esac
    out+="$line"$'\n'
  done <<EOF
$blob
EOF
  [ -n "$out" ] || return 1
  printf '%s' "$out"
  return 0
}
