#!/usr/bin/env bash
# archive-with-index.sh — move an artifact into the dated archive and record what
# decision it carries, in one indivisible step.
#
# C3 in the dream brief. The MOVE is reuse (tidy.md:84 et al already move files);
# the INDEX is the build-new. USER's requirement was never "get these out of
# the way" — it was "mechanisms for archiving/recording things and indexing them
# so we can always refer back to decisions". A move without an index row is the
# failure mode, not a partial success.
#
# THE INVARIANT: never move without indexing. If the index write fails, the file
# stays exactly where it was and this exits non-zero. An artifact that is neither
# in its old location nor in the index is lost — nobody greps an archive
# directory they don't know exists. Pinned by V5, which induces a real index
# write failure and asserts the file did not move.
#
# KD-11 — DECISION TEXT IS READ, NEVER INFERRED. The text comes from an explicit
# `## Decision` section or a `decision:` frontmatter key. If neither is present
# the row reads "no explicit decision recorded" and links to the file. A bash
# script cannot summarise a document, and having an LLM do it would violate KD-7
# and risk a hallucinated row. An index nobody can trust is worse than no index,
# because an index gets cited. Honest gap beats invented summary. (The runtime
# spike produced a live instance of exactly this: the routine's own prose
# miscalculated an mtime delta while reporting the raw epochs correctly.)
#
# Usage:
#   archive-with-index.sh --file=<path> --archive-root=<dir> --index=<path>
#                         [--origin=<text>] [--archived-on=YYYY-MM-DD] [--dry-run]
#
# --dry-run prints the exact destination and the exact INDEX.md diff it WOULD
# have written, and changes nothing. That is Slice 1's whole posture: build the
# real artifact, withhold only the write.
set -euo pipefail

FILE=""
ARCHIVE_ROOT=""
INDEX=""
ORIGIN=""
ARCHIVED_ON=""
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --file=*)         FILE="${arg#*=}" ;;
    --archive-root=*) ARCHIVE_ROOT="${arg#*=}" ;;
    --index=*)        INDEX="${arg#*=}" ;;
    --origin=*)       ORIGIN="${arg#*=}" ;;
    --archived-on=*)  ARCHIVED_ON="${arg#*=}" ;;
    --dry-run)        DRY_RUN=1 ;;
    *) echo "archive-with-index.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

[ -n "$FILE" ]         || { echo "archive-with-index.sh: --file is required" >&2; exit 2; }
[ -n "$ARCHIVE_ROOT" ] || { echo "archive-with-index.sh: --archive-root is required" >&2; exit 2; }
[ -n "$INDEX" ]        || { echo "archive-with-index.sh: --index is required" >&2; exit 2; }
[ -f "$FILE" ]         || { echo "archive-with-index.sh: no such file: $FILE" >&2; exit 1; }

[ -n "$ARCHIVED_ON" ] || ARCHIVED_ON=$(date +%Y-%m-%d)
case "$ARCHIVED_ON" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) echo "archive-with-index.sh: --archived-on must be YYYY-MM-DD" >&2; exit 2 ;;
esac
MONTH_DIR="${ARCHIVED_ON%-*}"     # YYYY-MM

NAME=$(basename "$FILE")
DEST_DIR="$ARCHIVE_ROOT/$MONTH_DIR"
DEST="$DEST_DIR/$NAME"

# ORIGIN defaults to the path RELATIVE TO THE REPO ROOT, not to whatever absolute
# path this process was invoked with. Same reason link_target() exists a few lines
# down: INDEX.md is committed and read on other machines and in the GitHub UI,
# where `$HOME/Projects/...` is meaningless. Relativizing only the link
# and leaving the origin absolute would leave half of every row host-specific —
# and `/dream night` invokes this without --origin.
#
# Derived with `rev-parse --show-prefix` rather than by stripping `--show-toplevel`
# off the front of $FILE. String-prefix matching looks equivalent and is not: on
# macOS `/var` is a symlink to `/private/var`, so a file under a mktemp dir arrives
# as `/var/folders/...` while show-toplevel reports `/private/var/folders/...`, the
# match fails, and the absolute path silently survives into the committed index.
# show-prefix asks git for the answer instead of reconstructing it.
if [ -z "$ORIGIN" ]; then
  ORIGIN_PREFIX=$(git -C "$(dirname "$FILE")" rev-parse --show-prefix 2>/dev/null || true)
  if [ -n "$ORIGIN_PREFIX" ]; then
    ORIGIN="${ORIGIN_PREFIX}${NAME}"
  elif git -C "$(dirname "$FILE")" rev-parse --show-toplevel >/dev/null 2>&1; then
    ORIGIN="$NAME"          # file sits at the repo root: prefix is legitimately empty
  else
    ORIGIN="$FILE"          # not in a repo at all: absolute is all we have
  fi
