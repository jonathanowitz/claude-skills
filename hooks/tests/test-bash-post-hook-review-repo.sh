#!/bin/bash
# Fixture-harness tests for bash-post-hook.sh's PR-review REPO resolution (#1198 defect 1).
#
# THE BUG THIS PINS: on `gh pr create`, the hook parsed the PR NUMBER out of the
# created-PR URL but threw away the owner/repo that came with it, then resolved the
# review worktree against EFFECTIVE_CWD (the session cwd). So a cross-repo
# `gh pr create --repo other/repo` opened from an unrelated session cwd:
#   1. `gh pr view <n>` ran against the SESSION repo → no such PR → empty head branch
#   2. REVIEW_CWD stayed the session checkout
#   3. both review scripts diffed a checkout whose HEAD == its base → "No diff found"
#   4. the PR got NO review, and nothing reported a failure
# A PR with no review comments is indistinguishable from one still in flight.
#
# THE FIX: keep owner/repo from the URL, resolve THAT repo's checkout
# (<PROJECTS_DIR>/<name>) and the worktree holding the PR's head branch, and review
# there. When the repo is known but no local checkout exists, say so loudly rather
# than silently reviewing the session repo's empty diff.
#
# HOW THIS TESTS SAFELY: POST_HOOK_REVIEW_SCRIPT / POST_HOOK_COVERAGE_SCRIPT point at
# harmless stubs and POST_HOOK_PROJECTS_DIR points at a fixture tree, so the real
# Claude/Gemini reviews never run. A stub `gh` (first on PATH) answers only
# `--json headRefName` and fails everything else, so no case can reach the network.
# Assertions read the hook's SYNCHRONOUS stdout, which names the resolved review repo
# and worktree — no dependence on the backgrounded launch.
#
# Usage: bash test-bash-post-hook-review-repo.sh   |   Exit 0 all pass, 1 any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${BASH_POST_HOOK:-$HOOKS_DIR/bash-post-hook.sh}"

PASS_COUNT=0; FAIL_COUNT=0

i=0
while :; do
  TESTDIR="/tmp/bashposthook-reviewrepo-$(printf '%s' "$i" | tr '27' 'ab')"
  mkdir "$TESTDIR" 2>/dev/null && break
  i=$((i + 1))
  if [ "$i" -gt 500 ]; then echo "FATAL: no free test dir under /tmp" >&2; exit 1; fi
done
cleanup() { rm -rf "$TESTDIR"; rm -f /tmp/code-review-pr-42.log /tmp/test-coverage-pr-42.log /tmp/code-review-pr-9.log /tmp/test-coverage-pr-9.log; }
trap cleanup EXIT

PROJECTS="$TESTDIR/projects"
mkdir -p "$PROJECTS" "$TESTDIR/bin"

# Stub gh: answer `--json headRefName` with $GH_STUB_HEAD, fail everything else so no
# fixture can reach the network (mirrors test-bash-post-hook-cwd.sh's guard).
cat > "$TESTDIR/bin/gh" <<'GH'
#!/bin/bash
for a in "$@"; do [ "$a" = "headRefName" ] && { echo "${GH_STUB_HEAD:-}"; exit 0; }; done
exit 1
GH
chmod +x "$TESTDIR/bin/gh"
PATH="$TESTDIR/bin:$PATH"; export PATH

# Harmless review stubs — exercised by the launch but produce nothing.
STUB_REVIEW="$TESTDIR/bin/stub-review"; STUB_COV="$TESTDIR/bin/stub-coverage"
printf '#!/bin/sh\nexit 0\n' > "$STUB_REVIEW"; chmod +x "$STUB_REVIEW"
printf '#!/bin/sh\nexit 0\n' > "$STUB_COV";    chmod +x "$STUB_COV"

contains() { case "$2" in *"$3"*) PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";;
  *) FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected to contain: $3"; echo "        got: $2";; esac; }
