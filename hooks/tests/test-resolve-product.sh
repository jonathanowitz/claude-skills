#!/bin/bash
# Fixture-harness tests for resolve-product.sh (example-app/#1201).
#
# Contract under test: resolve_product_field <field> prints the repo's declared
# value and returns 0, or prints nothing and returns 1. A miss (no
# .claude/product.json, absent key, malformed JSON, or a value that fails its
# field's shape) is NORMAL and returns 1 with empty stdout so the caller keeps
# its prior behavior. Values are shape-validated because they get interpolated
# into commands (supabase link, gh --repo, kill <port>).
#
# Every positive assertion is paired with a negative one so a resolver stuck at
# always-return-value (or always-miss) cannot pass by accident.
#
# Usage: bash test-resolve-product.sh   |   Exit 0 all pass, 1 any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$HOOKS_DIR/resolve-product.sh"

PASS_COUNT=0; FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL   %s\n     expected: [%s]\n     actual:   [%s]\n' "$1" "$2" "$3"; }

# Run resolve_product_field inside a fixture repo. Sets OUT (stdout) and RC.
run_in() { # <repo-dir> <field>
  OUT=$(cd "$1" && resolve_product_field "$2" 2>/dev/null); RC=$?
}

assert_val() { # <desc> <expected-stdout> <expected-rc>
  if [ "$OUT" = "$2" ] && [ "$RC" = "$3" ]; then pass "$1"; else fail "$1" "out=[$2] rc=$3" "out=[$OUT] rc=$RC"; fi
}

# --- fixtures --------------------------------------------------------------
i=0
while :; do
  ROOT="/tmp/resolve-product-test-$i"
  mkdir "$ROOT" 2>/dev/null && break
  i=$((i + 1)); [ "$i" -gt 500 ] && { echo "FATAL: no free test dir" >&2; exit 1; }
done
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

mk_repo() { # <name> -> echoes path; git-inits it
  local d="$ROOT/$1"; mkdir -p "$d/.claude"; ( cd "$d" && git init -q ); printf '%s' "$d"
}

# A fully-declared product repo (decidr — a DIFFERENT GitHub org than example-app,
# the case the whole issue exists for).
GOOD=$(mk_repo good)
cat > "$GOOD/.claude/product.json" <<'JSON'
{
  "gh_slug": "witzcraft/decidr",
  "issue_tracker": "witzcraft/decidr",
  "supabase_e2e_ref": "abcdefghijklmnopqrst",
  "supabase_prod_ref": "zyxwvutsrqponmlkjihg",
  "context_repo": "decidr-context",
  "stack": "vite-react",
  "dev_port": "5173",
  "shared_init": ["src/main.tsx", "index.html"]
}
JSON

# A repo whose values are the wrong SHAPE (short supabase ref, non-numeric port,
# slug with no owner) — present but must be rejected, not passed through.
BADSHAPE=$(mk_repo badshape)
cat > "$BADSHAPE/.claude/product.json" <<'JSON'
{ "supabase_e2e_ref": "TOO-SHORT", "dev_port": "notaport", "gh_slug": "ownerless" }
JSON

# A repo with an unsafe shared_init element (path traversal).
UNSAFE=$(mk_repo unsafe)
cat > "$UNSAFE/.claude/product.json" <<'JSON'
{ "shared_init": ["src/ok.tsx", "../../../etc/passwd"] }
JSON

# A repo with NO product.json — the common, correct miss.
NODECL=$(mk_repo nodecl)

# A repo with malformed JSON.
BADJSON=$(mk_repo badjson)
printf '{ this is not json' > "$BADJSON/.claude/product.json"

# A directory that is NOT a git repo at all.
NOTREPO="$ROOT/notrepo"; mkdir -p "$NOTREPO"

# --- assertions ------------------------------------------------------------

# scalar hit / unknown-field miss
run_in "$GOOD" gh_slug;            assert_val "gh_slug resolves (cross-org)"      "witzcraft/decidr" 0
run_in "$GOOD" banana;             assert_val "unknown field is a miss"           ""                 1

# supabase ref hit / bad-shape miss
run_in "$GOOD" supabase_e2e_ref;   assert_val "supabase_e2e_ref resolves"         "abcdefghijklmnopqrst" 0
run_in "$BADSHAPE" supabase_e2e_ref; assert_val "short supabase ref is rejected"  ""                 1

# port hit / bad-shape miss
run_in "$GOOD" dev_port;           assert_val "dev_port resolves"                 "5173"             0
run_in "$BADSHAPE" dev_port;       assert_val "non-numeric port is rejected"      ""                 1

# slug shape enforced
run_in "$BADSHAPE" gh_slug;        assert_val "ownerless slug is rejected"        ""                 1

# no declaration is a clean miss (paired against the GOOD hit above)
run_in "$NODECL" gh_slug;          assert_val "no product.json is a clean miss"   ""                 1

# malformed JSON is a miss, not a partial parse
run_in "$BADJSON" gh_slug;         assert_val "malformed JSON is a miss"          ""                 1

# not-a-repo is a miss (show-toplevel fails)
run_in "$NOTREPO" gh_slug;         assert_val "outside a git repo is a miss"      ""                 1

# array field emits one element per line / unsafe element rejects whole list
run_in "$GOOD" shared_init;        assert_val "shared_init emits its elements"    $'src/main.tsx\nindex.html' 0
run_in "$UNSAFE" shared_init;      assert_val "unsafe shared_init element rejects the list" ""       1

# env override wins, and is itself shape-validated
OUT=$(cd "$GOOD" && PRODUCT_GH_SLUG="growthxai/example-d" resolve_product_field gh_slug 2>/dev/null); RC=$?
assert_val "env override wins over product.json"   "growthxai/example-d" 0
OUT=$(cd "$GOOD" && PRODUCT_GH_SLUG="not-a-slug" resolve_product_field gh_slug 2>/dev/null); RC=$?
assert_val "env override failing its shape is a miss" "" 1

# --- summary ---------------------------------------------------------------
echo
echo "resolve-product: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]
