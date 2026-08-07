#!/bin/bash
# Fixture-harness test suite for tracker-now-next.sh's standing Infra slot.
# Issue: #1186 (companion change — making the Infra lane visible).
#
# Why this exists: the Infra lane was boarded but invisible. On 2026-07-22, 16
# of 17 open Infra items sat at Later with zero at Now, and this hook only
# surfaces Now + top-3 Next — so harness work never appeared at session start
# and only got touched reactively when something broke. The new block makes an
# unfilled standing slot loud. These assertions pair each positive case with its
# negative counterpart, so a silently-broken condition cannot pass by doing
# nothing (contrastive control — dev-reference/workflows/development-process.md
# Stage 4 step 4).
#
# `gh` is stubbed on PATH so no network call is made and the board's real state
# cannot make a run flaky.
#
# Usage: bash test-tracker-now-next.sh
# Exit code: 0 if all assertions pass, 1 if any fail.

set -u

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOKS_DIR/tracker-now-next.sh"

PASS_COUNT=0
FAIL_COUNT=0

TESTDIR=$(mktemp -d)
if [ -z "$TESTDIR" ] || [ ! -d "$TESTDIR" ]; then
  echo "FATAL: mktemp -d failed; refusing to run with an empty TESTDIR" >&2
  exit 1
fi
cleanup() { rm -rf "$TESTDIR"; }
trap cleanup EXIT

# --- stub harness -----------------------------------------------------------
# Writes a fake `gh` that emits $1 as the item-list payload, then runs the hook
# with that stub first on PATH. GH_EXIT lets a case simulate gh failing.
run_hook_with_board() {
  local payload="$1" gh_exit="${2:-0}"
  mkdir -p "$TESTDIR/bin"
  printf '%s\n' '#!/bin/bash' "exit_code=$gh_exit" '[ "$exit_code" -ne 0 ] && exit "$exit_code"' "cat <<'PAYLOAD_EOF'" "$payload" "PAYLOAD_EOF" > "$TESTDIR/bin/gh"
  chmod +x "$TESTDIR/bin/gh"
  PATH="$TESTDIR/bin:$PATH" bash "$HOOK" 2>/dev/null
}

item() { # number, title, priority, status, track
  printf '{"content":{"number":%s,"title":"%s"},"priority":"%s","status":"%s","track":"%s"}' "$1" "$2" "$3" "$4" "$5"
}

assert_contains() { # label, haystack, needle
  if printf '%s' "$2" | grep -qF -- "$3"; then
    PASS_COUNT=$((PASS_COUNT + 1)); echo "  PASS: $1"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  FAIL: $1"; echo "        expected to contain: $3"; echo "        got: $2"
  fi
}

assert_not_contains() { # label, haystack, needle
  if printf '%s' "$2" | grep -qF -- "$3"; then
    FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  FAIL: $1"; echo "        expected NOT to contain: $3"; echo "        got: $2"
  else
    PASS_COUNT=$((PASS_COUNT + 1)); echo "  PASS: $1"
  fi
}

echo "=== tracker-now-next.sh — standing Infra slot ==="

# A1/A2 — contrastive pair. Same board shape except the Infra item's priority.
# If the empty-slot condition were hardcoded off, A1 fails; if hardcoded on, A2 fails.
BOARD_EMPTY="{\"items\":[$(item 1085 "Product thing" Now "In Progress" Rebuild),$(item 1116 "Parked infra A" Later Todo Infra),$(item 1124 "Parked infra B" Later Todo Infra),$(item 969 "Parked infra C" Near Todo Infra)]}"
OUT=$(run_hook_with_board "$BOARD_EMPTY")
assert_contains     "A1 empty slot warns"            "$OUT" "INFRA LANE EMPTY"
assert_contains     "A1 warning counts parked items" "$OUT" "3 open Infra item(s) not at Now"

# A3 — an Infra item at Next must count as promotable. PARKED is the complement
# of Now, not an enumerated Later/Near/null list: enumerating silently drops
# Next, so the hook could report "0 item(s) parked" — nothing to promote —
# while a perfectly promotable item sat one rung down.
BOARD_NEXT="{\"items\":[$(item 1085 "Product thing" Now "In Progress" Rebuild),$(item 1130 "Infra at Next" Next Todo Infra)]}"
OUT=$(run_hook_with_board "$BOARD_NEXT")
assert_contains     "A3 Infra at Next still warns"     "$OUT" "INFRA LANE EMPTY"
assert_contains     "A3 Infra at Next counts as promotable" "$OUT" "1 open Infra item(s) not at Now"

BOARD_FILLED="{\"items\":[$(item 1085 "Product thing" Now "In Progress" Rebuild),$(item 1186 "Dispatch gate hardening" Now Todo Infra),$(item 1124 "Parked infra B" Later Todo Infra)]}"
OUT=$(run_hook_with_board "$BOARD_FILLED")
assert_not_contains "A2 filled slot does NOT warn"   "$OUT" "INFRA LANE EMPTY"

# B — Infra items in the Now list are tagged, non-Infra ones are not.
assert_contains     "B1 Infra Now item tagged"       "$OUT" "#1186 [infra]"
assert_not_contains "B2 Rebuild Now item untagged"   "$OUT" "#1085 [infra]"

# B3/B4 — the NEXT list applies the same [infra] tag as the NOW list. Same idiom,
# separate jq expression, previously unasserted.
BOARD_NEXT_TAG="{\"items\":[$(item 1186 "Dispatch gate hardening" Now Todo Infra),$(item 1130 "Infra at Next" Next Todo Infra),$(item 902 "Product at Next" Next Todo Rebuild)]}"
OUT=$(run_hook_with_board "$BOARD_NEXT_TAG")
assert_contains     "B3 Infra NEXT item tagged"      "$OUT" "#1130 [infra]"
assert_not_contains "B4 Rebuild NEXT item untagged"  "$OUT" "#902 [infra]"

# C0 — the empty-slot warning must still print when BOTH lists are empty. The
# early exit at the top is `[ -z "$NOW$NEXT" ] && [ "$INFRA_NOW" -ne 0 ]`, and
# every other fixture here carries a Now item, so this combination — no Now, no
# Next, unfilled Infra slot — was the one path that could silently exit early.
BOARD_ALL_EMPTY="{\"items\":[$(item 1124 "Parked infra B" Later Todo Infra)]}"
OUT=$(run_hook_with_board "$BOARD_ALL_EMPTY")
assert_contains     "C0 empty Now+Next still warns"  "$OUT" "INFRA LANE EMPTY"
assert_contains     "C0 empty Now+Next prints header" "$OUT" "ON DECK TRACKER"

# C — Done Infra items must not fill the slot (status filter still applies).
BOARD_DONE_ONLY="{\"items\":[$(item 1085 "Product thing" Now "In Progress" Rebuild),$(item 777 "Closed infra" Now Done Infra),$(item 1124 "Parked infra B" Later Todo Infra)]}"
OUT=$(run_hook_with_board "$BOARD_DONE_ONLY")
assert_contains     "C1 Done Infra does not fill slot" "$OUT" "INFRA LANE EMPTY"

# D — fail-open. A gh failure must produce no output and exit 0, never a warning
# built from a garbage count. This is the regression guard for the SessionStart
# contract ("MUST fail open — never block or slow-fail a session start").
OUT=$(run_hook_with_board "" 1)
assert_not_contains "D1 gh failure emits nothing"    "$OUT" "INFRA LANE EMPTY"
assert_not_contains "D2 gh failure emits no header"  "$OUT" "ON DECK TRACKER"

echo
echo "passed=$PASS_COUNT failed=$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