not_contains() { case "$2" in *"$3"*) FAIL_COUNT=$((FAIL_COUNT+1)); echo "  FAIL: $1"; echo "        expected NOT to contain: $3"; echo "        got: $2";;
  *) PASS_COUNT=$((PASS_COUNT+1)); echo "  PASS: $1";; esac; }

make_repo() { # name
  local w="$PROJECTS/$1"; mkdir -p "$w"; git init -q -b main "$w"
  git -C "$w" config user.email t@t.t; git -C "$w" config user.name t
  echo seed > "$w/seed.txt"; git -C "$w" add seed.txt; git -C "$w" commit -qm seed
  echo "$w"
}

GH_STUB_HEAD=""
run_hook() { # cwd, command, stdout
  jq -n --arg c "$2" --arg w "$1" --arg o "$3" \
    '{tool_name:"Bash", cwd:$w, tool_input:{command:$c}, tool_response:{stdout:$o, stderr:""}}' \
    | POST_HOOK_PROJECTS_DIR="$PROJECTS" POST_HOOK_REVIEW_SCRIPT="$STUB_REVIEW" \
      POST_HOOK_COVERAGE_SCRIPT="$STUB_COV" GH_STUB_HEAD="$GH_STUB_HEAD" \
      bash "$HOOK" 2>/dev/null
}

echo "=== bash-post-hook PR-review repo resolution (#1198 defect 1) ==="
[ -f "$HOOK" ] || { echo "FATAL: hook not found at $HOOK" >&2; exit 1; }

REPO_A=$(make_repo repo-a)   # the "session" repo
REPO_B=$(make_repo repo-b)   # the PR's actual repo

# --- 1. THE FIX: a cross-repo PR is reviewed in ITS repo, not the session cwd ------
GH_STUB_HEAD=""
out=$(run_hook "$REPO_A" "gh pr create --repo owner/repo-b --title t" "https://github.com/owner/repo-b/pull/42")
contains "review targets the PR's own repo (owner/repo-b)" "$out" "in owner/repo-b"
contains "review runs from the repo-b checkout" "$out" "Reviewing from repo-b"
not_contains "review does NOT run from the session repo (repo-a)" "$out" "repo-a"

# --- 2. Head-branch worktree resolution inside the target repo --------------------
git -C "$REPO_B" worktree add -q "$PROJECTS/repo-b-feature" -b feature/mine
GH_STUB_HEAD="feature/mine"
out=$(run_hook "$REPO_A" "gh pr create --title t" "https://github.com/owner/repo-b/pull/42")
contains "review runs from the worktree holding the head branch" "$out" "Reviewing from repo-b-feature"

# --- 3. Repo known but NO local checkout: loud, no silent session-repo review ------
GH_STUB_HEAD=""
out=$(run_hook "$REPO_A" "gh pr create --repo owner/ghost-repo --title t" "https://github.com/owner/ghost-repo/pull/7")
contains "missing checkout is reported" "$out" "no local checkout"
contains "missing checkout runs no review" "$out" "no review run"
not_contains "missing checkout does NOT fall back to the session repo" "$out" "Reviewing from"

# --- 4. NEGATIVE COUNTERPART: same-repo PR still resolves correctly ----------------
GH_STUB_HEAD=""
out=$(run_hook "$REPO_A" "gh pr create --title t" "https://github.com/owner/repo-a/pull/9")
contains "same-repo PR reviews the session repo (repo-a)" "$out" "Reviewing from repo-a"
contains "same-repo PR names its repo" "$out" "in owner/repo-a"

# --- 5. No URL at all: unchanged recovery message (parity with prior behavior) -----
out=$(run_hook "$REPO_A" "gh pr create --title t" "")
contains "no URL yields the could-not-extract recovery message" "$out" "could not extract PR number"
contains "recovery names the effective cwd" "$out" "EFFECTIVE_CWD=$REPO_A"

echo
echo "=== Summary: $PASS_COUNT passed, $FAIL_COUNT failed ==="
[ "$FAIL_COUNT" -eq 0 ] || exit 1
