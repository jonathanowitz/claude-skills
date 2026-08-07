#!/bin/bash
# SessionStart hook (Tier 1) — surface the Project Tracker board's Now + top-3 Next.
# Source of truth for work priority/state is GitHub Project #1 (USER/projects/1).
# MUST fail open (exit 0, no output) — never block or slow-fail a session start.
# Cap is deliberate (agy review): Now (all) + at most 3 Next, to avoid context bloat.

OWNER=USER

JSON=$(gh project item-list 1 --owner "$OWNER" --limit 600 --format json 2>/dev/null) || exit 0
[ -z "$JSON" ] && exit 0

NOW=$(printf '%s' "$JSON" | jq -r '[.items[]|select(.priority=="Now" and .status!="Done")]|.[]|"  > NOW   #\(.content.number) \(if .track=="Infra" then "[infra] " else "" end)\(.content.title[0:72])"' 2>/dev/null)
NEXT=$(printf '%s' "$JSON" | jq -r '[.items[]|select(.priority=="Next" and .status!="Done")]|.[0:3][]|"  . NEXT  #\(.content.number) \(if .track=="Infra" then "[infra] " else "" end)\(.content.title[0:72])"' 2>/dev/null)

# Standing Infra slot. The Infra lane is where dev-harness work lives. It has
# historically been boarded but parked: on 2026-07-22, 16 of 17 open Infra items
# sat at Later with zero at Now, so the entire lane was invisible here (this hook
# only surfaces Now + top-3 Next). Harness work then only got touched reactively
# when something broke. The convention is one Infra item held at Now at all times;
# this block makes an unfilled slot loud instead of silent. Counts only — no extra
# API call, same JSON payload already fetched above.
#
# PARKED is "every open Infra item not already at Now" — deliberately the
# complement of NOW rather than an enumerated list of parked priorities. An
# enumerated list (Later/Near/null) silently drops anything at Next, which is
# how the hook could report "0 item(s) parked" while offering nothing to
# promote and having a perfectly promotable item sitting one rung down.
INFRA_NOW=$(printf '%s' "$JSON" | jq -r '[.items[]|select(.track=="Infra" and .priority=="Now" and .status!="Done")]|length' 2>/dev/null)
INFRA_PARKED=$(printf '%s' "$JSON" | jq -r '[.items[]|select(.track=="Infra" and .status!="Done" and .priority!="Now")]|length' 2>/dev/null)
case "$INFRA_NOW" in ''|*[!0-9]*) INFRA_NOW=-1 ;; esac
case "$INFRA_PARKED" in ''|*[!0-9]*) INFRA_PARKED=0 ;; esac

[ -z "$NOW$NEXT" ] && [ "$INFRA_NOW" -ne 0 ] && exit 0

echo "ON DECK TRACKER (source of truth for priority/state: gh project #1). Start work on an issue with: bash ~/.claude/hooks/example-now.sh <issue#>"
[ -n "$NOW" ]  && printf '%s\n' "$NOW"
[ -n "$NEXT" ] && printf '%s\n' "$NEXT"
[ "$INFRA_NOW" -eq 0 ] && printf '%s\n' "  ! INFRA LANE EMPTY — standing slot unfilled, $INFRA_PARKED open Infra item(s) not at Now. Promote one, or decide out loud to leave it empty."
exit 0
