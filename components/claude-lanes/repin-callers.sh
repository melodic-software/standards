#!/usr/bin/env bash
# Re-pin the Claude lane caller components to a melodic-software/ci-workflows
# release. Extracted from .github/workflows/claude-lanes-repin.yml so the
# branching, the API-failure handling, and the file transformation are
# executable outside GitHub Actions and covered by repin-callers.test.sh.
#
# Two subcommands, matching the workflow's two steps:
#
#   repin-callers.sh resolve <owner/repo>   newest release -> tag + commit SHA
#   repin-callers.sh apply <tag> <sha>      rewrite the caller pins
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

# Sync-family and repo-local callers live outside LANE_DIR. They may already
# pin a different SHA than the lane components; apply reads each file's own
# pin rather than assuming one fleet-wide old SHA.
readonly -a EXTRA_CALLER_FILES=(
  '.github/workflows/claude-review.yml'
  '.github/workflows/sync.yml'
  '.github/workflows/standards-sync-stuck-automerge-alert.yml'
)

# Any `uses:` reference to a ci-workflows reusable workflow or composite action
# pinned by 40-character commit SHA.
readonly PIN_RE='uses: melodic-software/ci-workflows/[^@[:space:]]+@[0-9a-fA-F]{40}'

usage() {
  cat >&2 <<'USAGE'
usage:
  repin-callers.sh resolve <owner/repo>   resolve the newest release to tag + SHA
  repin-callers.sh apply <tag> <sha>      re-pin the lane callers to tag/SHA

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
  local err releases tag ref object_type object_sha sha

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

  echo "Resolved ${tag} (${object_type} object) to ${sha}."
  {
    echo 'resolved=true'
    echo "tag=${tag}"
    echo "sha=${sha}"
  } >> "$GITHUB_OUTPUT"
}

# repin::apply <tag> <sha>
#
# Emits changed=false and exits 0 when the callers already carry <sha>/<tag>;
# emits changed=true plus old-tags and version-note otherwise, leaving the
# rewritten files in the working tree for the caller to commit.
repin::apply() {
  local tag="$1" sha="$2"
  local root expected rewritten old_sha old_tags new_major old_major old_tag note delim
  local -a targets excludes

  root="$(git rev-parse --show-toplevel)"
  cd "$root"

  targets=("$LANE_DIR"/*.yml)
  local file
  for file in "${EXTRA_CALLER_FILES[@]}"; do
    # Extra callers are optional in a scratch test repo; they are required in
    # this repository and the existence check below covers production.
    [[ -f "$file" ]] && targets+=("$file")
  done
  for file in "${targets[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "::error::Expected enumerated caller '${file}' does not exist." >&2
      return 1
    fi
  done

  # grep exits 1 on no match, which pipefail would turn into a failed
  # assignment under errexit; `|| true` keeps the count (0) and drops the exit.
  expected="$(grep -hoE "$PIN_RE" "${targets[@]}" | wc -l || true)"
  # Unique old SHAs across every enumerated file — do not collapse to the
  # first pin. The workflow passes this unique-set to lockstep, which accepts
  # one SHA or a comma-separated list and still reads each caller file.
  old_sha="$(grep -hoE '@[0-9a-fA-F]{40}' "${targets[@]}" \
    | tr '[:upper:]' '[:lower:]' | tr -d '@' | sort -u | paste -sd, - || true)"
  old_tags="$(grep -hoE "${PIN_RE}[[:space:]]+# v[0-9]+\.[0-9]+\.[0-9]+" "${targets[@]}" \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | paste -sd, - || true)"

  sed -i -E "s|(uses: melodic-software/ci-workflows/[^@[:space:]]+)@[0-9a-fA-F]{40}.*|\1@${sha} # ${tag}|" \
    "${targets[@]}"

  rewritten="$(grep -hoE "${PIN_RE}[[:space:]]+# ${tag}\$" "${targets[@]}" | wc -l || true)"
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

  if git diff --quiet -- "${targets[@]}"; then
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
      [[ $# -eq 3 ]] || { usage; exit 2; }
      require_output_file
      repin::apply "$2" "$3"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
