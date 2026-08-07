#!/usr/bin/env bash
# tmp-scan.sh — classify files in a tmp/ directory for cleanup.
#
# Shared by /tidy (Phase 1) and /dream, so the two cannot drift. A file /tidy calls
# safe must never be a file a 2 AM routine deletes, which is only guaranteed if both
# ask the same classifier the same question.
#
# PURE FUNCTION of (files, time source, issue states). It performs NO network calls
# and NO GitHub lookups of its own — issue states are injected by the caller. That is
# not tidiness: the routine sandbox has no `gh` binary (verified 2026-07-24), and the
# GitHub MCP connector is callable only by a model, never from a script. Injecting the
# states keeps classification deterministic and offline in BOTH halves, and keeps the
# unit tests hermetic.
#
# SAFETY POSTURE: the asymmetry is deliberate. A wrong "delete" destroys work nobody
# is watching at 2 AM; a wrong "review" is only noise in a report. Every ambiguous
# case resolves toward keeping the file.
#
# Usage:
#   tmp-scan.sh --dir=<tmp-dir> [options]
#     --time-source=git|mtime   default mtime. Use git in a fresh clone: `git clone`
#                               stamps every file with checkout time, so mtime there
#                               silently reports every file as 0 days old.
#     --issue-states=1027=CLOSED,1221=OPEN
#                               state per referenced issue. Unlisted issues are
#                               treated as NOT closed (fail safe: never delete on
#                               missing information).
#     --repo-root=<path>        repo for git time lookups; defaults to --dir's repo.
#     --keep-list=<file>        one basename per line; each is suppressed (verdict
#                               skip, signal keep-registry) so a decidr "Keep" swipe
#                               stops the file re-surfacing on the next run.
#     --format=json|tsv         default json.
#
# IN-FILE MARKERS a file can carry to steer its own classification:
#   (keep) in the filename        — permanent skip; outranks every delete trigger.
#   keep-until-issue: #N          — a self-expiring park: verdict skip while issue N
#                                   is open (so it stops re-surfacing in triage), and
#                                   an archive candidate the moment N closes. This is
#                                   how a pre-mortem tracks its issue's lifecycle. The
#                                   marker's #N is metadata, not a citation — it is
#                                   stripped before the issue cross-reference.
#
# Output (json): one object per file with path, signals[], verdict,
# age_days, days_unchecked, issues{}.
set -euo pipefail

DIR=""
TIME_SOURCE="mtime"
ISSUE_STATES=""
REPO_ROOT=""
FORMAT="json"
KEEP_LIST=""

for arg in "$@"; do
  case "$arg" in
    --dir=*)           DIR="${arg#*=}" ;;
    --time-source=*)   TIME_SOURCE="${arg#*=}" ;;
    --issue-states=*)  ISSUE_STATES="${arg#*=}" ;;
    --repo-root=*)     REPO_ROOT="${arg#*=}" ;;
    --format=*)        FORMAT="${arg#*=}" ;;
    --keep-list=*)     KEEP_LIST="${arg#*=}" ;;
    *) echo "tmp-scan.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

[ -n "$DIR" ] || { echo "tmp-scan.sh: --dir is required" >&2; exit 2; }
[ -d "$DIR" ] || { echo "tmp-scan.sh: not a directory: $DIR" >&2; exit 2; }
case "$TIME_SOURCE" in
  git|mtime) ;;
  *) echo "tmp-scan.sh: --time-source must be git or mtime" >&2; exit 2 ;;
esac
case "$FORMAT" in
  json|tsv) ;;
  *) echo "tmp-scan.sh: --format must be json or tsv" >&2; exit 2 ;;
esac

[ -n "$REPO_ROOT" ] || REPO_ROOT="$DIR"

# Keep-registry: basenames the human has already dismissed via a decidr "Keep"
# swipe. Loaded once as a newline-delimited blob; membership is an exact whole-line
# match (grep -xF) so a substring can never suppress the wrong file.
KEEP_LIST_CONTENT=""
if [ -n "$KEEP_LIST" ]; then
  [ -f "$KEEP_LIST" ] || { echo "tmp-scan.sh: keep-list not found: $KEEP_LIST" >&2; exit 2; }
  KEEP_LIST_CONTENT=$(cat "$KEEP_LIST")
fi

NOW=$(date +%s)
DAY=86400
TOP_LINES=10   # mechanisation of tidy.md's "near the top"
MOCKUP_MAX_AGE=45   # a mockup-*.html older than this, unvetoed, is an archive candidate

