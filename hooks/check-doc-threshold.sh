#!/usr/bin/env bash
# check-doc-threshold.sh — audit a named doc against a written line-count rule.
#
# C2 in the dream brief. Build-new: nothing in scope audits a third-party doc
# against a convention today. `pattern-capture.sh` trims its OWN append-only log
# to a line count, which is rotation, not auditing — it was explicitly rejected
# as prior art.
#
# Rule: `next-steps.md` max 100 lines (next-steps-convention.md:65; was 300,
# lowered 2026-07-31). The threshold is a parameter rather than a constant so the
# second doc that acquires a written rule costs one call site, not a fork of this
# script; 100 is the default because next-steps is the only real consumer today.
#
# STRUCTURAL CHECK (#1255): line count is a blunt proxy. A next-steps file rots
# into a changelog long before any line cap — the evidence was a 143-line file
# already carrying SIX `## Immediate next step` sections while the 300-line gate
# stayed green (next-steps-convention.md rule 8: "exactly one"). Pass
# --unique-section="<header>" and the audit also counts anchored occurrences of
# that header. Rule 8 is "exactly one", so BOTH sides are violations regardless
# of line count: >1 → `duplicate_sections`, 0-when-checked → `missing_section`
# (a renamed/deleted heading, which would otherwise audit green forever).
#
# BOUNDARY IS EXACT AND DELIBERATE: "max N" means N passes and N+1 fails.
# Pinned by V4 at 299/300/301 because an off-by-one here is invisible — it would
# either nag about a compliant doc every night or silently tolerate creep.
#
# Exit status is NOT the verdict. It always exits 0 on a successful audit, even
# for a violation (line OR structural): this runs inside an unattended pipeline
# under `set -e`, where a non-zero "I found something" is indistinguishable from
# "I crashed" and would abort the rest of the night's jobs. The verdict is in the
# output. Exit 2 = bad usage, exit 1 = the file could not be read (a real failure).
#
# Usage:
#   check-doc-threshold.sh --file=<path> [--max-lines=100] [--label=<name>]
#                          [--unique-section=<header>] [--format=json|tsv]
set -euo pipefail

FILE=""
MAX_LINES=100
LABEL=""
FORMAT="json"
UNIQUE_SECTION=""

for arg in "$@"; do
  case "$arg" in
    --file=*)           FILE="${arg#*=}" ;;
    --max-lines=*)      MAX_LINES="${arg#*=}" ;;
    --label=*)          LABEL="${arg#*=}" ;;
    --unique-section=*) UNIQUE_SECTION="${arg#*=}" ;;
    --format=*)         FORMAT="${arg#*=}" ;;
    *) echo "check-doc-threshold.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

[ -n "$FILE" ] || { echo "check-doc-threshold.sh: --file is required" >&2; exit 2; }
case "$MAX_LINES" in
  ''|*[!0-9]*) echo "check-doc-threshold.sh: --max-lines must be a non-negative integer" >&2; exit 2 ;;
esac
case "$FORMAT" in
  json|tsv) ;;
  *) echo "check-doc-threshold.sh: --format must be json or tsv" >&2; exit 2 ;;
esac

# A missing target is a REAL failure, not a silent pass. The likeliest cause is a
# doc that moved or was renamed, and reporting "0 lines, compliant" for a file
# that no longer exists is exactly the clean-looking lie KD-12 warns about.
if [ ! -f "$FILE" ]; then
  echo "check-doc-threshold.sh: no such file: $FILE" >&2
  exit 1
fi

[ -n "$LABEL" ] || LABEL=$(basename "$FILE")

# `wc -l < file` rather than `wc -l file`: the redirect form emits the count
# alone, with no filename to strip and no BSD/GNU padding difference to trim.
LINES=$(wc -l < "$FILE" | tr -d '[:space:]')

# A final line with no trailing newline is still a line. wc counts newlines, so
# it under-reports by one here — the difference between 300 and 301 on a doc
# someone just edited without a trailing newline.
if [ -n "$(tail -c 1 "$FILE")" ]; then
  LINES=$(( LINES + 1 ))
fi

if [ "$LINES" -gt "$MAX_LINES" ]; then
  VIOLATION="true"
  OVERAGE=$(( LINES - MAX_LINES ))
else
  VIOLATION="false"
  OVERAGE=0
fi

# Structural check. Only runs when a header is supplied; otherwise the fields are
# inert (0 / false) so the output shape stays stable for callers that do not ask.
# The header is matched ANCHORED at line start — a quote of "## Immediate next
# step" inside a paragraph is prose, not a second section. The header is treated
# as a literal string, not a pattern: every regex metacharacter in it is escaped
# so a `#`, `.`, or `*` in a real heading cannot silently change what is counted.
#
# Rule 8 is "EXACTLY one" (next-steps-convention.md:66), so BOTH halves are
# violations: >1 is `duplicate_sections`, and 0-when-checked is `missing_section`.
# The zero case is the sharp one — without a distinct flag it is byte-identical to
# "the check never ran", so a file whose heading was renamed or deleted would
# audit green forever. That is the exact clean-looking lie this whole check
# exists to kill, so it gets its own signal, not a silent 0.
SECTIONS=0
DUPLICATE_SECTIONS="false"
MISSING_SECTION="false"
if [ -n "$UNIQUE_SECTION" ]; then
  ESCAPED=$(printf '%s' "$UNIQUE_SECTION" | LC_ALL=C sed 's/[][\.^$*+?(){}|/]/\\&/g')
  # grep -c with a no-match still exits 1 under set -e; `|| true` keeps the count.
  SECTIONS=$(grep -cE "^${ESCAPED}([[:space:]]|$)" "$FILE" || true)
  SECTIONS=$(printf '%s' "$SECTIONS" | tr -d '[:space:]')
  if [ "$SECTIONS" -gt 1 ]; then
    DUPLICATE_SECTIONS="true"
  elif [ "$SECTIONS" -eq 0 ]; then
    MISSING_SECTION="true"
  fi
fi

if [ "$FORMAT" = "tsv" ]; then
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$LABEL" "$LINES" "$MAX_LINES" "$VIOLATION" "$OVERAGE" \
    "$SECTIONS" "$DUPLICATE_SECTIONS" "$MISSING_SECTION"
  exit 0
fi

json_escape() {
  printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

printf '{"label":"%s","file":"%s","lines":%s,"max_lines":%s,"violation":%s,"overage":%s,"section_header":"%s","sections":%s,"duplicate_sections":%s,"missing_section":%s}\n' \
  "$(json_escape "$LABEL")" "$(json_escape "$FILE")" \
  "$LINES" "$MAX_LINES" "$VIOLATION" "$OVERAGE" \
  "$(json_escape "$UNIQUE_SECTION")" "$SECTIONS" "$DUPLICATE_SECTIONS" "$MISSING_SECTION"
