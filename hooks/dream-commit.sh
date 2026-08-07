#!/usr/bin/env bash
# dream-commit.sh — put one dream job's work on its own branch and push it.
#
# Slice 2. THIS IS THE ONLY SCRIPT IN DREAM ALLOWED TO WRITE TO GIT, and that is
# a containment decision, not an accident of layout. The other five
# (tmp-scan, check-doc-threshold, archive-with-index, dream-guard, dream-report)
# are pure functions of (files, time source, injected state), and tests/dream's
# V16 greps all five for git write verbs and asserts there are none. Arming the
# pipeline therefore lands here rather than by loosening V16, so "which file may
# push" stays a one-line grep instead of a judgment. tests/dream-commit's V27
# greps THIS file for the verbs it is still not allowed: no force-push, no
# unscoped `git add`, no `reset --hard`, no `gh`, no network client, no MCP tool.
#
# IT STOPS AT A PUSHED BRANCH. Opening the PR is deliberately not in scope:
# `gh` does not exist in the routine sandbox (`which gh` exits 1, verified
# 2026-07-24) and the GitHub MCP connector is callable only by a model, never
# from inside a script. The caller pushes with this, then opens the PR itself.
#
# THE PATH LIST IS A FENCE, NOT A HINT. Every path the job intends to touch is
# declared, and a working tree carrying anything outside that list is a hard
# refusal — the job is skipped and reported, never committed "helpfully". This
# is the mechanical form of the explicit-path-list rule, and that rule was
# earned: on 2026-04-28 an agent given "don't touch unrelated files" as intent
# ran a broad `git commit` and committed everything in the worktree. At 2 AM
# there is nobody to notice. `git add -A` with no pathspec is unreachable from
# here.
#
# IT ALWAYS FREES THE CHECKOUT. On the way out — success or failure — HEAD is
# back at the detached base. That is what makes one-small-PR-per-job (KD-3)
# mechanically possible: job B must branch from origin/main, not from job A's
# branch. A run that left HEAD on the first job's branch would stack every later
# job on top of it and produce exactly the nightly omnibus the brief refuses.
#
# The local branch goes with it in every case BUT ONE: a push that failed after
# the commit landed. There the branch is KEPT, because deleting it would leave
# the commit reachable only through the reflog of a container about to be
# destroyed. A push can fail for reasons having nothing to do with this run, and
# the right outcome is a failed job whose work is still inspectable — not a
# silent shred. Pinned by V28, which was invisible to every other test in the
# suite because they all push to a local bare repo, where push does not fail.
#
# TWO FENCES, AND NEITHER OF THEM IS THE GUARANTEE — the commit command is. The
# pre-stage fence checks the whole working tree and refuses if anything
# undeclared changed. The post-stage assertion checks what the commit will
# actually change and refuses if a declared pathspec expanded somewhere
# unexpected. What makes an undeclared path unable to reach the commit AT ALL is
# `git commit --only -- <declared paths>`, which builds the commit from HEAD plus
# the index entries for those paths and disregards everything else staged.
#
# Both of those used to read the whole index instead, and that was the round-12
# blocker: `git checkout -b` carries index state forward, so work staged before a
# job ran was committed by it and refused by the assertion — while
# --allow-unrelated-changes drops only the WORKING-TREE fence. The one job that
# must always ship was stoppable by a stale index, which is precisely the
# outcome that flag exists to prevent.
#
# --allow-unrelated-changes exists for exactly one caller: the nightly report.
# The pre-stage fence is repo-wide, so a tmp-sweep job that refused leaves its
# half-applied mutation in the tree and every later job in that repo — including
# the report — refuses too. That makes the one job that must always ship (KD-6: a
# missing report is the alarm) the one job that structurally cannot, and it
# converts "a job was skipped" into "the routine died". The report loses nothing
# by skipping the fence, because `--only` still holds: its commit can contain
# nothing but the report file. Every skipped-over path is named on stderr so the
# run stays honest.
# (Found by cross-model review, 2026-07-29 and 2026-07-30; both reproduced first.)
#
# Usage:
#   dream-commit.sh --repo-root=<dir> --job=<slug> --base=<sha> --message=<text>
#                   --path=<repo-relative>... [--remote=origin] [--dry-run]
#                   [--allow-unrelated-changes]
#
# Exit status: 0 = pushed (or planned, under --dry-run); 2 = usage error, before
# anything was touched; 1 = refused or failed. A 1 USUALLY means the repo was
# restored, and deliberately does not promise it: the `checkout_freed` field
# reports that, and the one path where it is false — HEAD stranded, the run over
# for that repo — exits 1 after a SUCCESSFUL push. Read the JSON, not the status.
set -uo pipefail

REPO_ROOT=""
JOB=""
BASE=""
MESSAGE=""
REMOTE="origin"
DRY_RUN=0
ALLOW_UNRELATED=0
PATHS=""
# Whether the caller has been told anything machine-readable yet. The EXIT trap
# uses it to avoid emitting a second, contradictory JSON line on paths that
# already reported.
EMITTED=0

usage() { echo "dream-commit.sh: $1" >&2; exit 2; }

for arg in "$@"; do
  case "$arg" in
    --repo-root=*) REPO_ROOT="${arg#*=}" ;;
    --job=*)       JOB="${arg#*=}" ;;
    --base=*)      BASE="${arg#*=}" ;;
    --message=*)   MESSAGE="${arg#*=}" ;;
    --remote=*)    REMOTE="${arg#*=}" ;;
    --dry-run)     DRY_RUN=1 ;;
    --allow-unrelated-changes) ALLOW_UNRELATED=1 ;;
    --path=*)
      # Checked HERE, on the raw argv element, because PATHS is a
      # newline-joined list: a path containing a newline would arrive intact and
      # then split into two half-paths downstream, each of which could look
      # coverable to the fence while the real file went unstaged. By the time
      # the validation loop below reads the list back, the evidence is gone.
      # $'\n', NOT "$(printf '\n')" — command substitution strips trailing
      # newlines, so the latter yields the EMPTY STRING and the pattern degrades
      # to *""*, which matches every path. A validation that always fires and a
      # validation that never fires are both invisible in a green suite; this
      # one announced itself by rejecting the happy path.
      case "${arg#*=}" in
        *$'\n'*) usage "--path may not contain a newline" ;;
      esac
      if [ -z "$PATHS" ]; then PATHS="${arg#*=}"; else PATHS="$PATHS
${arg#*=}"; fi ;;
    *) usage "unknown argument: $arg" ;;
  esac
done

[ -n "$REPO_ROOT" ] || usage "--repo-root is required"
[ -n "$JOB" ]       || usage "--job is required"
[ -n "$BASE" ]      || usage "--base is required"
[ -n "$MESSAGE" ]   || usage "--message is required"
[ -n "$PATHS" ]     || usage "at least one --path is required"

