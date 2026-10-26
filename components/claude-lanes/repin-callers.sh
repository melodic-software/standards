#!/usr/bin/env bash
# Re-pin the Claude lane caller components to a melodic-software/ci-workflows
# release. Extracted from .github/workflows/maintenance-repin-ci-workflows.yml so the
# branching, the API-failure handling, and the file transformation are
# executable outside GitHub Actions and covered by repin-callers.test.sh.
#
# Two subcommands, matching the workflow's two steps:
#
#   repin-callers.sh resolve <owner/repo>                      newest release -> tag, SHA, date
#   repin-callers.sh apply <tag> <sha> <date> [--root <dir>]   rewrite the pins the release changed
#
# apply moves a pin only when the release changed the path it pins (see
# repin::decide); every other pin stays byte-identical. Without --root it
# rewrites this repository's enumerated lane callers. With --root it rewrites
# every git-tracked .github/ YAML file of the repository at <dir> that pins
# ci-workflows, except the files the sync manifest manages in that repository
# (the sync owns their pins), which is how a consumer checkout repins with
# this same tool.
#
# Both report through GITHUB_OUTPUT (`key=value`, the Actions convention), so
# a test sets that variable to a scratch file and reads the result the same
# way the workflow does. Progress and diagnostics go to stdout/stderr as
# Actions workflow commands; every failure path exits non-zero.
set -euo pipefail
# A failing function inside `$(...)` must fail the assignment that called it,
# so planning errors cannot be read as an empty answer.
shopt -s inherit_errexit

# The directory holding the lane callers, relative to the repository root.
# ENUMERATED, never discovered: a repository-wide search for ci-workflows pins
# also matches components/pin-comment-convention/fixtures/, whose deliberately
# malformed pins are that component's test corpus, and the test script that
# asserts against them.
readonly LANE_DIR='components/claude-lanes'

# Sync-family and repo-local callers, the hosted lane caller components, and
# the two managed-files-guard caller components (hosted and fleet-routed),
# live outside LANE_DIR. They may
# already pin a different SHA than the lane components; apply reads each
# file's own pin rather than assuming one fleet-wide old SHA. The
# managed-files-guard callers pin a composite ACTION rather than a reusable
# workflow: they ride this cascade for the pin rewrite alone and have no
# runner-policy contract for the lockstep half to copy forward
# (components/managed-files-guard/README.md).
readonly -a EXTRA_CALLER_FILES=(
  '.github/workflows/pr-review.yml'
  '.github/workflows/pr-review-security.yml'
  '.github/workflows/maintenance-sync-standards.yml'
  'components/claude-lanes-hosted/claude-review.yml'
  'components/claude-lanes-hosted/claude-security-review.yml'
  'components/managed-files-guard/managed-files-guard.yml'
  'components/managed-files-guard/managed-files-guard-fleet.yml'
)

# Any `uses:` reference to a ci-workflows reusable workflow or composite action
# pinned by 40-character commit SHA.
readonly PIN_RE='uses: melodic-software/ci-workflows/[^@[:space:]]+@[0-9a-fA-F]{40}'
readonly DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
readonly UPSTREAM_REPO='melodic-software/ci-workflows'
# Old -> new upstream paths. Its `repo: ci-workflows` entries with a path
# `to` are the only renames apply follows; it keeps no copy of its own.
# Resolved beside this script, so a run against another repository root
# reads the same map.
RENAME_MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../github-actions-conventions" && pwd)/rename-map.json"
readonly RENAME_MAP
# The sync engine, resolved beside this script like RENAME_MAP. --root mode
# asks it which files the standards sync manages in the consumer.
SYNC_MANIFEST="${SYNC_MANIFEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../distribution" && pwd)/sync-manifest.sh}"
readonly SYNC_MANIFEST
readonly UPSTREAM_PATH_RE='^[A-Za-z0-9._/-]+$'
# The two `uses:` forms that run upstream code from the pinning commit itself:
# a step-level `$/<dir>` action and a job-level `./.github/workflows/<file>`
# nested workflow, the commit-relative forms runner-policy diffs
# (components/runner-policy/runner-policy.mjs). The optional character admits
# a quoted value.
readonly COMMIT_RELATIVE_RE='uses:[[:space:]]*.?(\$/[A-Za-z0-9_./-]+|\./\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml)'
# GitHub's compare response lists at most 300 files
# (https://docs.github.com/en/rest/commits/commits#compare-two-commits); a list
# that long may be cut short, so it cannot prove any path unchanged.
readonly COMPARE_FILE_CAP=300