LISTING=$(mktemp)
trap 'rm -f "$LISTING"' EXIT

# --- portable mtime -------------------------------------------------------------
# GNU first, BSD second. The order is load-bearing: GNU `stat -f` means
# --file-system and takes no format argument, so `stat -f %m FILE` on Linux prints
# filesystem info for FILE to STDOUT before failing on the bogus "%m" operand — the
# `||` fallback then appends a second value and the caller gets two lines where it
# expects an integer. BSD `stat -c` fails cleanly with no stdout, so GNU-first is
# safe on both. (BSD-first was broken on Linux, which is exactly where the night
# half runs; the local test suite could never have caught it.)
# The final `echo "$NOW"` covers TOCTOU: a file deleted between the listing and the
# stat must not abort the whole scan. Age 0 is the safe direction — "not stale".
file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo "$NOW"
}

# --- time source ----------------------------------------------------------------
# Emits "<epoch>\t<untracked-fallback 0|1>". Both come back as DATA rather than via
# a global, because this is called through $(...) — a subshell — so any global it
# assigned would be discarded the instant it returned.
file_epoch() {
  local f="$1" ct=""
  if [ "$TIME_SOURCE" = "git" ]; then
    ct=$(git -C "$REPO_ROOT" log -1 --format=%ct -- "$f" 2>/dev/null || true)
    if [ -n "$ct" ]; then
      printf '%s\t0\n' "$ct"; return
    fi
    printf '%s\t1\n' "$(file_mtime "$f")"; return
  fi
  printf '%s\t0\n' "$(file_mtime "$f")"
}

# --- issue state lookup (no network; injected) ----------------------------------
# bash 3.2 on macOS has no associative arrays, so this stays a string scan.
issue_state() {
  local num="$1" pair
  case ",$ISSUE_STATES," in
    *",$num="*)
      pair=$(printf '%s' "$ISSUE_STATES" | tr ',' '\n' | grep "^$num=" | head -1)
      printf '%s' "${pair#*=}"
      ;;
    *) printf 'UNKNOWN' ;;
  esac
}

# --- fenced code blocks are examples, not data ----------------------------------
# Docs that document checklists (this project has several) carry "- [x] Done" inside
# a ``` fence. Counting those as real checkboxes is a false-delete vector.
strip_fences() {
  awk '/^[[:space:]]*```/ { f = !f; next } !f'
}

json_escape() {
  printf '%s' "$1" \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' \
    | awk 'NR>1 { printf "\\n" } { printf "%s", $0 }'
}

# --- pass 1: classify every file -------------------------------------------------
# bash 3.2: parallel indexed arrays instead of a map.
NAMES=(); VERDICTS=(); SIGNALS=(); AGES=(); DUNCHECKED=(); ISSUELISTS=()

# -print0 so a filename containing a newline cannot split into two phantom entries.
# Written to a file rather than piped straight into the loop so a `find` failure (an
# unreadable directory, say) aborts loudly: inside a heredoc or a pipeline its exit
# status is discarded, and a partial scan would look like a clean one.
if ! find "$DIR" -maxdepth 1 -type f -print0 > "$LISTING"; then
  echo "tmp-scan.sh: failed to list $DIR" >&2
  exit 1
fi