# --- the branch namespace cannot be escaped (KD-2) ------------------------------
# "PR, never commit to main" was identified as THE anti-pattern across every
# shipped implementation researched, so it is enforced by construction: the
# branch is always `dream/<slug>` and the slug alphabet cannot express a path
# traversal, a ref namespace, or shell syntax. A date suffix IS legitimate —
# the nightly report needs `report-YYYY-MM-DD` so that yesterday's unmerged
# report PR cannot suppress today's report through the duplicate guard, which
# would suppress the KD-6 alarm along with it.
case "$JOB" in
  main|master|HEAD) usage "--job may not be '$JOB' — dream never writes to the default branch" ;;
esac
# AN ENUMERATED ALPHABET, because neither of the two shorter spellings holds on
# both platforms. A glob RANGE like [a-z] is collation-ordered and can interleave
# case. A character CLASS fixes that and introduces the other half: class
# membership is locale-dependent too, so [[:lower:]] admits é, ß and Cyrillic
# lowercase — `--job=café` produced branch `dream/café`, which reintroduces
# exactly the case-sensitivity mismatch with git's ref store on macOS that the
# class was chosen to avoid. And LC_ALL=C does not rescue it here: probed on
# bash 3.2/macOS, `café` passes BOTH the class and a bare [0-9a-f] range even
# under C. Listing the characters is the only spelling that rejected every
# non-ASCII and uppercase probe on macOS and glibc, in C and in the default
# locale. (Found by cross-model review, 2026-07-30; its uppercase-collation case
# did not reproduce on either platform, the non-ASCII one did.)
JOB_ALPHABET='abcdefghijklmnopqrstuvwxyz0123456789-'
case "$JOB" in
  *[!$JOB_ALPHABET]*) usage "--job must be lowercase [a-z0-9-] only, got: $JOB" ;;
  -*|*-)                    usage "--job may not start or end with a hyphen, got: $JOB" ;;
esac
BRANCH="dream/$JOB"

# THE ESCAPE HATCH IS FENCED TO THE JOB IT WAS ARGUED FOR. The header says it
# "exists for exactly one caller: the nightly report" and dream.md says it
# "belongs on this job and on no other" — and both were prose while any --job
# could pass the flag. The blast radius is small, since `commit --only` bounds
# the diff regardless, but this file's whole thesis is that a rule kept by
# intention is a rule that fails at 2 AM with nobody watching. The slug alphabet
# is already validated above, so the check is one case.
# (Found by cross-model review, 2026-07-30.)
if [ "$ALLOW_UNRELATED" = 1 ]; then
  case "$JOB" in
    report-*) ;;
    *) usage "--allow-unrelated-changes is for the nightly report job only, got: $JOB" ;;
  esac
fi

# --- every commit carries an issue reference ------------------------------------
# A hard project requirement, and an unattended generator is exactly where it
# would rot silently. Checked at the argument so a bad message never reaches a
# branch, rather than at review time when the branch already exists.
# --- the remote name is an argument too -----------------------------------------
# It reaches `git remote get-url`, `git ls-remote` and `git push` as a bare
# positional, so a name beginning with a hyphen is parsed as an option. Every
# other caller-supplied value here is validated at parse time; this one was
# reaching git on trust. A guard rather than a `--` delimiter, to match the
# file's idiom — and because `--` is not uniformly accepted across these three.
# Validated to a NAME, not merely to "not obviously hostile". This is the one
# caller-supplied value that reaches emit() without an alphabet — --job, --path
# and --base all have one — and it is a git remote name, which has no business
# containing whitespace or control characters. Two negative cases were the whole
# guard; a positive alphabet is the same thing said in the direction that cannot
# miss a case. (Found by cross-model review, 2026-07-29.)
REMOTE_ALPHABET='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-'
case "$REMOTE" in
  "")                            usage "--remote may not be empty" ;;
  -*)                            usage "--remote may not start with a hyphen, got: $REMOTE" ;;
  # Enumerated for the same reason as --job: [[:alnum:]] admits non-ASCII letters
  # under a UTF-8 locale. A bad name still has to survive `git remote get-url`
  # below, so this is the outermost of two guards rather than the only one.
  *[!$REMOTE_ALPHABET]*)         usage "--remote must be a git remote name ([A-Za-z0-9._/-]), got: $REMOTE" ;;
esac

# [1-9], not [0-9]: there is no issue #0, so `#0` is never a reference and a glob
# can at least exclude it. What a glob cannot exclude is an ordinal — "tidy #2 of
# the tmp dir" satisfies this and cites nothing. That is a weak commit message
# rather than a bad diff, and these messages are generated from a template that
# interpolates the finding's issue, so the guard is a backstop against the
# template drifting rather than a parser. (Found by cross-model review, 2026-07-29.)
case "$MESSAGE" in
  *"#"[1-9]*) ;;
  *) usage "--message must carry a #NN issue reference, got: $MESSAGE" ;;
esac

