#!/usr/bin/env bash
# Re-pin the Claude lane caller components to a melodic-software/ci-workflows
# release. Extracted from .github/workflows/claude-lanes-repin.yml so the
# branching, the API-failure handling, and the file transformation are
# executable outside GitHub Actions and covered by repin-callers.test.sh.
#
# Two subcommands, matching the workflow's two steps:
#
#   repin-callers.sh resolve <owner/repo>       newest release -> tag, SHA, date
#   repin-callers.sh apply <tag> <sha> <date>   rewrite the caller pins
#
# Both report through GITHUB_OUTPUT (`key=value`, the Actions convention), so
# a test sets that variable to a scratch file and reads the result the same
# way the workflow does. Progress and diagnostics go to stdout/stderr as
# Actions workflow commands; every failure path exits non-zero.
set -euo pipefail

# The directory holding the lane callers, relative to the repository root.
# ENUMERATED, never discovered: a repository-wide search for ci-workflows pins
# also matches components/pin-comment-convention/fixtures/, whose deliberately
# malformed pins are that component's test corpus, and the test script that
# asserts against them.
readonly LANE_DIR='components/claude-lanes'

# Sync-family and repo-local callers, plus the one other sync-managed caller
# component, live outside LANE_DIR. They may already pin a different SHA than
# the lane components; apply reads each file's own pin rather than assuming
# one fleet-wide old SHA. The managed-files-guard caller pins a composite
# ACTION rather than a reusable workflow: it rides this cascade for the pin
# rewrite alone and has no runner-policy contract for the lockstep half to
# copy forward (components/managed-files-guard/README.md).
readonly -a EXTRA_CALLER_FILES=(
  '.github/workflows/claude-review.yml'
  '.github/workflows/sync.yml'
  '.github/workflows/standards-sync-stuck-automerge-alert.yml'
  'components/managed-files-guard/managed-files-guard.yml'
)

# Any `uses:` reference to a ci-workflows reusable workflow or composite action
# pinned by 40-character commit SHA.
readonly PIN_RE='uses: melodic-software/ci-workflows/[^@[:space:]]+@[0-9a-fA-F]{40}'
# The pin-comment convention's fallback form (`# <short-sha> <YYYY-MM-DD>`),
# which a pin to an as-yet-unreleased commit carries. The date is provenance
# for humans; apply decides "ahead of the release" from GitHub compare
# ancestry against the release SHA, not from that date.
readonly FALLBACK_PIN_RE="${PIN_RE}[[:space:]]+# [0-9a-f]{7,40} [0-9]{4}-[0-9]{2}-[0-9]{2}"
readonly DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
readonly UPSTREAM_REPO='melodic-software/ci-workflows'

usage() {
  cat >&2 <<'USAGE'
usage:
  repin-callers.sh resolve <owner/repo>       resolve the newest release to tag, SHA, and commit date
  repin-callers.sh apply <tag> <sha> <date>   re-pin the callers to tag/SHA; <date> is that commit's YYYY-MM-DD

Requires GITHUB_OUTPUT to name a writable file; `resolve` also requires gh.
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
# the two halves of the release -> re-pin chain read one artefact under one
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

# repin::compare_status <release-sha> <pin-sha>
#
# Prints GitHub's compare `status` of <release-sha>... <pin-sha> on the
# upstream repo (https://docs.github.com/en/rest/commits/commits#compare-two-commits):
#   ahead     — pin has commits the release does not; rewriting would downgrade
#   diverged  — neither is an ancestor of the other; same downgrade risk
#   behind    — pin is an ancestor of the release; the release contains it
#   identical — pin *is* the release
# A failed lookup is fatal: guessing "not ahead" would rewrite, which is the
# downgrade this fence exists to prevent.
repin::compare_status() {
  local release_sha="$1" pin_sha="$2" status err
  err="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$err'" RETURN
  if ! status="$(gh api "repos/${UPSTREAM_REPO}/compare/${release_sha}...${pin_sha}" \
    --jq .status 2>"$err")"; then
    echo "::error::Could not compare ${release_sha}...${pin_sha} on ${UPSTREAM_REPO}." >&2
    cat "$err" >&2
    return 1
  fi
  printf '%s\n' "$status"
}

# repin::ahead_of <file> <release-sha>
#
# Prints the SHA of a fallback-form pin in <file> that is not an ancestor of
# <release-sha> (compare status `ahead` or `diverged`), or nothing. Tag-form
# pins never match: a release is the newest of its line by construction of
# `resolve`. Day-level pin-comment dates are not consulted — same-day pins
# and cross-branch timestamps cannot prove containment.
repin::ahead_of() {
  local file="$1" release_sha="$2" pin_line pin_sha status
  while IFS= read -r pin_line; do
    [[ -n "$pin_line" ]] || continue
    pin_sha="$(sed -nE 's/.*@([0-9a-fA-F]{40}).*/\1/p' <<<"$pin_line" | head -n1)"
    [[ -n "$pin_sha" ]] || continue
    status="$(repin::compare_status "$release_sha" "$pin_sha")" || return 1
    case "$status" in
      ahead | diverged)
        echo "$pin_sha"
        return 0
        ;;
      behind | identical) ;;
      *)
        echo "::error::compare ${release_sha}...${pin_sha} returned '${status}', not a documented status." >&2
        return 1
        ;;
    esac
  done < <(grep -hE "$FALLBACK_PIN_RE" "$file" || true)
}

