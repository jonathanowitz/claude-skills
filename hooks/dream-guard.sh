#!/usr/bin/env bash
# dream-guard.sh — the two questions asked before any dream job is allowed to act.
#
# C8 (freshness) and C10 (duplicate PR) from the brief. One script, two
# subcommands, because they are one concern — "may this job run tonight?" — and
# splitting them would mean two deploy steps and two chances for only one to be
# on the path. (`deploy-hooks.sh` is a manual per-file copy; hooks/ is NOT
# symlinked to ~/.claude/hooks/, so every extra file is an extra way to ship a
# guard that never runs.)
#
# NEITHER SUBCOMMAND TOUCHES THE NETWORK. Same constraint that shaped
# tmp-scan.sh: `gh` does not exist in the routine sandbox (verified 2026-07-24,
# `which gh` exits 1), and the GitHub MCP connector is callable only by a model,
# never from inside a script. So the open-PR list is INJECTED by the caller —
# /dream night gets it from the MCP connector, a local run gets it from `gh`.
# Freshness needs no network at all: it reads git.
#
# EXIT STATUS IS NOT THE VERDICT — always 0 on a successful evaluation, even for
# a skip. This runs inside a `set -e` pipeline where a non-zero "skip this job"
# is indistinguishable from a crash and would take the rest of the night with it.
# Read `decision` from the output. Exit 2 = usage error.
#
# Usage:
#   dream-guard.sh freshness --repo-root=<dir> --file=<path> [--file=<path>...]
#                            [--window-hours=4] [--now=<epoch>]
#   dream-guard.sh duplicate --job=<slug> [--open-prs=<slug>=<num>,...]
set -euo pipefail

MODE="${1:-}"
shift || true

REPO_ROOT=""
FILES=""
WINDOW_HOURS=4
NOW=""
JOB=""
OPEN_PRS=""

for arg in "$@"; do
  case "$arg" in
    --repo-root=*)    REPO_ROOT="${arg#*=}" ;;
    --file=*)         if [ -z "$FILES" ]; then FILES="${arg#*=}"; else FILES="$FILES
${arg#*=}"; fi ;;
    --window-hours=*) WINDOW_HOURS="${arg#*=}" ;;
    --now=*)          NOW="${arg#*=}" ;;
    --job=*)          JOB="${arg#*=}" ;;
    --open-prs=*)     OPEN_PRS="${arg#*=}" ;;
    *) echo "dream-guard.sh: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

json_escape() {
  printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

emit() { # emit <decision> <reason> [extra-json-fields]
  local extra=""
  [ -n "${3:-}" ] && extra=",$3"
  printf '{"guard":"%s","decision":"%s","reason":"%s"%s}\n' \
    "$MODE" "$1" "$(json_escape "$2")" "$extra"
}

case "$MODE" in

  # --- C8 ---------------------------------------------------------------------
  # Skip any job whose target was COMMITTED in the last N hours, so dream never
  # collides with work a live session is still in the middle of.
  #
  # COMMIT TIME, NOT MTIME (KD-12). `git clone` stamps every file with checkout
  # time, so an mtime-based guard in a fresh cloud clone reads every file as
  # "modified seconds ago" and skips every job forever — while the report still
  # says it ran. Confirmed live in the routine sandbox on 2026-07-24 and again
  # 2026-07-25: README.md's fs mtime was ~9 days newer than its last commit and
  # within 80s of "now", twice.
  #
  # THE WINDOW IS 4h, NOT 24h, ON PURPOSE. USER works most days; a 24h guard
  # would mean the prune never runs at all — a guard that looks prudent and
  # silently does nothing. At 02:00 a 4h window still covers a session running
  # into the small hours.
  freshness)
    [ -n "$REPO_ROOT" ] || { echo "dream-guard.sh freshness: --repo-root is required" >&2; exit 2; }
    [ -n "$FILES" ]     || { echo "dream-guard.sh freshness: at least one --file is required" >&2; exit 2; }
    case "$WINDOW_HOURS" in
      ''|*[!0-9]*) echo "dream-guard.sh freshness: --window-hours must be a non-negative integer" >&2; exit 2 ;;
    esac
    [ -n "$NOW" ] || NOW=$(date +%s)
    case "$NOW" in
      ''|*[!0-9]*) echo "dream-guard.sh freshness: --now must be an epoch integer" >&2; exit 2 ;;
    esac

    WINDOW_SECS=$(( WINDOW_HOURS * 3600 ))
    newest=0
    newest_file=""
    untracked=""

    while IFS= read -r f; do
      [ -n "$f" ] || continue
      ct=$(git -C "$REPO_ROOT" log -1 --format=%ct -- "$f" 2>/dev/null || true)
      if [ -z "$ct" ]; then
        # No commit history. Either brand new or untracked — both mean "someone
        # is working on this right now", and neither can be PROVEN old. Fail
        # safe: a wrong skip costs a report line, a wrong run costs a collision.
        if [ -z "$untracked" ]; then untracked="$f"; else untracked="$untracked, $f"; fi
        continue
      fi
      if [ "$ct" -gt "$newest" ]; then newest="$ct"; newest_file="$f"; fi
    done <<EOF