usage() {
  cat >&2 <<'USAGE'
usage:
  repin-callers.sh resolve <owner/repo>                      resolve the newest release to tag, SHA, and commit date
  repin-callers.sh apply <tag> <sha> <date> [--root <dir>]   re-pin the pins the release changed to tag/SHA;
                                                             <date> is that commit's YYYY-MM-DD; --root repins
                                                             the .github/ callers of the repository at <dir>

Requires GITHUB_OUTPUT to name a writable file, and gh.
USAGE
}

# require_output_file — GITHUB_OUTPUT is the only result channel, so an unset
# or unwritable one is a harness fault that must not read as a clean run.
require_output_file() {
  if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
    echo '::error::GITHUB_OUTPUT is not set; nothing can report a result.' >&2
    exit 2
  fi
  : >> "$GITHUB_OUTPUT"
}

# repin::resolve <owner/repo>
#
# Emits resolved=false and exits 0 when the upstream has published no release;
# emits resolved=true plus tag and sha otherwise. Any other fault exits 1.
#
# SINGLE SOURCE OF TRUTH: the highest-SemVer PUBLISHED RELEASE.
#
# Upstream's own `release.yml` computes the next version by the same rule, so
# the two halves of the release -> re-pin chain read one artifact under one
# ordering. They did not always: `release.yml` once computed from the newest
# TAG while this resolver read a Release, so a tag published without a Release
# advanced the version counter while staying invisible here — the fleet
# skipped that version entirely and never pinned to it.
#
# Deliberately NOT the `releases/latest` endpoint, which this used to call:
# that endpoint orders by `created_at`, which GitHub sets from the tag target's
# COMMIT date rather than publish time, so a release cut from an older commit
# outranks a newer version. Sorting the published set by SemVer has no such
# dependence on commit chronology.
repin::resolve() {
  local upstream="$1"
  local err releases tag ref object_type object_sha sha date

  err="$(mktemp)"
  # shellcheck disable=SC2064  # expand $err now: the trap must survive it going out of scope
  trap "rm -f '$err'" RETURN

  # NO failure of this read is benign. That is a change from the endpoint this
  # used to call: `releases/latest` answered 404 both for "this repository has
  # published no release yet" and for a renamed, deleted, or no-longer-readable
  # upstream, so the benign case had to be disambiguated with a second call.
  # The LIST endpoint does not overload its 404 — it answers 200 with an empty
  # body when nothing is published (handled below), so a 404 here means only
  # that the repository itself is gone or unreadable. Disambiguating would now
  # be dead code that reports a missing upstream as "nothing to re-pin".
  #
  # Every failure therefore stays loud: an unattended daily job that reports
  # green while it has silently stopped checking anything is worse than no job
  # at all.
  if ! releases="$(gh api --paginate "repos/${upstream}/releases" \
    --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' 2> "$err")"; then
    echo "::error::Could not read the published ${upstream} releases." >&2
    cat "$err" >&2
    return 1
  fi

  # The benign "nothing published yet" case: 200 with an empty body.
  if [[ -z "${releases//[[:space:]]/}" ]]; then
    echo "::notice::${upstream} has no published release to re-pin against."
    echo 'resolved=false' >> "$GITHUB_OUTPUT"
    return 0
  fi

  # The pin-comment convention's primary form accepts full SemVer only
  # (components/pin-comment-convention/README.md), so a tag outside that shape
  # would have this job author a comment this repository's own CI then rejects
  # on the pull request it just opened. Selecting the highest FULL-SemVer
  # release means a stray non-SemVer release no longer decides the pin — but a
  # published set containing nothing else still fails loudly below rather than
  # silently re-pinning to an older version.
  tag="$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$releases" | sort -V | tail -n1 || true)"
  if [[ -z "$tag" ]]; then
    echo "::error::No ${upstream} release carries a full-SemVer (vX.Y.Z) tag; the pin-comment convention has no form for any of them:" >&2
    printf '%s\n' "$releases" >&2
    return 1
  fi

  # An annotated tag's ref points at a tag object that must be dereferenced
  # again to reach the commit; a lightweight tag's ref points at the commit
  # already. Both shapes are legal and upstream has cut both, so branch on the
  # object type explicitly rather than through an endpoint that hides it.
  ref="$(gh api "repos/${upstream}/git/ref/tags/${tag}" --jq '[.object.type, .object.sha] | @tsv')"
  object_type="${ref%%$'\t'*}"
  object_sha="${ref##*$'\t'}"

  case "$object_type" in
    tag) sha="$(gh api "repos/${upstream}/git/tags/${object_sha}" --jq .object.sha)" ;;
    commit) sha="$object_sha" ;;
    *)
      echo "::error::Tag '${tag}' points at an unexpected object type '${object_type}'." >&2
      return 1
      ;;
  esac

  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::Dereferenced '${tag}' to '${sha}', which is not a 40-character commit SHA." >&2
    return 1
  fi

  # The release commit's own date, in the same YYYY-MM-DD shape a fallback-form
  # pin comment records for the commit IT names, so apply can compare the two.
  # Committer date, not author date: it is when the commit entered history,
  # which is the ordering a "does this release contain that commit" question
  # approximates.
  date="$(gh api "repos/${upstream}/commits/${sha}" --jq '.commit.committer.date')"
  date="${date:0:10}"
  if [[ ! "$date" =~ $DATE_RE ]]; then
    echo "::error::Commit ${sha} reported committer date '${date}', which is not YYYY-MM-DD." >&2
    return 1
  fi

  echo "Resolved ${tag} (${object_type} object) to ${sha} (${date})."
  {
    echo 'resolved=true'
    echo "tag=${tag}"
    echo "sha=${sha}"
    echo "date=${date}"
  } >> "$GITHUB_OUTPUT"
}