fi

# Refuse to silently overwrite a same-named artifact from a previous archival.
# Two files that shared a name now share a row, and the older one is gone with no
# trace — the exact "lost artifact" this script exists to prevent.
#
# CHECKED IN DRY-RUN TOO. Withholding the *write* is this slice's posture;
# withholding the *warning* is not. Five independent invocations land in one
# YYYY-MM directory, so two same-named sources would otherwise produce a green
# dry run followed by a hard-failing armed run — the dry run's one job is to not
# do that.
if [ -e "$DEST" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "archive-with-index.sh: COLLISION — $DEST already exists; the armed run would fail here" >&2
  else
    echo "archive-with-index.sh: destination already exists, refusing to overwrite: $DEST" >&2
  fi
  exit 1
fi

# --- fenced code blocks are examples, not data ----------------------------------
# Same rule as tmp-scan.sh: a doc that DOCUMENTS this convention will contain a
# literal "## Decision" inside a fence. Reading that as the file's own decision
# would put a snippet of documentation into the index as fact.
strip_fences() {
  awk '/^[[:space:]]*```/ { f = !f; next } !f'
}

# --- decision extraction (explicit markers only — KD-11) -------------------------
# Two accepted markers, checked in order:
#   1. `decision:` in YAML frontmatter (first fenced --- block)
#   2. a `## Decision` heading; text = lines until the next heading
# Everything is collapsed to a single line, because the index is a table and a
# row that spans lines breaks the table for every row after it.
extract_decision() {
  local f="$1" body d

  # A binary artifact (e.g. a PNG mockup) carries no text marker, and probing it
  # runs awk over the raw bytes — which dies with "awk: towc: multibyte conversion
  # failure" and spews the bytes at a caller capturing stderr. `grep -I` treats a
  # binary file as non-matching, so this returns empty (→ "no marker") without ever
  # reading the bytes as text. Behaviour is unchanged; only the noise is gone.
  if ! LC_ALL=C grep -Iq . "$f" 2>/dev/null; then
    return
  fi

  # Frontmatter first: it is the more explicit of the two, being a named key.
  if [ "$(head -n 1 "$f")" = "---" ]; then
    d=$(awk 'NR>1 { if ($0 == "---") exit; print }' "$f" \
        | grep -iE '^decision:[[:space:]]*' \
        | head -1 \
        | sed -E 's/^[Dd][Ee][Cc][Ii][Ss][Ii][Oo][Nn]:[[:space:]]*//' || true)
    if [ -n "$d" ]; then printf '%s' "$d"; return; fi
  fi

  body=$(strip_fences < "$f")
  d=$(printf '%s\n' "$body" | awk '
    /^##[[:space:]]+[Dd]ecision([[:space:]]|$)/ { grab = 1; next }
    grab && /^#/ { exit }
    grab { print }
  ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
      | grep -v '^$' \
      | tr '\n' ' ' \
      | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/[[:space:]]*$//' || true)

  printf '%s' "$d"
}

DECISION=$(extract_decision "$FILE")
if [ -n "$DECISION" ]; then
  HAS_MARKER="yes"
else
  # V14: never a generated summary. The gap is stated, and the row still links to
  # the file so a human can go read it.
  DECISION="_no explicit decision recorded_"
  HAS_MARKER="no"
fi

# A pipe inside the decision text would split the markdown table cell and shift
# every column right of it. Escape rather than truncate — the text is the payload.
escape_cell() {
  printf '%s' "$1" | sed -e 's/|/\\|/g'
}

# The link target is written RELATIVE TO THE INDEX, not as the absolute path this
# process happened to run with. INDEX.md is committed and read on other machines
# and in the GitHub UI, where `$HOME/Projects/...` is a dead link — and
# a dead link in the index defeats the "always refer back to decisions" purpose
# the index exists for. The common case (index at <archive>/INDEX.md, file at
# <archive>/YYYY-MM/<name>) is a plain prefix strip; anything else falls back to
# the absolute path rather than guessing at a ../ chain.
link_target() {
  local dest="$1" idx_dir="$2"
  case "$dest" in
    "$idx_dir"/*) printf '%s' "${dest#"$idx_dir"/}" ;;
    *)            printf '%s' "$dest" ;;
  esac
}

LINK=$(link_target "$DEST" "$(dirname "$INDEX")")
ROW="| $ARCHIVED_ON | \`$NAME\` | $(escape_cell "$ORIGIN") | [$LINK]($LINK) | $(escape_cell "$DECISION") |"

# One line per paragraph, deliberately, however long the line runs. This string is
# written verbatim into a committed .md, so hard-wrapping it here reproduces the
# wrapping in the artifact — the thing CLAUDE.md Rule 6 prohibits, reached through
# a generator instead of a direct edit. The rule is about the file that lands, not
# about who typed it.
INDEX_HEADER='# Archive Index

Every artifact moved into the archive, and the decision it records. Appended by `archive-with-index.sh` — one row per archival, written in the same operation as the move. Decision text is read from an explicit `## Decision` section or a `decision:` frontmatter key, never inferred (KD-11); files without a marker say so rather than carrying a generated summary.

| Archived | File | Origin | Archived to | Decision |
|---|---|---|---|---|'

# --- dry run: emit the exact artifacts, write nothing ----------------------------
if [ "$DRY_RUN" = 1 ]; then
  printf 'MOVE      %s\n' "$FILE"
  printf '       -> %s\n' "$DEST"
  printf 'MARKER    %s\n' "$HAS_MARKER"
  printf 'INDEX     %s\n' "$INDEX"
  printf -- '--- a/%s\n+++ b/%s\n' "$INDEX" "$INDEX"
  if [ ! -f "$INDEX" ]; then
    printf '%s\n' "$INDEX_HEADER" | sed 's/^/+/'
  fi
  printf '+%s\n' "$ROW"
  exit 0
fi

# --- the write, ordered so a failure is always recoverable -----------------------
# Staged in the index's OWN directory so the final step is a same-filesystem
# rename, which cannot half-complete.
INDEX_DIR=$(dirname "$INDEX")
mkdir -p "$INDEX_DIR" || { echo "archive-with-index.sh: cannot create index dir: $INDEX_DIR" >&2; exit 1; }

TMP_INDEX=$(mktemp "$INDEX_DIR/.INDEX.XXXXXX") || {
  echo "archive-with-index.sh: cannot stage index write in $INDEX_DIR — NOT moving $FILE" >&2
  exit 1
}
# Only clears on success; every failure path below exits with the temp removed.
# INT and TERM as well as EXIT: an interrupt landing between the two `mv` calls
# below would otherwise leave the file archived and unindexed — precisely the
# lost-artifact state THE INVARIANT block exists to prevent, and the window is
# real for a job running unattended at 2 AM.
trap 'rm -f "$TMP_INDEX"' EXIT INT TERM

if [ -f "$INDEX" ]; then
  cat "$INDEX" > "$TMP_INDEX" || {
    echo "archive-with-index.sh: cannot read existing index: $INDEX — NOT moving $FILE" >&2
    exit 1
  }
else
  printf '%s\n' "$INDEX_HEADER" > "$TMP_INDEX" || {
    echo "archive-with-index.sh: cannot write index header — NOT moving $FILE" >&2
    exit 1
  }
fi

printf '%s\n' "$ROW" >> "$TMP_INDEX" || {
  echo "archive-with-index.sh: cannot append index row — NOT moving $FILE" >&2
  exit 1
}

mkdir -p "$DEST_DIR" || {
  echo "archive-with-index.sh: cannot create $DEST_DIR — index unchanged, $FILE not moved" >&2
  exit 1
}

if ! mv "$FILE" "$DEST"; then
  echo "archive-with-index.sh: move failed — index unchanged, $FILE not moved" >&2
  exit 1
fi

# Last step, and the only one after the file has moved. If it does not land, the
# file goes back where it came from, so the pair stays consistent either way.
#
# The POSTCONDITION is checked, not just mv's exit status, because mv can succeed
# while doing the wrong thing: if $INDEX is a directory, `mv tmp "$INDEX"` moves
# the staged file INTO it and returns 0, leaving the archive populated and the
# index never written — a silent instance of exactly the state this script exists
# to prevent. Asserting "$INDEX is now a regular file containing our row" is the
# condition we actually care about, and unlike a bare exit-status check it is
# inducible in a test.
index_committed() {
  [ -f "$INDEX" ] && grep -qF "$ROW" "$INDEX"
}

if ! mv "$TMP_INDEX" "$INDEX" 2>/dev/null || ! index_committed; then
  echo "archive-with-index.sh: index commit failed — rolling back the move" >&2
  mv "$DEST" "$FILE" || echo "archive-with-index.sh: ROLLBACK ALSO FAILED — $FILE is at $DEST and unindexed" >&2
  exit 1
fi

trap - EXIT
printf 'archived  %s -> %s\n' "$FILE" "$DEST"
printf 'indexed   %s (decision marker: %s)\n' "$INDEX" "$HAS_MARKER"