$FILES
EOF

    if [ -n "$untracked" ]; then
      emit "skip" "no commit history for: $untracked — cannot prove it is untouched" \
        "\"untracked\":\"$(json_escape "$untracked")\""
      exit 0
    fi

    age_secs=$(( NOW - newest ))
    [ "$age_secs" -lt 0 ] && age_secs=0
    age_hours=$(( age_secs / 3600 ))

    if [ "$age_secs" -lt "$WINDOW_SECS" ]; then
      emit "skip" "$(basename "$newest_file") was committed ${age_hours}h ago, inside the ${WINDOW_HOURS}h window" \
        "\"newest_file\":\"$(json_escape "$newest_file")\",\"age_hours\":$age_hours,\"window_hours\":$WINDOW_HOURS"
    else
      emit "run" "newest target committed ${age_hours}h ago, outside the ${WINDOW_HOURS}h window" \
        "\"newest_file\":\"$(json_escape "$newest_file")\",\"age_hours\":$age_hours,\"window_hours\":$WINDOW_HOURS"
    fi
    ;;

  # --- C10 --------------------------------------------------------------------
  # The scan is deterministic, so an unmerged PR means tomorrow night finds the
  # same violation and opens an identical second PR. Four days away from the
  # keyboard = four duplicate PRs per job.
  #
  # This is not hypothetical any more. The 2026-07-25 06:07 UTC unattended firing
  # of the spike routine hit exactly this case: the branch and PR from the
  # previous run already existed. The model chose, on its own, to comment on the
  # open PR rather than force-push or duplicate — the right call, and the reason
  # nothing was corrupted. But that was a judgment made at 2 AM by a model with
  # no instruction covering it, and judgment is not a guarantee. This subcommand
  # makes the same outcome mechanical (KD-7).
  #
  # Matching is by JOB SLUG, which is also the branch name (`dream/<slug>`), not
  # by target file: the slug is a stable identifier dream itself controls, while
  # file lists drift between the scan and the PR. Unknown slug = no open PR = run.
  duplicate)
    [ -n "$JOB" ] || { echo "dream-guard.sh duplicate: --job is required" >&2; exit 2; }

    # bash 3.2 on macOS has no associative arrays, so this is a string scan —
    # same idiom as tmp-scan.sh's issue_state().
    case ",$OPEN_PRS," in
      *",$JOB="*)
        pr=$(printf '%s' "$OPEN_PRS" | tr ',' '\n' | grep "^$JOB=" | head -1)
        num="${pr#*=}"
        emit "skip" "PR #$num is already open for job '$JOB' — not opening a duplicate" \
          "\"job\":\"$(json_escape "$JOB")\",\"open_pr\":\"$(json_escape "$num")\""
        ;;
      *)
        emit "run" "no open dream PR for job '$JOB'" \
          "\"job\":\"$(json_escape "$JOB")\",\"open_pr\":null"
        ;;
    esac
    ;;

  ""|-h|--help)
    sed -n '2,30p' "${BASH_SOURCE[0]}"
    [ -z "$MODE" ] && exit 2
    exit 0
    ;;
  *)
    echo "dream-guard.sh: unknown subcommand: $MODE (expected freshness|duplicate)" >&2
    exit 2
    ;;
esac