# repin::compare <current-sha> <release-sha>
#
# Prints GitHub's compare `status` of <current-sha>...<release-sha>
# (https://docs.github.com/en/rest/commits/commits#compare-two-commits), read
# from the release's side:
#   ahead     — the release contains the pin; `files` is what it changed since
#   identical — the pin is the release
#   behind    — the pin has commits the release does not; moving would downgrade
#   diverged  — neither contains the other; same downgrade risk
# One call per distinct current SHA: the response is cached in REPIN_CACHE for
# the rest of the run, where repin::changed_files reads its file list. A failed
# lookup is fatal: guessing would either downgrade a pin or skip a change.
repin::compare() {
  local current="$1" release="$2" cached="${REPIN_CACHE}/compare-$1.json" status
  if [[ ! -f "$cached" ]]; then
    if ! gh api "repos/${UPSTREAM_REPO}/compare/${current}...${release}" \
      > "${cached}.part" 2> "${cached}.err"; then
      echo "::error::Could not compare ${current}...${release} on ${UPSTREAM_REPO}." >&2
      cat "${cached}.err" >&2
      return 1
    fi
    mv "${cached}.part" "$cached"
  fi
  status="$(jq -r '.status' "$cached")" || return 1
  case "$status" in
    ahead | identical | behind | diverged) printf '%s\n' "$status" ;;
    *)
      echo "::error::compare ${current}...${release} returned '${status}', not a documented status." >&2
      return 1
      ;;
  esac
}

