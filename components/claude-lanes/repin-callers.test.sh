#!/usr/bin/env bash
# Behavioral tests for repin-callers.sh — the re-pin logic the scheduled
# .github/workflows/claude-lanes-repin.yml executes.
#
# The subject branches on API failures and tag object types, rewrites files in
# place, detects major-version jumps, and decides whether a privileged pull
# request is opened. Every one of those paths runs here.
#
# `resolve` reaches GitHub only through `gh`, so these tests put a stub `gh`
# ahead of the real one on PATH and drive it from environment variables. No
# case touches the network, so a rate limit, an outage, or a new upstream
# release cannot turn a behavioral regression into a green run — or a passing
# suite into a red one.
#
# This suite deliberately does NOT skip_suite on a missing tool. run-tests.sh
# treats a skipped file as a non-failure, so a skip here would restore exactly
# the silent no-coverage state this suite exists to remove; a missing bash,
# git, sed, or grep is a broken environment and fails loudly instead.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

script="$root/components/claude-lanes/repin-callers.sh"
fixture_corpus="$root/components/pin-comment-convention/fixtures"
upstream='melodic-software/ci-workflows'
old_sha='c136b27f404dd32ce3873f39a6f3443891d1c16e'
new_sha='a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4'

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

assert_file_exists 'subject script exists' "$script"

for tool in git sed grep sort paste cmp; do
  command -v "$tool" >/dev/null 2>&1 ||
    fail 'required tool present' "$tool is missing; this environment cannot run the subject"
done

# ---------------------------------------------------------------- gh stubbing

# stub_gh <dir> — a `gh` that answers the four endpoints repin::resolve calls,
# driven entirely by STUB_* variables the caller exports. It reproduces gh's
# real 404 shape (`gh: Not Found (HTTP 404)` on stderr, non-zero exit) because
# the subject's benign-vs-fatal discrimination reads exactly that text.
stub_gh() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/gh" <<'STUB'
#!/usr/bin/env bash
# Test double for the gh CLI. Only `gh api <path> --jq <expr>` is supported;
# the subject calls nothing else.
set -uo pipefail
not_found() { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
[[ "${1:-}" == 'api' ]] || { echo "stub gh: unsupported command ${1:-}" >&2; exit 64; }
path="${2:-}"
case "$path" in
  */releases/latest)
    [[ "${STUB_RELEASES_STATUS:-200}" == '200' ]] || not_found
    printf '%s\n' "${STUB_TAG_NAME:?stub gh: STUB_TAG_NAME unset}"
    ;;
  */git/ref/tags/*)
    printf '%s\t%s\n' "${STUB_REF_TYPE:?stub gh: STUB_REF_TYPE unset}" \
      "${STUB_REF_SHA:?stub gh: STUB_REF_SHA unset}"
    ;;
  */git/tags/*)
    printf '%s\n' "${STUB_TAG_OBJECT_SHA:?stub gh: STUB_TAG_OBJECT_SHA unset}"
    ;;
  repos/*/*)
    # Bare `repos/<owner>/<repo>` — the repository-readable probe. Reached only
    # after the more specific patterns above have not matched.
    [[ "${STUB_REPO_STATUS:-200}" == '200' ]] || not_found
    printf '%s\n' "${path#repos/}"
    ;;
  *)
    echo "stub gh: unexpected path $path" >&2
    exit 64
    ;;
esac
STUB
  chmod +x "$dir/gh"
}

stub_bin="$scratch/bin"
stub_gh "$stub_bin"

# run_resolve <outfile> — invoke `resolve` with the stub ahead of the real gh.
# Prints combined output; returns the subject's exit code.
run_resolve() {
  local outfile="$1"
  : > "$outfile"
  PATH="$stub_bin:$PATH" GITHUB_OUTPUT="$outfile" bash "$script" resolve "$upstream" 2>&1
}

# ------------------------------------------------------------ resolve: shapes

# Lightweight tag — the shape ci-workflows cuts today. The ref points straight
# at the commit, so no second dereference happens.
out_file="$scratch/out-lightweight"
export STUB_RELEASES_STATUS=200 STUB_TAG_NAME='v0.9.1' STUB_REF_TYPE='commit' STUB_REF_SHA="$old_sha"
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: lightweight tag exits 0' 0 "$rc"
assert_contains 'resolve: lightweight tag reports the commit object' "$out" 'commit object'
assert_contains 'resolve: lightweight tag emits resolved=true' "$(cat "$out_file")" 'resolved=true'
assert_contains 'resolve: lightweight tag emits the tag' "$(cat "$out_file")" 'tag=v0.9.1'
assert_contains 'resolve: lightweight tag emits the commit SHA' "$(cat "$out_file")" "sha=$old_sha"

