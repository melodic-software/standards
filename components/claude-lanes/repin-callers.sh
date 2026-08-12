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
repin::resolve() {
  local upstream="$1"
  local err tag ref object_type object_sha sha

  err="$(mktemp)"
  # shellcheck disable=SC2064  # expand $err now: the trap must survive it going out of scope
  trap "rm -f '$err'" RETURN

  # Only one 404 here is benign — "this repository has published no release
  # yet". A renamed, deleted, or no-longer-readable upstream returns the same
  # 404, so confirm the repository itself still reads before accepting that
  # reading. Every other failure stays loud: an unattended daily job that
  # reports green while it has silently stopped checking anything is worse
  # than no job at all.
  if ! tag="$(gh api "repos/${upstream}/releases/latest" --jq .tag_name 2>"$err")"; then
    if grep -q 'HTTP 404' "$err" && gh api "repos/${upstream}" --jq .full_name > /dev/null 2>&1; then
      echo "::notice::${upstream} has no published release to re-pin against."
      echo 'resolved=false' >> "$GITHUB_OUTPUT"
      return 0
    fi
    echo "::error::Could not read the newest ${upstream} release." >&2
    cat "$err" >&2
    return 1
  fi

  # The pin-comment convention's primary form accepts full SemVer only
  # (components/pin-comment-convention/README.md), so a tag outside that shape
  # would have this job author a comment this repository's own CI then rejects
  # on the pull request it just opened.
  if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::Newest ${upstream} release tag '${tag}' is not full SemVer (vX.Y.Z); the pin-comment convention has no form for it." >&2
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
  local root expected rewritten old_tags new_major old_major old_tag note delim
  local -a targets

  root="$(git rev-parse --show-toplevel)"
  cd "$root"

  targets=("$LANE_DIR"/*.yml)
  local file
  for file in "${targets[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "::error::Expected lane caller component '${file}' does not exist." >&2
      return 1
    fi
  done

  # grep exits 1 on no match, which pipefail would turn into a failed
  # assignment under errexit; `|| true` keeps the count (0) and drops the exit.
  expected="$(grep -hoE "$PIN_RE" "${targets[@]}" | wc -l || true)"
  old_sha="$(grep -hoE '@[0-9a-fA-F]{40}' "${targets[@]}" | head -1 | tr '[:upper:]' '[:lower:]' | tr -d '@')"
  old_tags="$(grep -hoE "${PIN_RE}[[:space:]]+# v[0-9]+\.[0-9]+\.[0-9]+" "${targets[@]}" \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | paste -sd, - || true)"

  sed -i -E "s|(uses: melodic-software/ci-workflows/[^@[:space:]]+)@[0-9a-fA-F]{40}.*|\1@${sha} # ${tag}|" \
    "${targets[@]}"

  rewritten="$(grep -hoE "${PIN_RE}[[:space:]]+# ${tag}\$" "${targets[@]}" | wc -l || true)"
  if [[ "$expected" -eq 0 || "$expected" -ne "$rewritten" ]]; then
    echo "::error::Expected ${expected} ci-workflows pins to carry '@${sha} # ${tag}'; ${rewritten} do." >&2
    return 1
  fi

  # Runtime companion to the enumerated glob above: prove the rewrite reached
  # nothing else, whatever the regex did.
  if ! git diff --quiet -- . ":(exclude)$LANE_DIR/"; then
    echo "::error::The re-pin modified files outside ${LANE_DIR}/:" >&2
    git diff --name-only -- . ":(exclude)$LANE_DIR/" >&2
    return 1
  fi

  if git diff --quiet -- "$LANE_DIR/"; then
    echo "::notice::${LANE_DIR}/ already pins ${tag}; nothing to propose."
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