# repin::changed_files <current-sha>
#
# Prints every path the cached compare of <current-sha> touched, a renamed file
# under both its names, or the single line `*` when the list cannot be trusted
# as complete: absent, or at the documented cap.
repin::changed_files() {
  jq -r --argjson cap "$COMPARE_FILE_CAP" \
    'if (.files | type) != "array" or (.files | length) >= $cap then "*"
     else .files[] | .filename, (.previous_filename // empty) end' \
    "${REPIN_CACHE}/compare-$1.json"
}

# repin::source <path> <sha>
#
# Prints the upstream file at <sha>, or nothing when the path does not exist
# there: a path the release removed or renamed is in its compare file list, so
# that list, not this read, moves its pin. Any failure but a 404 is fatal.
repin::source() {
  local path="$1" sha="$2" err="${REPIN_CACHE}/source.err"
  if gh api -H 'Accept: application/vnd.github.raw' \
    "repos/${UPSTREAM_REPO}/contents/${path}?ref=${sha}" 2> "$err"; then
    return 0
  fi
  if grep -q 'HTTP 404' "$err"; then
    return 0
  fi
  echo "::error::Could not read ${path} at ${sha} on ${UPSTREAM_REPO}." >&2
  cat "$err" >&2
  return 1
}

# repin::refs_in <path> <release-sha>
#
# Prints the upstream paths <path> runs through a commit-relative `uses:`
# (COMMIT_RELATIVE_RE), read from its source at the release, a composite
# through its action.yml or action.yaml. Cached per path: several pins can
# reach one composite.
repin::refs_in() {
  local path="$1" sha="$2" cached text
  cached="${REPIN_CACHE}/refs-${path//\//__}"
  if [[ ! -f "$cached" ]]; then
    if [[ "$path" =~ \.ya?ml$ ]]; then
      text="$(repin::source "$path" "$sha")"
    else
      text="$(repin::source "${path}/action.yml" "$sha")"
      if [[ -z "$text" ]]; then
        text="$(repin::source "${path}/action.yaml" "$sha")"
      fi
    fi
    { grep -oE "$COMMIT_RELATIVE_RE" <<< "$text" || true; } \
      | sed -E 's|^uses:[[:space:]]*.?[$.]/||; s|/+$||' | sort -u > "$cached"
  fi
  cat "$cached"
}

# repin::reach <path> <release-sha>
#
# Prints <path> and every path it reaches through commit-relative references,
# transitively. A pin runs all of them from its own commit, so a change to any
# of them changes what the pin runs.
repin::reach() {
  local next refs ref seen=$'\n'"$1"$'\n'
  local -a queue=("$1")
  while [[ "${#queue[@]}" -gt 0 ]]; do
    next="${queue[0]}"
    queue=("${queue[@]:1}")
    refs="$(repin::refs_in "$next" "$2")"
    while IFS= read -r ref; do
      [[ -n "$ref" && "$seen" != *$'\n'"${ref}"$'\n'* ]] || continue
      seen+="${ref}"$'\n'
      queue+=("$ref")
    done <<< "$refs"
  done
  printf '%s' "${seen#$'\n'}"
}

# repin::touches <changed-files> <reach>
#
# True when a changed file is one of the reached paths or lies beneath one: a
# reusable workflow is one file, a composite action its whole directory.
repin::touches() {
  local file path
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      if [[ "$file" == "$path" || "$file" == "$path"/* ]]; then
        return 0
      fi
    done <<< "$2"
  done <<< "$1"
  return 1
}

# repin::inert <file>
#
# True for a file no pin executes: a test (*.test.*), a README.md, or docs/.
repin::inert() {
  local base="${1##*/}"
  [[ "$base" == *.test.* || "$base" == README.md || "$1" == docs/* ]]
}

# repin::decide <path> <sha> <release-sha> <fenced-shas> <pinned-paths>
#
# Prints `move` when the release changed what the pin <path>@<sha> runs,
# `keep` when it did not, `ahead` when <sha> is fenced (not contained by the
# release), and `current` when the pin already is the release. Fails closed to
# `move` when the compare's file list is incomplete, or when it changed a file
# that is not inert and that no pinned path reaches (a shared script, a schema):
# nothing then proves which pins depend on it.
repin::decide() {
  local path="$1" sha="$2" release="$3" fenced="$4" pinned="$5"
  local status files reach file other covered
  if [[ "$sha" == "$release" ]]; then
    echo current
    return 0
  fi
  if grep -qxF -- "$sha" <<< "$fenced"; then
    echo ahead
    return 0
  fi
  status="$(repin::compare "$sha" "$release")"
  if [[ "$status" == identical ]]; then
    echo current
    return 0
  fi
  files="$(repin::changed_files "$sha")"
  if [[ -z "$files" ]]; then
    echo keep
    return 0
  fi
  if [[ "$files" == '*' ]]; then
    echo move
    return 0
  fi
  reach="$(repin::reach "$path" "$release")"
  # shellcheck disable=SC2310  # a pure predicate: nothing in it needs errexit
  if repin::touches "$files" "$reach"; then
    echo move
    return 0
  fi
  while IFS= read -r file; do
    # shellcheck disable=SC2310  # a pure predicate: nothing in it needs errexit
    if [[ -z "$file" ]] || repin::inert "$file"; then
      continue
    fi
    covered=false
    while IFS= read -r other; do
      reach="$(repin::reach "$other" "$release")"
      # shellcheck disable=SC2310  # a pure predicate: nothing in it needs errexit
      if repin::touches "$file" "$reach"; then
        covered=true
        break
      fi
    done <<< "$pinned"
    if [[ "$covered" == false ]]; then
      echo move
      return 0
    fi
  done <<< "$files"
  echo keep
}

# repin::refs <file>...
#
# Prints one `file<TAB>path<TAB>sha<TAB>comment` line per pin occurrence, the
# SHA lowercased and the comment `vX.Y.Z` (the tag form), `fallback` (the
# pin-comment convention's `# <short-sha> <YYYY-MM-DD>` form, which a pin to
# an as-yet-unreleased commit carries), or empty.
repin::refs() {
  local file match path sha comment
  for file in "$@"; do
    while IFS= read -r match; do
      path="${match#uses: melodic-software/ci-workflows/}"
      path="${path%%@*}"
      sha="${match#*@}"
      sha="${sha:0:40}"
      comment=''
      if [[ "$match" =~ \#\ (v[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        comment="${BASH_REMATCH[1]}"
      elif [[ "$match" =~ \#\ [0-9a-f]{7,40}\ [0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        comment=fallback
      fi
      printf '%s\t%s\t%s\t%s\n' "$file" "$path" "${sha,,}" "$comment"
    done < <(grep -oE "${PIN_RE}([[:space:]]+# [^[:space:]]+( [0-9]{4}-[0-9]{2}-[0-9]{2})?)?" "$file" || true)
  done
}

# repin::fenced <refs> <release-sha>
#
# Prints each SHA a fallback-form pin names that the release does not contain
# (compare `behind` or `diverged`). Every pin at such a SHA is left as is:
# moving it would go backwards. Tag-form pins are not fenced, since a release
# is the newest of its line by construction of `resolve`. Day-level pin-comment
# dates are not consulted: same-day pins and cross-branch timestamps cannot
# prove containment.
repin::fenced() {
  local sha status
  while IFS= read -r sha; do
    [[ -n "$sha" && "$sha" != "$2" ]] || continue
    status="$(repin::compare "$sha" "$2")"
    case "$status" in
      behind | diverged) echo "$sha" ;;
      *) ;;
    esac
  done < <(awk -F'\t' '$4 == "fallback" { print $3 }' <<< "$1" | sort -u)
}

# repin::path_state <path> <sha>
#
# Prints `present` or `absent` for <path> on the upstream at <sha>, through
# the contents API, which answers for one exact path and ref (a file or a
# directory) and, unlike a recursive tree read, never truncates. Any failure
# but a 404 is fatal: it says nothing about the path.
repin::path_state() {
  local path="$1" sha="$2" err
  err="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$err'" RETURN
  if gh api "repos/${UPSTREAM_REPO}/contents/${path}?ref=${sha}" --silent 2>"$err"; then
    echo present
  elif grep -q 'HTTP 404' "$err"; then
    echo absent
  else
    echo "::error::Could not probe ${path} at ${sha} on ${UPSTREAM_REPO}." >&2
    cat "$err" >&2
    return 1
  fi
}

# repin::path_map <sha> <path>...
#
# Prints `from<TAB>to` for each upstream <path>... that
# RENAME_MAP renames and that <sha> carries only under its new name. A
# release cut before the rename still has the old path, so it maps nothing.
# A pinned path absent under both names is fatal: no rewrite could be right.
repin::path_map() {
  local sha="$1" entries pinned from to old_state new_state
  shift
  if [[ ! -f "$RENAME_MAP" ]]; then
    echo "::error::${RENAME_MAP} is missing; renamed upstream paths cannot be resolved." >&2
    return 1
  fi
  # Called through command substitution, where bash clears errexit: every
  # failure below returns explicitly.
  entries="$(jq -r '.[] | select(.repo == "ci-workflows" and (.to | startswith(".github/")))
    | [.from, .to] | @tsv' "$RENAME_MAP")" || return 1
  pinned="$(printf '%s\n' "$@" | sort -u)"
  while IFS=$'\t' read -r from to; do
    if [[ -z "$from" ]] || ! grep -qxF -- "$from" <<<"$pinned"; then
      continue
    fi
    if [[ ! "$from" =~ $UPSTREAM_PATH_RE || ! "$to" =~ $UPSTREAM_PATH_RE ]]; then
      echo "::error::${RENAME_MAP} maps '${from}' to '${to}', which is not a plain repository path." >&2
      return 1
    fi
    old_state="$(repin::path_state "$from" "$sha")"
    case "$old_state" in
      present) continue ;;
      absent) ;;
      *) return 1 ;;
    esac
    new_state="$(repin::path_state "$to" "$sha")"
    case "$new_state" in
      present) printf '%s\t%s\n' "$from" "$to" ;;
      absent)
        echo "::error::Neither ${from} nor its renamed path ${to} exists at ${sha}." >&2
        return 1
        ;;
      *) return 1 ;;
    esac
  done <<<"$entries"
}

# repin::targets [<dir>]
#
# Prints the caller files apply may rewrite, one per line, relative to the
# repository root apply has changed into. Without <dir>: LANE_DIR's callers
# plus EXTRA_CALLER_FILES, enumerated, never discovered. With <dir>: every
# git-tracked .github/ YAML file that pins ci-workflows, which in a consumer
# checkout is the whole caller set, except the files the sync manifest maps
# into the consumer's origin repository: the sync owns those pins, and the
# consumer's managed-files guard rejects a PR that edits them. Skipped files
# are named on stderr.
repin::targets() {
  local file extra_present=0 extra_missing=0 repo managed=''
  local -a found
  if [[ "$#" -eq 1 ]]; then
    repo="$(git remote get-url origin 2>/dev/null || true)"
    repo="$(sed -E 's#^.*github\.com[:/]##; s#\.git$##' <<<"$repo")"
    if [[ -n "$repo" ]]; then
      managed="$(bash "$SYNC_MANIFEST" dest-paths --target "$repo")"
    fi
    git ls-files -- '.github/*.yml' '.github/*.yaml' | while IFS= read -r file; do
      if ! grep -qE "$PIN_RE" -- "$file"; then
        continue
      elif grep -qxF -- "$file" <<<"$managed"; then
        echo "Skipping sync-managed file: ${file}" >&2
      else
        printf '%s\n' "$file"
      fi
    done
    return 0
  fi
  found=("$LANE_DIR"/*.yml)
  for file in "${EXTRA_CALLER_FILES[@]}"; do
    if [[ -f "$file" ]]; then
      extra_present=1
      found+=("$file")
    else
      extra_missing=1
    fi
  done
  # Scratch fixtures may omit every extra. Production has the full set. A
  # partial set means a required extra was renamed or deleted — fail loud.
  if [[ "$extra_present" -eq 1 && "$extra_missing" -eq 1 ]]; then
    echo "::error::Enumerated extra callers must be all present or all absent." >&2
    for file in "${EXTRA_CALLER_FILES[@]}"; do
      if [[ ! -f "$file" ]]; then
        echo "::error::Expected enumerated caller '${file}' does not exist." >&2
      fi
    done
    return 1
  fi
  for file in "${found[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "::error::Expected enumerated caller '${file}' does not exist." >&2
      return 1
    fi
  done
  printf '%s\n' "${found[@]}"
}

# repin::apply <tag> <sha> <date> [<dir>]
#
# Moves each pin the release changed (repin::decide) to <sha> with a `# <tag>`
# comment and leaves every other pin byte-identical. Emits changed=false and
# exits 0 when no pin moves; emits changed=true plus old-sha, old-tags and
# version-note otherwise, leaving the rewritten files in the working tree for
# the caller to commit. A fallback-form pin the release does not contain is
# ahead of it and is reported, never rewritten (repin::fenced).
repin::apply() {
  local tag="$1" sha="$2" release_date="$3" dir="${4:-}"
  local root found refs fenced pinned decided moved file path pin_sha decision
  local expected before after old_sha old_tags new_major old_major old_tag note ahead_list kept_list delim
  local path_map from to renamed moved_paths
  local -a targets ahead excludes sed_args

  if [[ ! "$release_date" =~ $DATE_RE ]]; then
    echo "::error::Release date '${release_date}' is not YYYY-MM-DD." >&2
    return 2
  fi

  if [[ -n "$dir" ]]; then
    root="$(git -C "$dir" rev-parse --show-toplevel)"
  else
    root="$(git rev-parse --show-toplevel)"
  fi
  cd "$root"

  if [[ -n "$dir" ]]; then
    found="$(repin::targets "$dir")"
  else
    found="$(repin::targets)"
  fi
  if [[ -z "$found" ]]; then
    echo "::error::No file under ${root}/.github pins ${UPSTREAM_REPO}." >&2
    return 1
  fi
  mapfile -t targets <<< "$found"

  refs="$(repin::refs "${targets[@]}")"
  if [[ -z "$refs" ]]; then
    echo "::error::The caller files carry no ${UPSTREAM_REPO} pin to re-pin." >&2
    return 1
  fi
  fenced="$(repin::fenced "$refs" "$sha")"
  pinned="$(cut -f2 <<< "$refs" | sort -u)"

  # One decision per distinct path@sha; every occurrence of it shares it.
  decided=''
  while IFS=$'\t' read -r path pin_sha; do
    if [[ ! "$path" =~ $UPSTREAM_PATH_RE ]]; then
      echo "::error::Pinned path '${path}' is not a plain repository path." >&2
      return 1
    fi
    decision="$(repin::decide "$path" "$pin_sha" "$sha" "$fenced" "$pinned")"
    decided+="${path}"$'\t'"${pin_sha}"$'\t'"${decision}"$'\n'
  done < <(cut -f2,3 <<< "$refs" | sort -u)

  # A pin already on the release still takes the tag form when its comment
  # is not `# <tag>`, as a fallback-form pin to the release commit is.
  moved="$(
    {
      awk -F'\t' '$3 == "move" { print $1 "\t" $2 }' <<< "$decided"
      awk -F'\t' -v s="$sha" -v t="$tag" '$3 == s && $4 != t { print $2 "\t" $3 }' <<< "$refs"
    } | awk '$0 != "" && !seen[$0]++'
  )"

  ahead=()
  while IFS=$'\t' read -r file pin_sha; do
    [[ -n "$file" ]] || continue
    echo "::notice::${file} pins ${pin_sha}, not an ancestor of ${tag} (${sha}); left as is."
    if [[ " ${ahead[*]} " != *" ${file} "* ]]; then
      ahead+=("$file")
    fi
  done < <(awk -F'\t' 'NR == FNR { if ($0 != "") fenced[$0] = 1; next } ($3 in fenced) { print $1 "\t" $3 }' \
    <(printf '%s\n' "$fenced") <(printf '%s\n' "$refs") | awk '!seen[$0]++')

  kept_list=''
  while IFS=$'\t' read -r path pin_sha; do
    [[ -n "$path" ]] || continue
    echo "::notice::${tag} changes nothing ${path}@${pin_sha:0:7} runs; that pin stays."
    kept_list+="\`${path}\`, "
  done < <(awk -F'\t' '$3 == "keep" { print $1 "\t" $2 }' <<< "$decided")

  if [[ -z "$moved" ]]; then
    if ! awk -F'\t' '$3 != "ahead" && $3 != "" { found = 1 } END { exit !found }' <<< "$decided"; then
      echo "::notice::Every enumerated caller is ahead of ${tag}; nothing to propose."
    else
      echo "::notice::No pin needs ${tag}; nothing to propose."
    fi
    echo 'changed=false' >> "$GITHUB_OUTPUT"
    return 0
  fi

  # Count every moved occurrence not already `@<sha> # <tag>`, then require
  # exactly that many new such pins after the rewrite.
  expected="$(awk -F'\t' -v s="$sha" -v t="$tag" 'NR == FNR { if ($0 != "") m[$0] = 1; next }
    (($2 "\t" $3) in m) && !($3 == s && $4 == t)' \
    <(printf '%s\n' "$moved") <(printf '%s\n' "$refs") | wc -l)"
  before="$(grep -hoE "uses: ${UPSTREAM_REPO}/[^@[:space:]]+@${sha}[[:space:]]+# ${tag}\$" "${targets[@]}" | wc -l || true)"
  # A run that only relabels pins already on the release hands lockstep the
  # release SHA itself, which it treats as a no-op.
  old_sha="$(cut -f2 <<< "$moved" | { grep -vxF -- "$sha" || true; } | sort -u | paste -sd, -)"
  old_sha="${old_sha:-$sha}"
  old_tags="$(awk -F'\t' 'NR == FNR { if ($0 != "") m[$0] = 1; next } (($2 "\t" $3) in m) && $4 ~ /^v/ { print $4 }' \
    <(printf '%s\n' "$moved") <(printf '%s\n' "$refs") | sort -u | paste -sd, - || true)"

  moved_paths="$(cut -f1 <<< "$moved" | sort -u)"
  # shellcheck disable=SC2086  # one argument per moved path, none with whitespace
  path_map="$(repin::path_map "$sha" $moved_paths)"
  renamed=''
  while IFS=$'\t' read -r from to; do
    [[ -n "$from" ]] || continue
    echo "::notice::${tag} carries ${from} as ${to}; the pins follow the rename."
    renamed+="\`${from}\` to \`${to}\`, "
  done <<< "$path_map"
  sed_args=()
  while IFS=$'\t' read -r path pin_sha; do
    to="$(awk -F'\t' -v p="$path" '$1 == p { print $2 }' <<< "$path_map")"
    sed_args+=(-e "s|(uses: ${UPSTREAM_REPO}/)${path//./\\.}@${pin_sha}([^0-9a-fA-F].*)?\$|\1${to:-$path}@${sha} # ${tag}|I")
  done <<< "$moved"
  sed -i -E "${sed_args[@]}" "${targets[@]}"

  after="$(grep -hoE "uses: ${UPSTREAM_REPO}/[^@[:space:]]+@${sha}[[:space:]]+# ${tag}\$" "${targets[@]}" | wc -l || true)"
  if [[ "$expected" -eq 0 || "$((after - before))" -ne "$expected" ]]; then
    echo "::error::Expected ${expected} ci-workflows pins to newly carry '@${sha} # ${tag}'; $((after - before)) do." >&2
    return 1
  fi

  # Runtime companion to the target set: prove the rewrite reached nothing
  # else, whatever the regex did.
  excludes=()
  for file in "${targets[@]}"; do
    excludes+=(":(exclude)$file")
  done
  if ! git diff --quiet -- . "${excludes[@]}"; then
    echo "::error::The re-pin modified files outside the caller set:" >&2
    git diff --name-only -- . "${excludes[@]}" >&2
    return 1
  fi

  if git diff --quiet -- "${targets[@]}"; then
    echo "::notice::The callers already pin ${tag}; nothing to propose."
    echo 'changed=false' >> "$GITHUB_OUTPUT"
    return 0
  fi

  new_major="${tag#v}"
  new_major="${new_major%%.*}"
  local major_jump=false
  for old_tag in ${old_tags//,/ }; do
    old_major="${old_tag#v}"
    old_major="${old_major%%.*}"
    [[ "$old_major" == "$new_major" ]] || major_jump=true
  done

  if [[ "$major_jump" == true ]]; then
    note="> [!WARNING]
> **Major-version jump** from \`${old_tags}\` to \`${tag}\`. This is not a drop-in bump: read the upstream release notes for breaking changes to the lane callers' inputs, secrets, and required check names before merging."
  else
    note="Same major version as the pin it replaces (\`${old_tags}\` to \`${tag}\`)."
  fi
  # shellcheck disable=SC2016  # markdown code spans, not shell expansions
  note+="

Moved because ${tag} changed what they run: $(cut -f1 <<< "$moved" | sort -u | sed 's/.*/`&`/' | paste -sd, - | sed 's/,/, /g')."
  if [[ -n "$kept_list" ]]; then
    note+="

Left where they are because ${tag} changes nothing they run: ${kept_list%, }."
  fi
  if [[ -n "$renamed" ]]; then
    note+="

Renamed upstream at ${tag}, so these pins moved path as well as SHA: ${renamed%, }."
  fi
  if [[ "${#ahead[@]}" -gt 0 ]]; then
    ahead_list="$(printf "\`%s\`, " "${ahead[@]}")"
    note+="

Left untouched because their pinned commit is not an ancestor of ${tag} (${sha}): ${ahead_list%, }. Those pins advance on the first release that contains them."
  fi

  # A random heredoc delimiter, per GitHub's own multi-line output guidance:
  # a fixed one could in principle be reproduced inside the value and end the
  # block early.
  delim="NOTE_${RANDOM}${RANDOM}${RANDOM}"
  {
    echo 'changed=true'
    echo "old-sha=${old_sha}"
    echo "old-tags=${old_tags}"
    echo "version-note<<${delim}"
    echo "$note"
    echo "$delim"
  } >> "$GITHUB_OUTPUT"
}

main() {
  case "${1:-}" in
    resolve)
      [[ $# -eq 2 ]] || { usage; exit 2; }
      require_output_file
      repin::resolve "$2"
      ;;
    apply)
      if [[ $# -eq 6 && "$5" == '--root' && -n "$6" ]]; then
        set -- "$1" "$2" "$3" "$4" "$6"
      elif [[ $# -ne 4 ]]; then
        usage
        exit 2
      fi
      require_output_file
      REPIN_CACHE="$(mktemp -d)"
      # shellcheck disable=SC2064  # expand now: the path must survive the function
      trap "rm -rf -- '${REPIN_CACHE}'" EXIT
      repin::apply "${@:2}"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