while IFS= read -r -d '' path; do
  name=$(basename "$path")

  epoch_pair=$(file_epoch "$path")
  epoch=${epoch_pair%%	*}
  fallback=${epoch_pair##*	}
  age_days=$(( (NOW - epoch) / DAY ))
  [ "$age_days" -lt 0 ] && age_days=0

  sig=""
  add_sig() { if [ -z "$sig" ]; then sig="$1"; else sig="$sig,$1"; fi; }

  # (keep) outranks everything, including a closed issue and a ticked Done box.
  keep=0
  case "$name" in *"(keep)"*) keep=1; add_sig "keep-marker" ;; esac

  # CHECKBOX signals are read from MARKDOWN ONLY. Parsing every file type was a
  # false-delete vector: a companion .js carrying "// - [x] implement login" scored
  # all-checkboxes-checked and was deleted on its own merit — which pass 2's
  # companion rule cannot rescue, because that rule only ever promotes TO delete.
  #
  # ISSUE references are ALSO read from a mockup-*.html, because the open-issue veto
  # needs them: a stale mockup pointing at a still-open issue must be kept, and the
  # only place that #NNNN lives is inside the html. Reading a mockup's body does NOT
  # make a closed-issue reference a delete trigger for it — that path is gated to
  # markdown below (is_md), so a mockup is archived on age alone, never on a citation.
  done_checkbox=0; all_checked=0; unchecked_remain=0; done_unchecked=0; is_md=0
  body=""
  case "$name" in
    *.md)
      is_md=1
      body=$(strip_fences < "$path" 2>/dev/null || true)
      head_n=$(printf '%s\n' "$body" | head -n "$TOP_LINES")

      printf '%s' "$head_n" | grep -qE '^[[:space:]]*-[[:space:]]*\[[xX]\][[:space:]]*Done' && done_checkbox=1
      printf '%s' "$head_n" | grep -qE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\][[:space:]]*Done' && done_unchecked=1

      n_checked=$(printf '%s' "$body" | grep -cE '^[[:space:]]*-[[:space:]]*\[[xX]\]' || true)
      n_unchecked=$(printf '%s' "$body" | grep -cE '^[[:space:]]*-[[:space:]]*\[[[:space:]]\]' || true)
      [ "$n_unchecked" -gt 0 ] && unchecked_remain=1
      [ "$n_checked" -gt 0 ] && [ "$n_unchecked" -eq 0 ] && all_checked=1
      ;;
    mockup-*.html)
      body=$(cat "$path" 2>/dev/null || true)
      ;;
  esac

  [ "$done_checkbox" = 1 ] && add_sig "done-checkbox"
  [ "$all_checked" = 1 ] && add_sig "all-checkboxes-checked"
  [ "$unchecked_remain" = 1 ] && add_sig "unchecked-remain"
  [ "$done_unchecked" = 1 ] && add_sig "done-unchecked"

  # GitHub cross-reference. ALL referenced issues must be closed to count as done;
  # an unknown state is never treated as closed.
  #
  # A `#` is REQUIRED — a bare integer in prose ("step 1", "personas 1-8") is not
  # an issue reference. But `#[0-9]+` alone still pulls `#1` out of a hash-prefixed
  # RANGE like `#1-8` / `#1–8`, and a coincidental collision with a closed issue #1
  # then drives a false `issues-all-closed` archive (observed on the first /dream
  # run: pre-mortem-gifted-access, text `#1–8`). So drop range tokens: normalize
  # en-/em-dashes to a plain hyphen (as two SEPARATE literal substitutions — a
  # `[–—]` bracket class matches individual UTF-8 bytes under a C locale and would
  # mangle the run, the exact multibyte trap run-in-docker exists to catch), match
  # the whole `#N-M` token, then discard any token still carrying a hyphen. No PCRE
  # lookahead: BSD grep on macOS has no -P, and this suite runs on macOS and Linux.
  # `|| true`: a file with no issue refs makes grep exit 1, which pipefail would
  # otherwise turn into a scan-wide abort. No refs is the common case, not an error.
  # A `keep-until-issue: #N` marker line is metadata, not a citation — its #N names
  # the park's expiry, not work this file references. Drop those lines before the
  # cross-reference so a parked file never earns a spurious issues-open/closed from
  # its own marker (its verdict comes from the park block below instead).
  issues=$(printf '%s' "$body" | grep -viE 'keep-until-issue:' \
    | sed -e 's/–/-/g' -e 's/—/-/g' \
    | grep -oE '#[0-9]+(-[0-9]+)?' | grep -v '-' \
    | tr -d '#' | sort -un | tr '\n' ' ' || true)
  issue_json=""
  if [ -n "$(printf '%s' "$issues" | tr -d ' ')" ]; then
    all_closed=1
    for n in $issues; do
      st=$(issue_state "$n")
      [ "$st" = "CLOSED" ] || all_closed=0
      [ -n "$issue_json" ] && issue_json="$issue_json,"
      # $st is caller-supplied via --issue-states and must be escaped: a state
      # containing a quote or backslash would otherwise emit malformed JSON into
      # the very format /dream consumes unattended. ($n is digit-constrained by
      # the extraction above and is safe as-is.)
      issue_json="$issue_json\"$n\":\"$(json_escape "$st")\""
    done
    if [ "$all_closed" = 1 ]; then add_sig "issues-all-closed"; else add_sig "issues-open"; fi
  fi

  # keep-until-issue: a deliberate park keyed to an issue's lifecycle. `keep-until-issue:
  # #N` keeps a file SUPPRESSED (verdict skip) while N is open, and lets the park EXPIRE
  # to an archive candidate the moment N closes. This is how a pre-mortem tracks its own
  # issue — kept while the work is unshipped, surfaced for archival once it lands, and
  # never re-swiped in the triage pile in between. An unknown state is "not closed"
  # (fail-safe toward keeping), the same posture the issue cross-reference takes. The
  # marker's #N was stripped from that cross-reference above, so the two never conflict.
  park_active=0; park_expired=0
  keep_until=$(LC_ALL=C grep -aoE 'keep-until-issue:[[:space:]]*#?[0-9]+' "$path" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
  if [ -n "$keep_until" ]; then
    if [ "$(issue_state "$keep_until")" = "CLOSED" ]; then
      park_expired=1; add_sig "park-expired-$keep_until-closed"
    else
      park_active=1; add_sig "parked-until-$keep_until"
    fi
  fi

  case "$name" in mockup-*.html) add_sig "mockup-needs-brief-state" ;; esac
  [ "$fallback" = 1 ] && add_sig "untracked-fallback"

  # Verdict. Companions are resolved in pass 2, once every .md verdict is known.
  #
  # AN OPEN ISSUE VETOES A DONE SIGNAL, demoting delete -> review (2026-07-25).
  # This REVERSES the original precedence, in which a ticked Done box outranked an
  # open issue reference. The reversal was forced by a real file, not a thought
  # experiment: the first live scan of `example-context/tmp/` classified
  # `dream-workflow-framing-2026-07-24.md` as DELETE — signals
  # `done-checkbox,all-checkboxes-checked,issues-open` — while #1221 was open and
  # the active brief linked to that very file as its framing source. An unattended
  # 2 AM run would have deleted the framing document of the project it was built
  # for, on its first real night.
  #
  # The two signals mean different things and the old rule conflated them. A ticked
  # "- [x] Done" says THIS CHECKLIST IS COMPLETE; it does not say the document is
  # disposable. For a framing or decision doc, "done" is precisely when it becomes
  # worth keeping. An open issue is a live claim that something still references
  # this work. So the done signal still generates a candidate — the file surfaces
  # in the report either way — but the open issue withholds the automatic deletion
  # and puts a human on it.
  #
  # Fail-safe covers unknown states too: an issue whose state was not supplied is
  # "not closed", so it vetoes as well. The veto only ever moves a verdict toward
  # keeping, which is the direction this whole script is biased in.
  # A mockup-*.html older than MOCKUP_MAX_AGE, with no live claim on it, is stale:
  # a mockup is a throwaway design surface, and once its brief has shipped (or gone
  # cold) it is exactly the kind of artifact this routine exists to archive. Like
  # every other delete trigger below, it is still subject to the open-issue veto —
  # an old mockup a live issue points at is kept.
  mockup_stale=0
  case "$name" in
    mockup-*.html) [ "$age_days" -gt "$MOCKUP_MAX_AGE" ] && mockup_stale=1 ;;
  esac
  [ "$mockup_stale" = 1 ] && add_sig "mockup-stale"

  # keep-registry outranks every delete trigger, exactly as an in-file (keep) marker
  # does: a human already said keep, so we do not re-litigate it at 2 AM.
  in_keep_list=0
  if [ -n "$KEEP_LIST_CONTENT" ] && printf '%s\n' "$KEEP_LIST_CONTENT" | grep -qxF "$name"; then
    in_keep_list=1
  fi

  # Delete candidates: a ticked Done box, an all-checkboxes-checked list, an
  # all-issues-closed reference, or a stale mockup. The open-issue veto then demotes
  # ANY candidate to review — one uniform rule instead of one per trigger.
  #
  # An UNCHECKED checkbox (`unchecked-remain`) is deliberately NOT a veto and never
  # blocks a `delete` — an all-issues-closed file archives even with boxes unticked
  # (the `issue-closed.md` golden fixture pins this). Decided 2026-08-03 (USER):
  # he "sometimes just forgets the checkboxes", so an unchecked box is not reliable
  # evidence of unfinished work, whereas a closed cited issue is a positive signal
  # the work landed. Only an OPEN/unknown-state cited issue withholds archival.
  cand=0
  { [ "$done_checkbox" = 1 ] || [ "$all_checked" = 1 ]; } && cand=1
  [ "$is_md" = 1 ] && printf '%s' "$sig" | grep -q 'issues-all-closed' && cand=1
  [ "$mockup_stale" = 1 ] && cand=1

  if [ "$keep" = 1 ] || [ "$in_keep_list" = 1 ]; then
    verdict="skip"
    [ "$in_keep_list" = 1 ] && [ "$keep" = 0 ] && add_sig "keep-registry"
  elif [ "$park_active" = 1 ]; then
    # Parked against an open issue: suppressed like a keep, but self-expiring.
    verdict="skip"
  elif [ "$park_expired" = 1 ]; then
    # The park's issue closed: surface for archival regardless of other signals.
    verdict="delete"
  elif printf '%s' "$sig" | grep -q 'issues-open'; then
    # An open (or unknown-state) cited issue means the artifact is still live: keep it,
    # and — decided 2026-08-05 (USER) — never even ASK. This SUPERSEDES the older
    # open-issue veto, which only demoted a delete candidate to `review` (a triage-deck
    # question): "if something is still open, you shouldn't ask me if I want to archive
    # it." Like a keep-until-issue park, this self-expires — once every cited issue
    # closes the file re-earns `issues-all-closed` and, if it carries a done signal,
    # archives on the next pass. Applies whether or not the file is a delete candidate.
    verdict="skip"
    add_sig "open-issue-keep"
  elif [ "$cand" = 1 ]; then
    verdict="delete"
  else
    verdict="review"
  fi

  du="-"
  [ "$done_unchecked" = 1 ] && du="$age_days"

  NAMES+=("$name"); VERDICTS+=("$verdict"); SIGNALS+=("$sig")
  AGES+=("$age_days"); DUNCHECKED+=("$du"); ISSUELISTS+=("$issue_json")