# --- paths must be repo-relative and must not escape ----------------------------
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    /*)          usage "--path must be repo-relative, got absolute: $p" ;;
    -*)          usage "--path may not start with a hyphen: $p" ;;
    # A leading colon is git PATHSPEC MAGIC — `:(exclude)…` and `:!…` invert or
    # widen what `git add` matches. The post-stage assertion would still catch
    # anything it widened, and covered() matches literally so it would cover
    # nothing, but a fence argument that git reads as an operator rather than a
    # path has no business getting that far.
    :*)          usage "--path may not begin with ':' (git pathspec magic): $p" ;;
    ..|../*|*/..|*/../*) usage "--path may not escape the repo: $p" ;;
    .)           usage "--path may not be the whole repo" ;;
    # `./tmp/x` names the right file and can never be covered: git normalizes the
    # pathspec, so the post-stage assertion reads back `tmp/x` while covered()
    # compares the declared string literally. Fail-closed — but the refusal then
    # names a path the caller DID declare, which reads as the fence malfunctioning
    # rather than as a spelling to fix. Same class as the ':' and glob guards.
    # (Found by cross-model review, 2026-07-29.)
    ./*)         usage "--path must be plain repo-relative, without a leading './': $p" ;;
    # A path carrying a tab would corrupt the report's TSV records, and the
    # fence below joins paths with newlines — a path containing one would split
    # into two half-paths that each look coverable. Rejected at the argument
    # rather than escaped downstream: nothing dream archives needs one, and a
    # fence is not the place to be clever.
    *$'\t'*) usage "--path may not contain a tab: $p" ;;
    # A BACKSLASH IS AN ESCAPE TO ALMOST EVERYTHING THAT READS THIS LIST, and
    # the only reason it is not one HERE is a flag repeated on five loops.
    #
    # The rationale first written here — that a trailing `\` line-continues in
    # the unquoted heredocs and silently joins two declared paths — is FALSE.
    # Every consumer uses `while IFS= read -r`, and -r is precisely what disables
    # backslash processing. Probed both ways rather than re-reasoned: with -r the
    # paths stay separate; without it they join into `tmp/dirtmp/other.md`.
    # (Corrected after cross-model review, 2026-07-29 — the original comment
    # described an impossible failure, in a file that treats its comments as the
    # spec.)
    #
    # The guard stays for what is true: a backslash is safe here only because of
    # five `-r` flags whose loss nobody would notice, and the byte still has to
    # survive json_escape on its way into the report. An alphabet that excludes
    # it costs nothing and removes the dependency.
    *\\*) usage "--path may not contain a backslash: $p" ;;
    # Glob metacharacters, for a reason that IS live. `git add --all -- 'tmp/*'`
    # expands, while covered() matches literally — so the fence approves one
    # thing and the staging step does another. Fail-closed (the post-stage
    # assertion refuses whatever the glob pulled in), but the refusal would then
    # name a staged file the caller never declared, and a declared path is meant
    # to be a path. (Found by cross-model review, 2026-07-29.)
    *"*"*|*"?"*|*"["*) usage "--path may not contain a glob metacharacter: $p" ;;
  esac
done <<EOF
$PATHS
EOF
case "$PATHS" in
  *$'\r'*) usage "--path may not contain a carriage return" ;;
esac

git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || usage "not a git repository: $REPO_ROOT"

# --repo-root must be the TOPLEVEL, not a subdirectory of the repo. `git status`
# reports paths relative to the toplevel while `git add` resolves a pathspec
# relative to the cwd, so from a subdirectory the fence would be comparing two
# different coordinate systems. The mismatch fails safe (everything reads as
# outside the declared list, and the job refuses) but it fails CONFUSINGLY, and
# a guard whose diagnostics lie is most of the way to a guard nobody trusts.
TOPLEVEL=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$TOPLEVEL" ] || usage "cannot resolve the repository toplevel from: $REPO_ROOT"
[ "$(git -C "$REPO_ROOT" rev-parse --show-prefix)" = "" ] \
  || usage "--repo-root must be the repository toplevel ($TOPLEVEL), got a subdirectory: $REPO_ROOT"

git -C "$REPO_ROOT" remote get-url "$REMOTE" >/dev/null 2>&1 \
  || usage "no such remote '$REMOTE' in $REPO_ROOT"

g() { git -C "$REPO_ROOT" "$@"; }

refuse() { echo "dream-commit.sh: $1" >&2; exit 1; }

# Tabs are escaped, not passed through: a literal tab inside a JSON string is
# invalid JSON, and this output is parsed by the caller that builds the report's
# TSV records — where a stray tab would also shift every field after it.
#
# AND EVERY OTHER CONTROL BYTE IS STRIPPED, rather than trusted not to arrive.
# The upstream argument validation does reject newline, CR and tab — but the
# premise of the whole fence is that pathological names reach it (V29), the
# alphabet checks live 200 lines away from here, and a control byte that slips
# through produces invalid JSON, which the caller cannot parse into a report at
# all. That turns one bad filename into a missing report, which KD-6 reads as
# the routine having died. Escaping is a claim about this function; stripping is
# a guarantee. (Found by cross-model review, 2026-07-29.)
json_escape() {
  # \000-\010, then \012-\037, then \177: everything below space EXCEPT \011,
  # which the sed below escapes as \t. The first version of this range also
  # skipped \012 (LF) and \015 (CR) — carried over from "newline and CR are
  # rejected at the argument", which is precisely the reliance on unreachability
  # the paragraph above says this is not doing. A guarantee with two holes in it
  # is a claim. (Found by cross-model review, 2026-07-29.)
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\010\012-\037\177' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/'"$(printf '\t')"'/\\t/g'
}

# --- the base assertion (KD-13) -------------------------------------------------
# Every finding in tonight's report is a claim about the SHA Phase 0 recorded.
# If HEAD has moved since the scan, this commit would be built on a state nobody
# scanned, and the PR could not be traced back to the state it was computed
# against — which is the entire reason the report records SHAs per repo.
#
# The prefix match below is what lets a caller pass an abbreviated SHA, so the
# value has to be validated as a SHA first. Unvalidated, `--base=0` matches
# roughly one HEAD in sixteen, and a truncated or template-mangled value passes
# silently — turning the assertion that exists to prove we are on the scanned
# commit into one that sometimes proves nothing. Seven is git's own default
# abbreviation length.
# Lowercase only. `git rev-parse` always emits lowercase and the assertion below
# is a literal prefix match, so accepting A-F here would let an uppercase base
# fail with "HEAD has moved since the scan" — sending the reader off to hunt a
# concurrent commit that never happened. This file's own reasoning a few lines
# up says a guard whose diagnostics lie is most of the way to a guard nobody
# trusts; that applies to its own.
# Enumerated, for the reason spelled out at the --job guard: this was the last
# bare collation-ordered RANGE in the file, and on bash 3.2/macOS `café` passes
# [0-9a-f] even under LC_ALL=C.
case "$BASE" in
  *[!0123456789abcdef]*) usage "--base must be a lowercase hex SHA, got: $BASE" ;;
esac
[ "${#BASE}" -ge 7 ] || usage "--base must be at least 7 hex characters, got: $BASE"
# 64, not 40: a SHA-256 repo produces 64-character SHAs, and --base is always
# `git rev-parse HEAD` from the same repo this then runs against, so the two
# would migrate together and a 40-cap would reject every run on day one. The
# floor and the lowercase-hex check are correct for both formats.
[ "${#BASE}" -le 64 ] || usage "--base must be at most 64 hex characters, got: $BASE"

HEAD_SHA=$(g rev-parse HEAD 2>/dev/null) || refuse "cannot resolve HEAD in $REPO_ROOT"

# HEAD MUST ALREADY BE DETACHED. Phase 0 always leaves it that way, so this
# costs the nightly run nothing — but `/dream` is an ordinary slash command and
# can be invoked on a laptop, where restore() would hand the operator their own
# checkout back in detached HEAD without ever having said so. Refusing up front
# is also a cleaner statement of the Phase 0 contract than restoring a ref this
# script never owned.
if g symbolic-ref -q HEAD >/dev/null 2>&1; then
  refuse "HEAD is on branch '$(g rev-parse --abbrev-ref HEAD)' — dream operates from a detached checkout (Phase 0). Refusing rather than moving a branch somebody else owns."
fi

case "$HEAD_SHA" in
  "$BASE"*) ;;
  *) refuse "HEAD has moved since the scan — expected base $BASE, HEAD is $HEAD_SHA. Refusing to commit against a state nobody scanned." ;;
esac

# --- the fence ------------------------------------------------------------------
# Collected with -z so a path containing a space or a quote arrives intact rather
# than as git's C-quoted rendering, and with -uall so an untracked DIRECTORY is
# expanded into its files — porcelain otherwise reports `?? tmp/archive/` as one
# entry, and a fence that reasons about directories cannot tell which files are
# actually inside one.
# NUL IN, NUL OUT. Re-emitting these records newline-separated would undo the
# only reason -z was used: a repository file whose name contains a newline would
# split into two half-paths, and a fence that evaluates half-paths is not a
# fence. --path arguments are separately rejected if they contain one, so the
# two sides of every comparison below are whole paths.
# ASK GIT WHETHER IT COULD ANSWER, before believing that it answered "nothing".
# Both this and the post-stage diff are consumed through a pipe whose exit status
# nobody reads, so a corrupt index or an unreadable object yields zero records —
# indistinguishable from a clean tree. The job then refuses with "no change under
# the declared paths", blaming the path list for a fault in git, and refusals may
# never be worked around, so that message is the whole of a human's diagnosis.
# Fail-closed either way; the point is which failure it names.
# (Found by cross-model review, 2026-07-30.)
g status --porcelain -z -uall >/dev/null 2>&1 \
  || refuse "git cannot read the working tree in $REPO_ROOT — this is a git fault, not a path-list problem"

changed_paths() {
  local rec status p
  g status --porcelain -z -uall | {
    while IFS= read -r -d '' rec; do
      status="${rec:0:2}"
      p="${rec:3}"
      printf '%s\0' "$p"
      # Renames and copies carry their SOURCE as the next NUL record. Both ends
      # of a rename are a change, and a fence that only saw the destination
      # would let a job quietly delete a file it never declared. Consuming that
      # extra record is also mandatory for correctness, not just coverage: leave
      # it in the stream and every following record is read as a status/path
      # pair one position out of phase, so the fence mis-evaluates the whole
      # rest of the tree — a fence failure that reads as green. Pinned by V41.
      #
      # X only. In porcelain v1 the `R`/`C` codes are index statuses, so they
      # appear in the first column; `RM` (renamed, then modified in the worktree)
      # is the shape that made an earlier `*R|*C` alternative look necessary.
      # It never matched anything, and a pattern that cannot fire reads as
      # uncertainty about the format in the one loop that must not be uncertain.
      case "$status" in
        R*|C*) IFS= read -r -d '' rec && printf '%s\0' "$rec" ;;
      esac
    done
  }
}

# The declared list, parsed ONCE. covered() is called per changed path and again
# per staged path, and it used to re-read $PATHS through a heredoc every time —
# which on bash 3.2 (the macOS default, and what `#!/usr/bin/env bash` resolves
# to there) materializes a temp file per call. An indexed array is bash 3.2 and
# costs nothing. Trailing slashes are stripped here so covered() does not redo it
# on every comparison. (Found by cross-model review, 2026-07-29.)
DECLARED=()
while IFS= read -r _d; do
  [ -n "$_d" ] || continue
  DECLARED[${#DECLARED[@]}]="${_d%/}"
done <<EOF
$PATHS
EOF

covered() { # covered <path> — is it at or under a declared path?
  local target="$1" d
  for d in "${DECLARED[@]}"; do
    [ "$target" = "$d" ] && return 0
    case "$target" in "$d"/*) return 0 ;; esac
  done
  return 1
}

OUTSIDE=""
N_OUTSIDE=0
INSIDE=0
# Process substitution, not a pipe: a pipe would run this loop in a subshell and
# INSIDE/OUTSIDE would be discarded at the end of it, leaving the fence
# permanently reporting "nothing outside, nothing inside" — a guard that always
# passes and an empty-diff refusal on every job.
while IFS= read -r -d '' c; do
  [ -n "$c" ] || continue
  if covered "$c"; then
    INSIDE=$((INSIDE+1))
  else
    # CAPPED. The point of this list is for a human to read it in the report and
    # see what the tree was carrying. An un-ignored node_modules would make it a
    # multi-megabyte stderr line, which is not a longer version of that — it is
    # an unreadable one, and it would ride into the report and the PR body.
    N_OUTSIDE=$((N_OUTSIDE + 1))
    if [ "$N_OUTSIDE" -le 20 ]; then
      if [ -z "$OUTSIDE" ]; then OUTSIDE="$c"; else OUTSIDE="$OUTSIDE, $c"; fi
    fi
  fi
done < <(changed_paths)
if [ "$N_OUTSIDE" -gt 20 ]; then
  OUTSIDE="$OUTSIDE, … and $((N_OUTSIDE - 20)) more ($N_OUTSIDE undeclared paths in total)"
fi

if [ -n "$OUTSIDE" ] && [ "$ALLOW_UNRELATED" = 0 ]; then
  # The mutations are deliberately NOT reverted. Reverting would destroy both
  # this job's work and whatever the undeclared change was — cleaning up after a
  # guard by deleting the thing the guard was protecting.
  refuse "working tree carries changes outside the declared paths: $OUTSIDE — refusing to commit a wider diff than the job declared"
fi
if [ -n "$OUTSIDE" ]; then
  # --allow-unrelated-changes: proceed, but SAY what is being stepped over, so
  # the report can carry it and the reviewer of the resulting PR knows the tree
  # was not pristine.
  echo "dream-commit.sh: proceeding past unrelated working-tree changes (--allow-unrelated-changes): $OUTSIDE" >&2
fi

if [ "$INSIDE" -eq 0 ]; then
  # A PR with no diff is worse than no PR: it costs a review slot and teaches
  # the reviewer that dream PRs can be skimmed.
  refuse "nothing to commit for job '$JOB' — no change under the declared paths"
fi

# --- never re-use a branch that already exists ----------------------------------
# C10 (the duplicate-PR guard) is meant to catch this upstream, but C10 decides
# on state the MODEL injected via the MCP connector, and a stale or mis-mapped
# --open-prs list is a plausible 2 AM input. On 2026-07-25 the unattended run
# landed on exactly this collision. This is the backstop that makes the worst
# case a refused job rather than rewritten history on a branch under review.
if g show-ref --verify --quiet "refs/heads/$BRANCH"; then
  refuse "local branch $BRANCH already exists — refusing to reuse it"
fi
# `--exit-code` gives three distinct answers and they must not be collapsed:
# 0 = the branch exists, 2 = it does not, anything else = the remote could not
# be reached. Treating "unreachable" as "absent" would commit and then fail at
# push, landing in the preserved-branch path with a refusal message about the
# push when the real problem was the network — a diagnostic that sends the
# reader to the wrong place.
g ls-remote --exit-code --heads "$REMOTE" "$BRANCH" >/dev/null 2>&1
LS_RC=$?
case "$LS_RC" in
  0) refuse "$BRANCH already exists on $REMOTE — refusing to open a second commit on a branch already under review (never force-pushed)" ;;
  2) ;;
  *) refuse "cannot reach remote '$REMOTE' (git ls-remote exit $LS_RC) — refusing to commit work that cannot be pushed" ;;
esac

emit() { # emit <pushed> <commit-sha> <mode>
  # `base` is $HEAD_SHA, the FULL resolved SHA — deliberately, not the --base
  # argument, which the caller may have passed abbreviated. They denote the same
  # commit (the case above enforces it as a prefix match) but only one of them
  # is unambiguous in a report.
  local paths_json="" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -z "$paths_json" ]; then paths_json="\"$(json_escape "$p")\""
    else paths_json="$paths_json,\"$(json_escape "$p")\""; fi
  done <<EOF
$PATHS
EOF
  EMITTED=1
  printf '{"job":"%s","branch":"%s","base":"%s","commit":"%s","pushed":%s,"checkout_freed":%s,"remote":"%s","mode":"%s","paths":[%s]}\n' \
    "$(json_escape "$JOB")" "$(json_escape "$BRANCH")" "$HEAD_SHA" "$2" "$1" \
    "$([ "${FREED:-1}" = 1 ] && printf true || printf false)" \
    "$(json_escape "$REMOTE")" "$3" "$paths_json"
}

# --- dry run: everything above still ran, nothing below happens -----------------
# Slice 1's guarantee was cheap to hold when no code could push. Arming is
# exactly when it stops being free, so the dry run exits here — after every
# check, before the first mutation — and reports the real branch it would have
# created rather than a description of one.
if [ "$DRY_RUN" = 1 ]; then
  emit false "" dry-run
  exit 0
fi

# --- from here on the repo is being modified, so restore is guaranteed ----------
# INT and TERM as well as EXIT: an interrupt between the commit and the push
# would otherwise strand a local branch and leave HEAD off the base, and the
# next job in the same run would silently build on top of it.
COMMITTED=0
PUSHED=0
RESTORED=0
FREED=1
RESTORE_DONE=0
EXPECT_NO_BRANCH=0
restore() {
  # ONCE, AND ONLY ONCE. The INT/TERM handler below exits, which then fires the
  # EXIT trap — so without this guard restore runs twice on every signal, and
  # the second pass reads flags the first pass already acted on.
  [ "$RESTORED" = 1 ] && return 0
  RESTORED=1

  # WAIT FOR THE REPO TO GO QUIET BEFORE TOUCHING IT. On a signal, bash does not
  # wait for the running git child — it interrupts its own wait and runs this
  # handler immediately, leaving that child alive and still writing. Restoring
  # into an in-flight `git commit` loses the fight twice over: the checkout and
  # the branch delete fail on the held index.lock, and then the commit lands
  # AFTER this function has already inspected HEAD and declared the outcome. The
  # observed result was HEAD stranded on a commit whose branch had just been
  # deleted — a dangling commit, reported by a message written before it existed.
  # (Found by V34, 2026-07-29; the FREED check below caught the symptom, but a
  # loud alarm on a race is worse than not racing.)
  #
  # Bounded, because a wedged git must not hang the nightly: ~30s, then restore
  # anyway and let the FREED verification report whatever it finds. A git killed
  # with SIGKILL leaves index.lock on disk forever, so the bound is what turns
  # that from a hang into the loud alarm below plus a one-line human fix.
  #
  # The bound is overridable ONLY so the FREED=0 path can be tested — reaching it
  # otherwise means waiting the full 30s in a suite run twice per change. That
  # path is documented as ending the run for a whole repo and requiring hand
  # resolution, which makes "untested" the wrong thing for it to be; this file's
  # own standard is that a guard nobody exercises is prose. The default is
  # unchanged for every real caller. (Found by cross-model review, 2026-07-29.)
  # Validated, because an unvalidated knob degrades the wrong way: under
  # `set -uo pipefail` with no `-e`, a non-numeric value makes `[` error on every
  # iteration and the loop silently evaporates — the test-only override becoming
  # "no wait at all" in production without saying a word.
  LOCK_WAIT_DS="${DREAM_COMMIT_LOCK_WAIT_DS:-300}"
  # `0` is numeric and therefore passed the validation, and `while [ "$Q" -lt 0 ]`
  # never iterates — the "no wait at all" degradation this paragraph exists to
  # prevent, reachable one value over from the case that catches it.
  # (Found by cross-model review, 2026-07-30.)
  case "$LOCK_WAIT_DS" in
    ""|*[!0-9]*) LOCK_WAIT_DS=300 ;;
  esac
  [ "$LOCK_WAIT_DS" -ge 1 ] || LOCK_WAIT_DS=300
  GIT_DIR_ABS=$(g rev-parse --absolute-git-dir 2>/dev/null || echo "")
  if [ -n "$GIT_DIR_ABS" ]; then
    Q=0
    while [ "$Q" -lt "$LOCK_WAIT_DS" ] && [ -e "$GIT_DIR_ABS/index.lock" ]; do
      Q=$((Q + 1)); sleep 0.1
    done
  fi
  # Re-read the flags' subject rather than trusting the pre-signal snapshot: if
  # the interrupted commit completed during the quiesce above, COMMITTED is
  # still 0 while a commit now exists, and the `else` branch would delete the
  # branch holding it. Ask git what is actually there.
  if [ "$COMMITTED" = 0 ] && g rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null 2>&1; then
    if [ "$(g rev-parse "refs/heads/$BRANCH" 2>/dev/null)" != "$HEAD_SHA" ]; then
      COMMITTED=1
      echo "dream-commit.sh: interrupted after the commit landed — treating it as committed." >&2
    fi
  fi

  # And the same question for PUSHED, for the same reason one window later.
  # `PUSHED=1` is a statement AFTER the push command, so a signal arriving during
  # a push that then SUCCEEDS runs this handler with PUSHED still 0 — and the
  # branch-preserving arm below would announce "the commit is preserved on local
  # branch" for a branch that is already on the remote. The caller records a
  # skip, no PR is ever opened for it, and every subsequent night refuses
  # permanently on "already exists on $REMOTE". A silent, self-perpetuating dead
  # branch is the worst outcome this file can produce.
  #
  # ASKED LOCALLY, NOT OVER THE NETWORK. The obvious source of truth is
  # `git ls-remote`, and putting it here would be its own bug: the likeliest
  # reason this handler is running at all is a SIGTERM sent because the push HUNG
  # on a network fault, and a cleanup path that then blocks on the same network
  # gets SIGKILLed mid-restore — losing the checkout-freeing guarantee at exactly
  # the moment it matters. A successful `git push` updates the remote-tracking
  # ref locally, even with an explicit refspec and no `-u` (verified), so the
  # answer is already on disk. A remote configured without a fetch refspec leaves
  # PUSHED=0, which preserves the branch — safe for the WORK, and not safe for
  # the job: the branch is on the remote either way, so the next night refuses on
  # "already exists" and that job is dead until a human looks. `git remote add`
  # always writes a fetch refspec, so this is a misconfiguration rather than a
  # shape dream produces; naming it here so a future reader does not read "safe
  # direction" as "no consequence".
  # (Both halves found by cross-model review, 2026-07-29.)
  if [ "$COMMITTED" = 1 ] && [ "$PUSHED" = 0 ]; then
    LOCAL_SHA=$(g rev-parse "refs/heads/$BRANCH" 2>/dev/null || echo "")
    TRACK_SHA=$(g rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH" 2>/dev/null || echo "")
    if [ -n "$LOCAL_SHA" ] && [ "$LOCAL_SHA" = "$TRACK_SHA" ]; then
      PUSHED=1
      echo "dream-commit.sh: interrupted after the push completed — the branch is on $REMOTE." >&2
    fi
  fi

  g checkout -q --detach 2>/dev/null || true
  if [ "$COMMITTED" = 1 ] && [ "$PUSHED" = 0 ]; then
    # A commit exists. HEAD goes back to the base so the NEXT job still branches
    # from origin/main rather than stacking on this one — that is the whole
    # point of restoring, and leaving HEAD here would build the nightly omnibus
    # KD-3 refuses. The tree is clean at this point, so a plain checkout is
    # enough; `reset --hard` is not used and V27 asserts it never appears,
    # because this runs against a real checkout when /dream is invoked locally.
    g checkout -q --detach "$HEAD_SHA" 2>/dev/null || true
    # THE BRANCH IS KEPT, DELIBERATELY. Deleting it here would leave the commit
    # dangling — reachable only through the reflog, in a container that is about
    # to be destroyed. A push can fail for reasons that have nothing to do with
    # this run (network, a ref that moved under us), and the correct outcome is
    # a failed job whose work is still inspectable, not a silent shred. The
    # branch is named in the refusal so it can be found.
    echo "dream-commit.sh: the commit is preserved on local branch $BRANCH" >&2
  else
    # Either nothing was committed — nothing to preserve — or the push
    # succeeded and the commit is safely on the remote. Both cases want the
    # local branch gone: a leftover would collide with tomorrow's run and
    # refuse it.
    if [ "$COMMITTED" = 1 ]; then
      g checkout -q --detach "$HEAD_SHA" 2>/dev/null || true
    else
      # Scoped to the declared paths. A bare `git reset` is a repo-wide mixed
      # reset that would unstage a human's pre-staged work — unreachable behind
      # the default fence, but reachable under --allow-unrelated-changes, which
      # is precisely the flag that exists to tolerate a tree we did not stage.
      while IFS= read -r rp; do
        [ -n "$rp" ] || continue
        g reset -q -- "$rp" 2>/dev/null || true
      done <<EOF
$PATHS
EOF
    fi
    g branch -q -D "$BRANCH" 2>/dev/null || true
    EXPECT_NO_BRANCH=1
  fi

  # EVERY checkout above is `|| true`, so without this the header's promise that
  # the checkout is always freed would be an intention rather than a guarantee:
  # a failed checkout leaves HEAD on the job's branch, the script exits with
  # whatever status it had, and the NEXT job branches from dream/<slug> —
  # building the stacked omnibus KD-3 refuses, silently, at 2 AM. Say it loudly
  # instead, and report it in the JSON so the caller can stop.
  # BOTH HALVES: the right commit AND detached. Checking the SHA alone was not
  # enough — `checkout -b` creates the job branch AT the base, so a run that
  # refused before committing leaves HEAD on dream/<slug> pointing at exactly
  # $HEAD_SHA, and a SHA-only comparison calls that freed. It is not: the next
  # job then branches from dream/<slug> and stacks, which is the whole failure
  # this verification exists to catch, passing its own check. (Found while
  # building V43's fixture, 2026-07-29 — the fixture could not turn the alarm on
  # because the alarm was looking at the wrong thing.)
  # AND THE THIRD HALF: the branch delete is `|| true` like every checkout, and
  # went unverified while the two above it were checked. A surviving dream/<slug>
  # is the same failure one step over — the next run's `checkout -b` refuses on
  # it, forever, while this run's JSON says the checkout was freed and the caller
  # records an ordinary skip. Only asserted where deletion was INTENDED: a push
  # that failed after the commit landed keeps the branch on purpose, and calling
  # that a failure would turn the one path built to preserve work into an alarm.
  # (Found by cross-model review, 2026-07-29 — the same class the SHA-only check
  # was already found to be, which is the argument for checking it.)
  FINAL_SHA=$(g rev-parse HEAD 2>/dev/null || echo "")
  FINAL_REF=$(g symbolic-ref -q --short HEAD 2>/dev/null || echo "")
  LEFTOVER=0
  if [ "$EXPECT_NO_BRANCH" = 1 ] \
     && g rev-parse --verify -q "refs/heads/$BRANCH" >/dev/null 2>&1; then
    LEFTOVER=1
  fi
  if [ "$FINAL_SHA" != "$HEAD_SHA" ] || [ -n "$FINAL_REF" ] || [ "$LEFTOVER" = 1 ]; then
    FREED=0
    WHERE="$FINAL_SHA"
    [ -n "$FINAL_REF" ] && WHERE="branch $FINAL_REF ($FINAL_SHA)"
    [ "$LEFTOVER" = 1 ] && WHERE="$WHERE, and local branch $BRANCH could not be deleted"
    echo "dream-commit.sh: FAILED TO FREE THE CHECKOUT — HEAD is $WHERE, expected detached at $HEAD_SHA. Run no further jobs against $REPO_ROOT until this is resolved by hand." >&2
  fi
  RESTORE_DONE=1
}
# INT/TERM MUST EXIT, NOT MERELY CLEAN UP. Bash resumes at the next statement
# after a signal handler returns, so `trap restore INT TERM` would run the
# cleanup and then let the script carry on through the code the cleanup just
# undid. The confirmed worst path: SIGTERM during the staging loop runs restore
# with COMMITTED=0, which deletes the branch the script is still using; control
# returns, the commit lands on a now-detached HEAD, and the push fails against a
# local ref that no longer exists — after which the EXIT trap reports "the
# commit is preserved on local branch dream/<slug>", naming a branch that does
# not exist. That is the exact silent shred V28 exists to prevent, announced as
# a preservation. (Found by cross-model review, 2026-07-29.)
#
# HUP and QUIT as well: their DEFAULT ACTION terminates bash without firing the
# EXIT trap at all, so a hangup in the scheduled nightly would leave HEAD on
# dream/<slug> and the branch orphaned — the identical failure the paragraph
# above exists to prevent, arriving through a signal nobody trapped.
#
# AND IT MUST STILL SPEAK. Exiting silently is its own version of the same bug:
# if the signal landed after the push completed, restore() now correctly
# recovers that fact, deletes the local branch and frees the checkout — but a
# bare `exit 1` prints no JSON, and Phase 3's general rule ("a non-zero exit is
# a refusal, record it as a skip") then applies to a branch that is genuinely on
# the remote. No PR is opened, and every subsequent night refuses on "already
# exists" — the dead branch again, arrived at from the other side. So the signal
# path emits the same JSON the success path does, with the resolved PUSHED, and
# the caller can act on it. (Found by cross-model review, 2026-07-29.)
on_signal() {
  # Never a second JSON object. The traps are no longer cleared on the success
  # path, so a signal can arrive after `emit true … armed` has already printed —
  # and a caller parsing two objects from one run is worse than a caller told
  # nothing. The line already out is the true one: restore had finished and the
  # push had succeeded before it was written.
  [ "$EMITTED" = 1 ] && exit 1
  restore
  # A SECOND SIGNAL, ARRIVING WHILE THE FIRST ONE'S restore WAS STILL RUNNING,
  # finds RESTORED=1 and gets an instant no-op above — so the FREED it reports is
  # whatever the interrupted pass had set by then, which on an early interrupt is
  # still the initial 1. Do not vouch for a restore that did not finish: FREED=0
  # ends the run for that repo and sends a human to look, which is the honest
  # answer to "we cannot say where HEAD is". Same reasoning for the ~30s quiesce
  # window on the success path, which is now covered by these handlers rather
  # than cleared before it. (Found by cross-model review, 2026-07-29.)
  if [ "$RESTORE_DONE" = 0 ]; then
    FREED=0
    echo "dream-commit.sh: interrupted DURING the restore — cannot vouch for the checkout. Run no further jobs against $REPO_ROOT until this is resolved by hand." >&2
  fi
  if [ "$PUSHED" = 1 ]; then
    emit true "$(git -C "$REPO_ROOT" rev-parse "refs/remotes/$REMOTE/$BRANCH" 2>/dev/null || echo "")" interrupted
  else
    # The commit SHA is known here whenever COMMITTED resolved to 1 — restore()
    # preserved the branch and it still points at the work. Emitting an empty
    # `commit` field hands the caller a branch name and withholds the SHA the
    # finding was computed into, which is the one thing a report row wants.
    emit false "$(git -C "$REPO_ROOT" rev-parse "refs/heads/$BRANCH" 2>/dev/null || echo "")" interrupted
  fi
  exit 1
}

# A REFUSAL THAT COULD NOT FREE THE CHECKOUT MUST STILL SAY SO IN THE JSON.
# `refuse()` prints a line and exits 1 — no JSON, by design, because a refusal
# has nothing to report. But whether the checkout was freed is decided later, in
# restore(), and a refusal whose restore ALSO failed is the worst combination in
# the file: dream.md's general rule for a non-zero exit is "record it as a skip
# and move to the next job", and moving on means every later job in that repo
# fails the base assertion — including the report, whose absence KD-6 reads as
# the routine having died. The stderr alarm was the only signal, on the one path
# where the field that is supposed to carry it was never printed.
# (Found by cross-model review, 2026-07-29.)
on_exit() {
  restore
  # A POST-COMMIT REFUSAL REPORTS ITSELF EVEN WHEN THE RESTORE WORKED. An ordinary
  # refusal stays silent on purpose — a signal that fires on every refusal is not
  # one — but a refusal that happens AFTER the commit is a different animal: the
  # branch exists, and in the lost-acknowledgement case (the remote wrote the ref,
  # the client never read the ack) it exists on the REMOTE too. restore() cannot
  # discover that, deliberately: it asks git locally rather than the network,
  # because the likeliest reason it is running is a hang on that same network. So
  # the local remote-tracking ref stays unset, PUSHED stays 0, and dream.md tells
  # the caller "the work was not pushed — tomorrow recomputes it". It does not:
  # the branch is on the remote and every later night refuses on `already exists`,
  # which this pipeline's own documentation calls its single worst outcome.
  # Emitting the branch and the SHA is what lets a human — or tomorrow's report —
  # see that there was something to look for. (Found by cross-model review,
  # 2026-07-30. Low probability, permanent and silent, hence reported anyway.)
  if [ "$FREED" = 1 ] && [ "$EMITTED" = 0 ] && [ "$COMMITTED" = 1 ]; then
    emit false "$(git -C "$REPO_ROOT" rev-parse "refs/heads/$BRANCH" 2>/dev/null || echo "")" refused
  elif [ "$FREED" = 0 ] && [ "$EMITTED" = 0 ]; then
    # The commit SHA, for the same reason on_signal fills it: `refuse "push of
    # … failed"` fires with COMMITTED=1 and the branch preserved, so a refusal
    # that ALSO stranded the checkout would otherwise report an empty commit for
    # work sitting on a local branch this same run just named on stderr.
    emit false "$(git -C "$REPO_ROOT" rev-parse "refs/heads/$BRANCH" 2>/dev/null || echo "")" refused
  fi
}
trap on_exit EXIT
trap on_signal INT TERM HUP QUIT

g checkout -q -b "$BRANCH" || refuse "cannot create branch $BRANCH"

while IFS= read -r p; do
  [ -n "$p" ] || continue
  # `--all -- <pathspec>` so a deletion is staged as a deletion: archival is a
  # MOVE, and staging only additions would leave the original file on the branch
  # alongside its archived copy. Scoped by pathspec, never repo-wide.
  # `git add --all -- <nonexistent>` exits 128 with `fatal: pathspec … did not
  # match any files`, so a typo in the declared list fails the whole job rather
  # than narrowing the commit — right direction, illegible message. Since
  # refusals must never be worked around, that message is all a human gets, and
  # "cannot stage" reads like a git problem rather than a list problem. Name the
  # actual cause: the path was declared and nothing is there.
  # Every OTHER failure keeps git's own stderr, for the same reason the branch
  # above names its cause: "cannot stage tmp/x" reads as a git malfunction, and
  # a refusal nobody may work around is entirely what its message says.
  #
  # NOT the gitignored target, which is what this was first written for. `git
  # status -uall` does not list ignored files, so a declared path that is
  # ignored contributes nothing to INSIDE and the empty-diff guard above refuses
  # with "no change under the declared paths" before staging is reached at all —
  # verified by trace. The reachable failures are the ones that need a real tree
  # AND a real fault: a `required` clean filter that exits non-zero (V47), an
  # unwritable index, a corrupt object. Naming the unreachable case as the
  # motivation would have been this file's own recurring bug.
  # (Found by cross-model review, 2026-07-29; its stated example did not hold,
  # the underlying point did.)
  ADD_ERR=$(g add --all -- "$p" 2>&1) || {
    if [ ! -e "$REPO_ROOT/$p" ] && ! g ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then
      refuse "declared --path does not exist in the repo: $p — the path list is wrong, not the tree"
    fi
    refuse "cannot stage $p: $(printf '%s' "$ADD_ERR" | tr '\n' ' ')"
  }
done <<EOF
$PATHS
EOF

# Post-stage assertion, deliberately separate from the pre-stage fence. The fence
# reasons about what the working tree looked like; this reasons about what git
# will actually put in the COMMIT.
#
# IT IS A NEAR-DEAD GUARD NOW, and saying so is the honest version. Once the diff
# below is scoped to the declared pathspecs and --path is validated against
# globs, pathspec magic, `./`, `..` and absolute paths, every path git can report
# for `tmp/archive` is `tmp/archive` or under it — which is exactly what covered()
# accepts. The billing this comment used to carry, "the check that the declared
# pathspecs did not expand somewhere unexpected", describes a property the code
# can no longer observe; the guarantee is `commit --only` below. One narrow path
# is still live: covered() compares literally while git pathspec matching honors
# core.ignorecase, true by default on macOS — so a declared `tmp/Archive` against
# an index entry `tmp/archive` matches the pathspec, git reports the index
# spelling, and this refuses. Kept for that, and for the N_STAGED counter on the
# same loop, which IS load-bearing. Not re-widened to the whole index: that was
# the round-12 bug this scoping fixed. (Found by cross-model review, 2026-07-30.)
#
# SCOPED TO THE DECLARED PATHS, because the index is not this job's to speak for.
# Both this loop and the commit below used to read the WHOLE index, and the two
# together were the file's central claim: "the report PR can contain nothing but
# the report file". They did not deliver it. `git checkout -b` carries index
# state forward, so anything already staged when a job starts was both committed
# by `git commit` and refused by this assertion — and the flag that exists to
# make the report immune to a dirty tree, --allow-unrelated-changes, drops only
# the WORKING-TREE fence. So the one job that must always ship (KD-6) was the one
# job a stale index could stop, which is the exact outcome the flag was added to
# prevent. Reachable two ways: a human's pre-staged work on a laptop `/dream`
# (named as live at the scoped-reset comment in restore(), then refused on here),
# and inside the container a prior job's `g reset -q -- "$rp" 2>/dev/null || true`
# losing to index-lock contention — the condition V42/V43 deliberately fixture.
#
# `commit --only -- <declared>` is what makes the scoping safe rather than a
# loosening: it builds the commit from HEAD plus the index entries for these
# paths and disregards everything else staged, so the commit cannot contain an
# undeclared path by construction, and the set this loop walks is exactly the set
# of paths that commit will change. The guarantee moves from an assertion into
# the command, which is this file's preferred direction; the assertion stays as
# the check that the declared pathspecs themselves did not expand somewhere
# unexpected. (Found by cross-model review, 2026-07-30 — Gemini's, and the
# script's own scoped-reset comment was the corroborating evidence.)
# NUL-separated for the same reason as the fence above, and counted inside the
# loop rather than by splitting a captured string on newlines.
N_STAGED=0
while IFS= read -r -d '' s; do
  [ -n "$s" ] || continue
  N_STAGED=$((N_STAGED+1))
  covered "$s" || refuse "staged path outside the declared list: $s"
# --no-renames IS LOAD-BEARING, not tidiness. `git diff --cached` defaults to
# rename detection, which collapses a rename to its destination path alone — so
# an undeclared DELETION that git pairs with a declared addition disappears from
# this list entirely, and the check billed above as "what actually guarantees
# the diff" would pass it. The test file already carried this exact reasoning for
# its own assertion and it was not applied to the guard being validated.
# (Found by cross-model review, 2026-07-29.)
done < <(g diff --cached --name-only --no-renames -z -- "${DECLARED[@]}")

# Same reason as the working-tree probe above: an unreadable index yields zero
# records, and "nothing staged" would blame the declared paths for it.
g diff --cached --quiet --exit-code >/dev/null 2>&1
[ "$?" -le 1 ] \
  || refuse "git cannot read the index in $REPO_ROOT — this is a git fault, not a path-list problem"

[ "$N_STAGED" -gt 0 ] \
  || refuse "nothing staged for job '$JOB' after adding the declared paths"

# The identity is set explicitly on every commit, not just when one is missing.
# A fresh container's git has no user.email at all, and `git commit` there fails
# with an instruction to run `git config` — an interactive remedy, at 2 AM, with
# nobody watching, that would cost the whole night's PRs and leave the report
# unable to explain why. Setting it also makes every commit attributable to the
# routine rather than to whoever's identity happened to be configured.
g -c user.name="dream (nightly maintenance)" \
  -c user.email="dream@example.local" \
  commit -q --only -m "$MESSAGE" -- "${DECLARED[@]}" \
  || refuse "commit failed for job '$JOB'"

COMMITTED=1
COMMIT_SHA=$(g rev-parse HEAD)

# Explicit refspec, no upstream tracking, no lease, no force. If the remote ref
# moved between the ls-remote above and here, git rejects this and the job is
# reported as failed — which is the correct outcome, not something to retry past.
g push -q "$REMOTE" "refs/heads/$BRANCH:refs/heads/$BRANCH" \
  || refuse "push of $BRANCH to $REMOTE failed"
PUSHED=1

# THE HANDLERS STAY ARMED THROUGH restore. Clearing them here left the widest
# unguarded window in the file: restore() opens with a bounded quiesce that
# sleeps up to ~30s, and a TERM arriving in it would take the default action and
# kill the process with the branch already on the remote and no JSON printed —
# which dream.md tells the caller to record as a skip, so no PR opens and every
# later night refuses on `already exists`. That is the outcome dream.md names as
# the single worst one in this pipeline, reached by the one path that had
# succeeded. Leaving them armed is safe because the handlers are idempotent
# against this: restore() no-ops on RESTORED, on_exit no-ops on EMITTED, and
# on_signal emits `interrupted` with pushed:true — which the caller opens a PR
# from. (Found by cross-model review, 2026-07-29.)
restore
emit true "$COMMIT_SHA" armed
# A FAILED RESTORE IS A FAILED RUN, even though the push succeeded. The header
# promises the checkout is always freed and restore() declares the alternative
# unrecoverable — but the success path used to exit 0 regardless, leaving that
# one condition guarded by nothing but the caller remembering to read a JSON
# field. In a script whose whole thesis is that prose guards do not hold at 2 AM,
# the mechanism cannot be prose. The JSON is emitted FIRST and above this line,
# so the caller still gets the branch and the SHA and can open the PR for work
# that really was pushed; `checkout_freed:false` explains the exit rather than
# being the only thing that carries it. (Found by cross-model review, 2026-07-29.)
[ "$FREED" = 1 ] || exit 1
