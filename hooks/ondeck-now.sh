#!/bin/bash
# example-now <issue-number> — mark a tracker item In Progress + Priority=Now.
# Run this when starting work on an issue (Tier-2 "In Progress" transition, done explicitly
# because branch names are descriptive and carry no issue number). Adds the issue to the
# board first if it isn't there yet. State->Done is handled by GitHub's native closed->Done
# workflow, NOT here, to avoid a double-write race (agy review).

NUM="$1"
if [ -z "$NUM" ]; then echo "usage: example-now <issue-number>"; exit 1; fi

# example-now is the example-app board tool, so the board owner/PID/field IDs
# below stay example-app's own — but the issue URL itself resolves the current
# repo's declared tracker (orbit repos still resolve to USER/example-app;
# every other repo falls back to the same default here, since this tool only
# ever targets the example-app board) (example-app/#1201).
RESOLVER="$(dirname "${BASH_SOURCE[0]}")/resolve-product.sh"
[ -f "$RESOLVER" ] && . "$RESOLVER"
TRACKER=""
if command -v resolve_product_field >/dev/null 2>&1; then
  TRACKER="$(resolve_product_field issue_tracker 2>/dev/null)" || TRACKER=""
fi
[ -n "$TRACKER" ] || TRACKER="USER/example-app"

OWNER=USER
PID="PVT_kwHOAI1B-M4BQIxS"
F_PRIO="PVTSSF_lAHOAI1B-M4BQIxSzhYNXug";  O_NOW=93fb5f92
F_STATUS="PVTSSF_lAHOAI1B-M4BQIxSzg-WAHE"; O_INPROG=47fc9ee4

IID=$(gh project item-list 1 --owner "$OWNER" --limit 600 --format json 2>/dev/null \
  | jq -r --argjson n "$NUM" '.items[]|select(.content.number==$n)|.id' | head -1)

if [ -z "$IID" ] || [ "$IID" = "null" ]; then
  IID=$(gh project item-add 1 --owner "$OWNER" \
    --url "https://github.com/$TRACKER/issues/$NUM" --format json 2>/dev/null \
    | jq -r '.id')
fi

if [ -z "$IID" ] || [ "$IID" = "null" ]; then echo "example-now: could not resolve a board item for #$NUM"; exit 1; fi

gh project item-edit --id "$IID" --project-id "$PID" --field-id "$F_STATUS" --single-select-option-id "$O_INPROG" >/dev/null
gh project item-edit --id "$IID" --project-id "$PID" --field-id "$F_PRIO"   --single-select-option-id "$O_NOW"    >/dev/null
echo "example: #$NUM -> In Progress + Now"