# Annotated tag — the ref points at a tag object that must be dereferenced
# again. The emitted SHA must be the tag object's target, never the tag object.
out_file="$scratch/out-annotated"
tag_object='0000111122223333444455556666777788889999'
export STUB_RELEASES_STATUS=200 STUB_TAG_NAME='v1.4.0' STUB_REF_TYPE='tag' STUB_REF_SHA="$tag_object" STUB_TAG_OBJECT_SHA="$new_sha"
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: annotated tag exits 0' 0 "$rc"
assert_contains 'resolve: annotated tag reports the tag object' "$out" 'tag object'
assert_contains 'resolve: annotated tag dereferences to the commit' "$(cat "$out_file")" "sha=$new_sha"
assert_not_contains 'resolve: annotated tag never emits the tag object SHA' "$(cat "$out_file")" "$tag_object"
unset STUB_TAG_OBJECT_SHA

# ------------------------------------------------- resolve: 404 vs 404

# Benign: the repository reads, it simply has no published release. A clean
# no-op, because there is nothing to re-pin against yet.
out_file="$scratch/out-no-release"
export STUB_RELEASES_STATUS=404 STUB_REPO_STATUS=200 STUB_TAG_NAME='unused' STUB_REF_TYPE='commit' STUB_REF_SHA="$old_sha"
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: no published release exits 0' 0 "$rc"
assert_contains 'resolve: no published release emits resolved=false' "$(cat "$out_file")" 'resolved=false'
assert_contains 'resolve: no published release is a notice' "$out" '::notice::'
assert_not_contains 'resolve: no published release raises no error' "$out" '::error::'

# Fatal: the repository itself does not read. Identical 404 on the release
# endpoint, opposite verdict — this is the discrimination that keeps a renamed,
# deleted, or access-revoked upstream from reading as "nothing to do" forever.
out_file="$scratch/out-unreadable"
export STUB_RELEASES_STATUS=404 STUB_REPO_STATUS=404
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_nonzero 'resolve: unreadable upstream fails loudly' "$rc"
assert_contains 'resolve: unreadable upstream raises an error' "$out" '::error::'
assert_not_contains 'resolve: unreadable upstream never emits resolved=false' "$(cat "$out_file")" 'resolved=false'
export STUB_REPO_STATUS=200

# A tag outside full SemVer has no pin-comment form, so re-pinning would author
# a comment this repository's own pin-comment lane then rejects.
out_file="$scratch/out-bad-tag"
export STUB_RELEASES_STATUS=200 STUB_TAG_NAME='v1.4' STUB_REF_TYPE='commit' STUB_REF_SHA="$new_sha"
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_nonzero 'resolve: partial-SemVer tag fails' "$rc"
assert_contains 'resolve: partial-SemVer tag names the convention' "$out" 'SemVer'

# A ref pointing at neither a commit nor a tag object is unhandled upstream
# data, not something to guess at.
out_file="$scratch/out-odd-object"
export STUB_TAG_NAME='v1.4.0' STUB_REF_TYPE='blob' STUB_REF_SHA="$new_sha"
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_nonzero 'resolve: unexpected ref object type fails' "$rc"

# GITHUB_OUTPUT is the only result channel; an unset one must not read as a
# clean run that simply resolved nothing.
export STUB_TAG_NAME='v0.9.1' STUB_REF_TYPE='commit' STUB_REF_SHA="$old_sha"
rc=0
out="$(PATH="$stub_bin:$PATH" GITHUB_OUTPUT='' bash "$script" resolve "$upstream" 2>&1)" || rc=$?
assert_nonzero 'resolve: missing GITHUB_OUTPUT fails' "$rc"

# ------------------------------------------------------------- apply: fixtures