# repin::apply <tag> <sha> <date>
#
# Emits changed=false and exits 0 when the callers already carry <sha>/<tag>;
# emits changed=true plus old-tags and version-note otherwise, leaving the
# rewritten files in the working tree for the caller to commit. A file whose
# fallback-form pin is not an ancestor of <sha> is ahead of the release and
# is left untouched (see repin::ahead_of); it is reported, never rewritten.
repin::apply() {
  local tag="$1" sha="$2" release_date="$3"
  local root expected rewritten old_sha old_tags new_major old_major old_tag note ahead_sha ahead_list delim
  local -a targets rewrite ahead excludes

  if [[ ! "$release_date" =~ $DATE_RE ]]; then
    echo "::error::Release date '${release_date}' is not YYYY-MM-DD." >&2
    return 2
  fi

  root="$(git rev-parse --show-toplevel)"
  cd "$root"

  targets=("$LANE_DIR"/*.yml)
  local file extra_present=0 extra_missing=0
  for file in "${EXTRA_CALLER_FILES[@]}"; do
    if [[ -f "$file" ]]; then
      extra_present=1
      targets+=("$file")
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
  for file in "${targets[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "::error::Expected enumerated caller '${file}' does not exist." >&2
      return 1
    fi
  done

  # Split the enumerated set into files this release may advance and files
  # already ahead of it. The split is per file: every enumerated caller pins
  # one ci-workflows revision, so a file is either behind the release or not.
  rewrite=()
  ahead=()
  for file in "${targets[@]}"; do
    ahead_sha="$(repin::ahead_of "$file" "$sha")"
    if [[ -n "$ahead_sha" ]]; then
      echo "::notice::${file} pins ${ahead_sha}, not an ancestor of ${tag} (${sha}); left as is."
      ahead+=("$file")
    else
      rewrite+=("$file")
    fi
  done
  if [[ "${#rewrite[@]}" -eq 0 ]]; then
    echo "::notice::Every enumerated caller is ahead of ${tag}; nothing to propose."
    echo 'changed=false' >> "$GITHUB_OUTPUT"
    return 0
  fi

  # grep exits 1 on no match, which pipefail would turn into a failed
  # assignment under errexit; `|| true` keeps the count (0) and drops the exit.
  expected="$(grep -hoE "$PIN_RE" "${rewrite[@]}" | wc -l || true)"
  # Unique old SHAs across every rewritten file — do not collapse to the
  # first pin. The workflow passes this unique-set to lockstep, which accepts
  # one SHA or a comma-separated list and still reads each caller file.
  old_sha="$(grep -hoE "$PIN_RE" "${rewrite[@]}" \
    | grep -oE '[0-9a-fA-F]{40}$' | tr '[:upper:]' '[:lower:]' | sort -u | paste -sd, - || true)"
  old_tags="$(grep -hoE "${PIN_RE}[[:space:]]+# v[0-9]+\.[0-9]+\.[0-9]+" "${rewrite[@]}" \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | paste -sd, - || true)"

  sed -i -E "s|(uses: melodic-software/ci-workflows/[^@[:space:]]+)@[0-9a-fA-F]{40}.*|\1@${sha} # ${tag}|" \
    "${rewrite[@]}"

  rewritten="$(grep -hoE "${PIN_RE}[[:space:]]+# ${tag}\$" "${rewrite[@]}" | wc -l || true)"
  if [[ "$expected" -eq 0 || "$expected" -ne "$rewritten" ]]; then
    echo "::error::Expected ${expected} ci-workflows pins to carry '@${sha} # ${tag}'; ${rewritten} do." >&2
    return 1
  fi

  # Runtime companion to the enumerated set: prove the rewrite reached
  # nothing else, whatever the regex did. Extra callers live outside
  # LANE_DIR; they are allowlisted, not a hard-fail.
  excludes=(":(exclude)$LANE_DIR/")
  for file in "${EXTRA_CALLER_FILES[@]}"; do
    excludes+=(":(exclude)$file")
  done
  if ! git diff --quiet -- . "${excludes[@]}"; then
    echo "::error::The re-pin modified files outside the enumerated caller set:" >&2
    git diff --name-only -- . "${excludes[@]}" >&2
    return 1
  fi

  if git diff --quiet -- "${rewrite[@]}"; then
    echo "::notice::Enumerated callers already pin ${tag}; nothing to propose."
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
      [[ $# -eq 4 ]] || { usage; exit 2; }
      require_output_file
      repin::apply "$2" "$3" "$4"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