done < <(LC_ALL=C sort -z < "$LISTING")

# --- pass 2: a companion follows its deleted same-base sibling --------------------
# A companion is a generated satellite of a primary artifact that shares its base
# name: a .js next to a foo.md brief, a .png render next to a mockup-foo.html. When
# the primary is archived the companion is dead weight, so it inherits the delete —
# but ONLY that direction (companion->delete), never the reverse. Matching is on the
# shared base (name minus its final extension), so .png follows .html just as .js
# follows .md, without either type being special-cased.
i=0
while [ $i -lt ${#NAMES[@]} ]; do
  n="${NAMES[$i]}"
  case "$n" in
    *.js|*.png)
      base="${n%.*}"
      j=0
      while [ $j -lt ${#NAMES[@]} ]; do
        if [ "$j" -ne "$i" ] && [ "${NAMES[$j]%.*}" = "$base" ] && \
           [ "${VERDICTS[$j]}" = "delete" ]; then
          VERDICTS[$i]="delete"
          if [ -z "${SIGNALS[$i]}" ]; then SIGNALS[$i]="companion-of-deleted"
          else SIGNALS[$i]="${SIGNALS[$i]},companion-of-deleted"; fi
          break
        fi
        j=$(( j + 1 ))
      done
      ;;
  esac
  i=$(( i + 1 ))
done

# --- emit -----------------------------------------------------------------------
if [ "$FORMAT" = "tsv" ]; then
  i=0
  while [ $i -lt ${#NAMES[@]} ]; do
    s="${SIGNALS[$i]}"; [ -n "$s" ] || s="-"
    printf '%s\t%s\t%s\t%s\n' "${NAMES[$i]}" "${VERDICTS[$i]}" "$s" "${DUNCHECKED[$i]}"
    i=$(( i + 1 ))
  done
  exit 0
fi

printf '[\n'
i=0
while [ $i -lt ${#NAMES[@]} ]; do
  [ $i -gt 0 ] && printf ',\n'
  sig_json=""
  if [ -n "${SIGNALS[$i]}" ]; then
    sig_json=$(printf '%s' "${SIGNALS[$i]}" | tr ',' '\n' | sed 's/.*/"&"/' | paste -sd, -)
  fi
  du="${DUNCHECKED[$i]}"
  if [ "$du" = "-" ]; then du_json="null"; else du_json="$du"; fi
  printf '  {"path":"%s","verdict":"%s","signals":[%s],"age_days":%s,"days_unchecked":%s,"issues":{%s}}' \
    "$(json_escape "$DIR/${NAMES[$i]}")" "${VERDICTS[$i]}" "$sig_json" \
    "${AGES[$i]}" "$du_json" "${ISSUELISTS[$i]}"
  i=$(( i + 1 ))
done
printf '\n]\n'