# lane_repo <dir> <pinned-sha> <pinned-tag> — a scratch repository carrying two
# lane callers AND this repository's REAL pin-comment fixture corpus, so the
# scope assertions run against the actual deliberately-malformed pins a
# repository-wide rewrite would corrupt, not a convenient stand-in.
lane_repo() {
  local dir="$1" pin_sha="$2" pin_tag="$3"
  make_repo "$dir"
  # The subject compares bytes through git and through cmp; a line-ending
  # rewrite between checkout and comparison would be indistinguishable from
  # the rewrite under test.
  git -C "$dir" config core.autocrlf false
  mkdir -p "$dir/components/claude-lanes" "$dir/components/pin-comment-convention"
  cp -R "$fixture_corpus" "$dir/components/pin-comment-convention/fixtures"

  cat > "$dir/components/claude-lanes/claude-review.yml" <<YAML
name: claude-review
on: pull_request
jobs:
  select-runner:
    uses: melodic-software/ci-workflows/.github/workflows/select-runner.yml@${pin_sha} # ${pin_tag}
  review:
    uses: melodic-software/ci-workflows/.github/workflows/claude-review.yml@${pin_sha} # ${pin_tag}
YAML
  cat > "$dir/components/claude-lanes/claude-security-review.yml" <<YAML
name: claude-security-review
on: pull_request
jobs:
  select-runner:
    uses: melodic-software/ci-workflows/.github/workflows/select-runner.yml@${pin_sha} # ${pin_tag}
  security:
    uses: melodic-software/ci-workflows/.github/workflows/claude-security-review.yml@${pin_sha} # ${pin_tag}
YAML
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'lane callers'
}

# run_apply <dir> <outfile> <tag> <sha>
run_apply() {
  local dir="$1" outfile="$2" tag="$3" sha="$4"
  : > "$outfile"
  (cd "$dir" && GITHUB_OUTPUT="$outfile" bash "$script" apply "$tag" "$sha" 2>&1)
}

# ------------------------------------------- apply: rewrite scope + major jump

repo="$scratch/repo-major"
lane_repo "$repo" "$old_sha" 'v0.9.1'
out_file="$scratch/out-apply-major"
rc=0; out="$(run_apply "$repo" "$out_file" 'v1.4.0' "$new_sha")" || rc=$?
assert_exit 'apply: major-version bump exits 0' 0 "$rc"
assert_contains 'apply: major-version bump reports a change' "$(cat "$out_file")" 'changed=true'
assert_contains 'apply: major-version bump records the tag it replaced' "$(cat "$out_file")" 'old-tags=v0.9.1'
assert_contains 'apply: major-version bump flags the jump' "$(cat "$out_file")" '[!WARNING]'
# shellcheck disable=SC2016  # markdown code fences in the expected note, not shell expansions
assert_contains 'apply: major-version bump names both versions' "$(cat "$out_file")" 'v0.9.1` to `v1.4.0'

# Both callers carry the new pin, and the comment carries the new tag.
lane_pins="$(grep -hoE "$new_sha # v1.4.0" "$repo"/components/claude-lanes/*.yml | wc -l | tr -d ' ')"
assert_eq 'apply: every lane pin is rewritten' '4' "$lane_pins"
assert_not_contains 'apply: no stale pin survives' \
  "$(cat "$repo"/components/claude-lanes/*.yml)" "$old_sha"

# THE SCOPE FENCE. The fixture corpus holds ci-workflows pins that are
# deliberately malformed — a missing comment, prose, a partial SemVer, a
# reversed fallback. A discovery-based rewrite would normalize every one of
# them into valid form and leave the bad-fixture suite passing with nothing
# left to detect. Byte-compare against the pristine originals.
fixture_drift=0
while IFS= read -r original; do
  copy="$repo/components/pin-comment-convention/fixtures/${original#"$fixture_corpus/"}"
  cmp -s "$original" "$copy" || fixture_drift=$((fixture_drift + 1))
done < <(find "$fixture_corpus" -type f | sort)
assert_eq 'apply: the pin-comment fixture corpus is byte-identical afterwards' '0' "$fixture_drift"

# The same claim from git's side, which also catches a file the loop above
# never enumerated.
changed_paths="$(git -C "$repo" diff --name-only | sort | paste -sd, -)"
assert_eq 'apply: only the lane callers are modified' \
  'components/claude-lanes/claude-review.yml,components/claude-lanes/claude-security-review.yml' \
  "$changed_paths"

# ------------------------------------------------- apply: same major, no diff

repo="$scratch/repo-minor"
lane_repo "$repo" "$old_sha" 'v0.9.1'
out_file="$scratch/out-apply-minor"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.2' "$new_sha")" || rc=$?
assert_exit 'apply: same-major bump exits 0' 0 "$rc"
assert_contains 'apply: same-major bump reports a change' "$(cat "$out_file")" 'changed=true'
assert_not_contains 'apply: same-major bump raises no jump warning' "$(cat "$out_file")" '[!WARNING]'
assert_contains 'apply: same-major bump says so' "$(cat "$out_file")" 'Same major version'

# Already at the target pin: a clean exit, no change reported, and — the part
# that matters — nothing left modified for a later step to commit.
repo="$scratch/repo-nodiff"
lane_repo "$repo" "$old_sha" 'v0.9.1'
out_file="$scratch/out-apply-nodiff"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.1' "$old_sha")" || rc=$?
assert_exit 'apply: no-diff run exits 0' 0 "$rc"
assert_contains 'apply: no-diff run reports changed=false' "$(cat "$out_file")" 'changed=false'
assert_not_contains 'apply: no-diff run never reports a change' "$(cat "$out_file")" 'changed=true'
assert_contains 'apply: no-diff run is a notice' "$out" '::notice::'
assert_silent 'apply: no-diff run leaves the tree clean' "$(git -C "$repo" status --porcelain)"

# ------------------------------------------------------------ apply: controls

# A repository with no lane callers must fail rather than report a clean no-op
# — silently re-pinning nothing is how this job would rot after a rename.
repo="$scratch/repo-empty"
make_repo "$repo"
mkdir -p "$repo/components/claude-lanes"
out_file="$scratch/out-apply-empty"
rc=0; out="$(run_apply "$repo" "$out_file" 'v1.4.0' "$new_sha")" || rc=$?
assert_nonzero 'apply: a repository with no lane callers fails' "$rc"
assert_not_contains 'apply: a repository with no lane callers reports no change' \
  "$(cat "$out_file")" 'changed=true'

# A caller set the rewrite reaches only partly must FAIL rather than open a
# pull request that re-pins some of the fleet and silently leaves the rest.
# The divergence here is two pins on one line: the counting pass matches per
# occurrence, while the substitution is per line and its trailing `.*` absorbs
# the second — so the guard sees 5 pins in and 4 rewritten. Synthetic (real
# callers put one `uses:` per line), and that is the point: it proves the
# count assertion is live rather than decorative.
#
# It also records a real property of a line-oriented rewrite — `uses:`-shaped
# text is matched wherever it appears on a line, including inside a YAML
# comment. That is why the file set is enumerated rather than discovered; the
# pin-comment component reaches for yq precisely to avoid this class of
# imprecision, and this subject does not need to because its inputs are two
# files this repository authors.
repo="$scratch/repo-partial"
lane_repo "$repo" "$old_sha" 'v0.9.1'
printf '    # %s %s\n' \
  "uses: melodic-software/ci-workflows/.github/workflows/a.yml@$old_sha" \
  "uses: melodic-software/ci-workflows/.github/workflows/b.yml@$old_sha" \
  >> "$repo/components/claude-lanes/claude-review.yml"
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'two pins on one line'
out_file="$scratch/out-apply-partial"
rc=0; out="$(run_apply "$repo" "$out_file" 'v1.4.0' "$new_sha")" || rc=$?
assert_nonzero 'apply: a partially-rewritten caller set fails' "$rc"
assert_contains 'apply: the partial rewrite reports the count mismatch' "$out" '::error::'
assert_not_contains 'apply: the partial rewrite reports no change' "$(cat "$out_file")" 'changed=true'

# apply also refuses without a result channel.
repo="$scratch/repo-nooutput"
lane_repo "$repo" "$old_sha" 'v0.9.1'
rc=0
out="$( (cd "$repo" && GITHUB_OUTPUT='' bash "$script" apply 'v1.4.0' "$new_sha" 2>&1) )" || rc=$?
assert_nonzero 'apply: missing GITHUB_OUTPUT fails' "$rc"

# Unknown and malformed invocations are usage errors, never silent successes.
rc=0; out="$(GITHUB_OUTPUT="$scratch/out-usage" bash "$script" 2>&1)" || rc=$?
assert_nonzero 'no subcommand is a usage error' "$rc"
rc=0; out="$(GITHUB_OUTPUT="$scratch/out-usage" bash "$script" frobnicate 2>&1)" || rc=$?
assert_nonzero 'an unknown subcommand is a usage error' "$rc"
rc=0; out="$(GITHUB_OUTPUT="$scratch/out-usage" bash "$script" apply v1.0.0 2>&1)" || rc=$?
assert_nonzero 'apply with a missing argument is a usage error' "$rc"

[[ $FAILED -eq 0 ]] || exit 1
