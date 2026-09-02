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
# Test double for the gh CLI. Only `gh api [flags] <path> --jq <expr>` is
# supported; the subject calls nothing else.
set -uo pipefail
not_found() { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; }
[[ "${1:-}" == 'api' ]] || { echo "stub gh: unsupported command ${1:-}" >&2; exit 64; }
# The route is the first non-flag argument after `api`. Scanning for it rather
# than reading $2 keeps the stub correct as the subject adds flags such as
# `--paginate`, which the release-list read passes ahead of the path.
shift
path=''
for arg in "$@"; do
  case "$arg" in
    -*) continue ;;
    *) path="$arg"; break ;;
  esac
done
case "$path" in
  */releases)
    # The published-release LIST — the subject's source of truth. Answers 200
    # with an empty body for a repository that has published nothing.
    [[ "${STUB_RELEASES_STATUS:-200}" == '200' ]] || not_found
    if [[ -n "${STUB_RELEASE_TAGS+x}" ]]; then
      [[ -z "$STUB_RELEASE_TAGS" ]] || printf '%s\n' "$STUB_RELEASE_TAGS"
    else
      printf '%s\n' "${STUB_TAG_NAME:?stub gh: STUB_TAG_NAME unset}"
    fi
    ;;
  */releases/latest)
    # Retained so a regression that reintroduces the created_at-ordered
    # endpoint is a loud stub failure rather than a silently different answer.
    echo 'stub gh: releases/latest is not the source of truth; use the release list' >&2
    exit 64
    ;;
  */git/ref/tags/*)
    printf '%s\t%s\n' "${STUB_REF_TYPE:?stub gh: STUB_REF_TYPE unset}" \
      "${STUB_REF_SHA:?stub gh: STUB_REF_SHA unset}"
    ;;
  */git/tags/*)
    printf '%s\n' "${STUB_TAG_OBJECT_SHA:?stub gh: STUB_TAG_OBJECT_SHA unset}"
    ;;
  */commits/*)
    # The resolved commit's metadata; the subject reads its committer date.
    # Defaults so the resolve cases that predate the date output need no
    # extra setup; the date cases set it explicitly.
    printf '%s\n' "${STUB_COMMIT_DATE-2026-01-15T09:30:00Z}"
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
assert_contains 'resolve: lightweight tag emits the commit date as YYYY-MM-DD' "$(cat "$out_file")" 'date=2026-01-15'

# The date is the release COMMIT's committer date, truncated to the day, in
# the shape a fallback-form pin comment records — apply compares the two.
out_file="$scratch/out-date"
export STUB_COMMIT_DATE='2026-08-21T08:17:24Z'
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: commit date exits 0' 0 "$rc"
assert_contains 'resolve: commit date is truncated to the day' "$(cat "$out_file")" 'date=2026-08-21'
assert_not_contains 'resolve: commit date carries no time component' "$(cat "$out_file")" 'T08:17'

# An unparsable date is upstream data the ahead-of-release comparison cannot
# consume; it must fail loudly rather than emit a date apply then misreads.
out_file="$scratch/out-bad-date"
export STUB_COMMIT_DATE='not-a-date'
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_nonzero 'resolve: an unparsable commit date fails' "$rc"
assert_contains 'resolve: an unparsable commit date raises an error' "$out" '::error::'
assert_not_contains 'resolve: an unparsable commit date never emits resolved=true' "$(cat "$out_file")" 'resolved=true'
unset STUB_COMMIT_DATE

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

# ------------------------------------------- resolve: highest SemVer wins

# THE SOURCE-OF-TRUTH RULE. The subject picks the highest-SemVer published
# release, not the first entry and not the one the `releases/latest` endpoint
# would name. `releases/latest` orders by `created_at`, which GitHub sets from
# the tag target's COMMIT date, so a release cut from an older commit outranks
# a newer version there; this ordering has no such dependence.
out_file="$scratch/out-highest-semver"
export STUB_RELEASES_STATUS=200 STUB_REF_TYPE='commit' STUB_REF_SHA="$new_sha"
export STUB_RELEASE_TAGS='v0.9.1
v0.14.0
v0.12.0'
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: a multi-release set exits 0' 0 "$rc"
assert_contains 'resolve: the highest SemVer release wins' "$(cat "$out_file")" 'tag=v0.14.0'
assert_not_contains 'resolve: a lower release never wins' "$(cat "$out_file")" 'tag=v0.12.0'

# Version ordering, not lexical: v0.10.0 is newer than v0.9.1, and a lexical
# sort would answer v0.9.1.
out_file="$scratch/out-semver-order"
export STUB_RELEASE_TAGS='v0.9.1
v0.10.0'
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: SemVer ordering exits 0' 0 "$rc"
assert_contains 'resolve: v0.10.0 outranks v0.9.1' "$(cat "$out_file")" 'tag=v0.10.0'

# A stray non-SemVer release no longer decides the pin: it is skipped and the
# highest full-SemVer release is chosen instead.
out_file="$scratch/out-mixed-shapes"
export STUB_RELEASE_TAGS='nightly
v0.12.0
v1.4'
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: a mixed-shape release set exits 0' 0 "$rc"
assert_contains 'resolve: non-SemVer releases are skipped' "$(cat "$out_file")" 'tag=v0.12.0'

# An empty published set is the benign "nothing to re-pin against" verdict the
# list endpoint reports as 200 rather than 404.
out_file="$scratch/out-empty-list"
export STUB_RELEASE_TAGS=''
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: an empty published release set exits 0' 0 "$rc"
assert_contains 'resolve: an empty release set emits resolved=false' "$(cat "$out_file")" 'resolved=false'
assert_contains 'resolve: an empty release set is a notice' "$out" '::notice::'
assert_not_contains 'resolve: an empty release set raises no error' "$out" '::error::'
unset STUB_RELEASE_TAGS

# ------------------------------------------------- resolve: 404 vs 404

# Benign: the repository reads, it simply has no published release. A clean
# no-op, because there is nothing to re-pin against yet. Under the LIST
# endpoint that case is 200 with an empty body — not the 404 the old
# `releases/latest` endpoint returned.
out_file="$scratch/out-no-release"
export STUB_RELEASES_STATUS=200 STUB_RELEASE_TAGS='' STUB_REPO_STATUS=200 STUB_TAG_NAME='unused' STUB_REF_TYPE='commit' STUB_REF_SHA="$old_sha"
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_exit 'resolve: no published release exits 0' 0 "$rc"
assert_contains 'resolve: no published release emits resolved=false' "$(cat "$out_file")" 'resolved=false'
assert_contains 'resolve: no published release is a notice' "$out" '::notice::'
assert_not_contains 'resolve: no published release raises no error' "$out" '::error::'
unset STUB_RELEASE_TAGS

# Fatal: the repository itself does not read. The LIST endpoint does not
# overload its 404 the way `releases/latest` did — nothing-published is the
# 200-empty case above — so a 404 here means only that the upstream is gone or
# unreadable, and it must stay loud. A renamed, deleted, or access-revoked
# upstream reading as "nothing to do" forever is the failure this guards.
out_file="$scratch/out-unreadable"
export STUB_RELEASES_STATUS=404 STUB_REPO_STATUS=404
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_nonzero 'resolve: unreadable upstream fails loudly' "$rc"
assert_contains 'resolve: unreadable upstream raises an error' "$out" '::error::'
assert_not_contains 'resolve: unreadable upstream never emits resolved=false' "$(cat "$out_file")" 'resolved=false'
export STUB_REPO_STATUS=200

# A 404 on the release list is fatal even when the repository itself still
# reads: under the list endpoint that combination is not "nothing published",
# it is an unreadable releases surface, and the old disambiguating second call
# would have mistaken it for a clean no-op.
out_file="$scratch/out-releases-404-repo-ok"
export STUB_RELEASES_STATUS=404 STUB_REPO_STATUS=200
rc=0; out="$(run_resolve "$out_file")" || rc=$?
assert_nonzero 'resolve: releases 404 with a readable repo still fails loudly' "$rc"
assert_contains 'resolve: releases 404 with a readable repo raises an error' "$out" '::error::'
assert_not_contains 'resolve: releases 404 with a readable repo emits no resolved=false' "$(cat "$out_file")" 'resolved=false'
export STUB_RELEASES_STATUS=200

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

# run_apply <dir> <outfile> <tag> <sha> [release-date]
#
# The release date only matters to fallback-form pins; the tag-form fixtures
# below take a fixed default so their cases stay about the rewrite itself.
run_apply() {
  local dir="$1" outfile="$2" tag="$3" sha="$4" release_date="${5:-2026-08-21}"
  : > "$outfile"
  (cd "$dir" && GITHUB_OUTPUT="$outfile" bash "$script" apply "$tag" "$sha" "$release_date" 2>&1)
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

# Extra callers live outside LANE_DIR and may already pin a different SHA.
# apply must rewrite each file from its own pin and must not hard-fail just
# because the diff left LANE_DIR.
repo="$scratch/repo-mixed"
lane_repo "$repo" "$old_sha" 'v0.9.1'
other_sha='b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5'
mkdir -p "$repo/.github/workflows"
cat > "$repo/.github/workflows/sync.yml" <<YAML
name: sync
on: workflow_dispatch
jobs:
  sync:
    uses: melodic-software/ci-workflows/.github/workflows/standards-sync.yml@${other_sha} # v0.8.0
YAML
cat > "$repo/.github/workflows/standards-sync-stuck-automerge-alert.yml" <<YAML
name: alert
on: schedule
jobs:
  alert:
    uses: melodic-software/ci-workflows/.github/workflows/standards-sync-stuck-automerge-alert.yml@${other_sha} # v0.8.0
YAML
cat > "$repo/.github/workflows/claude-review.yml" <<YAML
name: local-review
on: pull_request
jobs:
  review:
    uses: melodic-software/ci-workflows/.github/workflows/claude-review.yml@${old_sha} # v0.9.1
YAML
# The guard caller pins a composite ACTION at a step, in the convention's
# fallback comment form, dated before the release under test — so this
# release may advance it, and the rewrite must land the tag form.
guard_sha='c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f6'
guard_caller='components/managed-files-guard/managed-files-guard.yml'
mkdir -p "$repo/components/managed-files-guard"
cat > "$repo/$guard_caller" <<YAML
name: managed-files-guard
on: pull_request
jobs:
  managed-files-guard:
    steps:
      - uses: melodic-software/ci-workflows/.github/actions/managed-files-guard@${guard_sha} # c3d4e5f 2026-08-01
YAML
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'mixed pins'
out_file="$scratch/out-apply-mixed"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.2' "$new_sha" '2026-08-21')" || rc=$?
assert_exit 'apply: mixed-SHA extras exit 0' 0 "$rc"
assert_contains 'apply: mixed-SHA extras report a change' "$(cat "$out_file")" 'changed=true'
assert_contains 'apply: mixed-SHA extras record both old SHAs' "$(cat "$out_file")" "$old_sha"
assert_contains 'apply: mixed-SHA extras record the sync-family SHA' "$(cat "$out_file")" "$other_sha"
assert_contains 'apply: mixed-SHA extras record the guard action SHA' "$(cat "$out_file")" "$guard_sha"
mixed_old="$(grep '^old-sha=' "$out_file" | cut -d= -f2-)"
assert_contains 'apply: mixed-SHA old-sha is a comma-separated unique set' "$mixed_old" ','
assert_not_contains 'apply: mixed-SHA extras do not hard-fail outside LANE_DIR' "$out" 'outside'
assert_not_contains 'apply: a fallback pin dated before the release is not reported as ahead' "$out" 'left as is'
mixed_pins="$(grep -hoE "$new_sha # v0.9.2" \
  "$repo"/components/claude-lanes/*.yml \
  "$repo"/.github/workflows/sync.yml \
  "$repo"/.github/workflows/standards-sync-stuck-automerge-alert.yml \
  "$repo"/.github/workflows/claude-review.yml \
  "$repo/$guard_caller" | wc -l | tr -d ' ')"
assert_eq 'apply: every enumerated pin is rewritten under mixed SHAs' '8' "$mixed_pins"
assert_contains 'apply: the guard caller fallback comment becomes the tag form' \
  "$(cat "$repo/$guard_caller")" "managed-files-guard@${new_sha} # v0.9.2"
assert_not_contains 'apply: the guard caller keeps no stale fallback comment' \
  "$(cat "$repo/$guard_caller")" '2026-08-01'
mixed_paths="$(git -C "$repo" diff --name-only | sort | paste -sd, -)"
assert_contains 'apply: mixed-SHA extras include sync.yml' "$mixed_paths" '.github/workflows/sync.yml'
assert_contains 'apply: mixed-SHA extras include the alert caller' "$mixed_paths" \
  '.github/workflows/standards-sync-stuck-automerge-alert.yml'
assert_contains 'apply: mixed-SHA extras include the local review caller' "$mixed_paths" \
  '.github/workflows/claude-review.yml'
assert_contains 'apply: mixed-SHA extras include the guard caller component' "$mixed_paths" "$guard_caller"

# ------------------------------------------ apply: a pin ahead of the release

# THE DOWNGRADE FENCE. A fallback-form pin names a commit by its date; when
# that date is after the release commit's, the release cannot contain it, and
# rewriting the file would move the pin BACKWARDS — behind the fix it was
# pinned for. The lane callers still advance; the ahead file is reported and
# left byte-identical.
repo="$scratch/repo-ahead"
lane_repo "$repo" "$old_sha" 'v0.9.1'
mkdir -p "$repo/.github/workflows" "$repo/components/managed-files-guard"
for extra in sync.yml standards-sync-stuck-automerge-alert.yml claude-review.yml; do
  cat > "$repo/.github/workflows/$extra" <<YAML
name: extra
on: pull_request
jobs:
  job:
    uses: melodic-software/ci-workflows/.github/workflows/${extra}@${old_sha} # v0.9.1
YAML
done
cat > "$repo/$guard_caller" <<YAML
name: managed-files-guard
on: pull_request
jobs:
  managed-files-guard:
    steps:
      - uses: melodic-software/ci-workflows/.github/actions/managed-files-guard@${guard_sha} # c3d4e5f 2026-08-30
YAML
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'guard pinned ahead of the release'
out_file="$scratch/out-apply-ahead"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.2' "$new_sha" '2026-08-21')" || rc=$?
assert_exit 'apply: an ahead pin exits 0' 0 "$rc"
assert_contains 'apply: an ahead pin still reports the lane change' "$(cat "$out_file")" 'changed=true'
assert_contains 'apply: an ahead pin is reported as left as is' "$out" \
  "::notice::${guard_caller} pins a commit dated 2026-08-30, after v0.9.2 (2026-08-21); left as is."
assert_contains 'apply: the ahead file keeps its SHA' "$(cat "$repo/$guard_caller")" "@${guard_sha} # c3d4e5f 2026-08-30"
assert_not_contains 'apply: the ahead file is never moved to the release' "$(cat "$repo/$guard_caller")" "$new_sha"
assert_eq 'apply: the ahead file stays byte-identical' \
  "$(git -C "$repo" diff --name-only -- "$guard_caller")" ''
assert_not_contains 'apply: the ahead SHA is not handed to lockstep as an old SHA' \
  "$(grep '^old-sha=' "$out_file")" "$guard_sha"
assert_contains 'apply: the version note names the file left untouched' "$(cat "$out_file")" \
  "(2026-08-21): \`${guard_caller}\`. Those pins advance"
ahead_pins="$(grep -hoE "$new_sha # v0.9.2" \
  "$repo"/components/claude-lanes/*.yml "$repo"/.github/workflows/*.yml | wc -l | tr -d ' ')"
assert_eq 'apply: every other enumerated pin still advances' '7' "$ahead_pins"

# Same-day is not ahead: a release cut the day the pinned commit landed is
# taken to contain it, so the pin advances to the tag form.
repo="$scratch/repo-same-day"
lane_repo "$repo" "$old_sha" 'v0.9.1'
mkdir -p "$repo/.github/workflows" "$repo/components/managed-files-guard"
for extra in sync.yml standards-sync-stuck-automerge-alert.yml claude-review.yml; do
  printf 'jobs:\n  job:\n    uses: melodic-software/ci-workflows/.github/workflows/%s@%s # v0.9.1\n' \
    "$extra" "$old_sha" > "$repo/.github/workflows/$extra"
done
printf 'jobs:\n  g:\n    steps:\n      - uses: melodic-software/ci-workflows/.github/actions/managed-files-guard@%s # c3d4e5f 2026-08-21\n' \
  "$guard_sha" > "$repo/$guard_caller"
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'guard pinned the day of the release'
out_file="$scratch/out-apply-same-day"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.2' "$new_sha" '2026-08-21')" || rc=$?
assert_exit 'apply: a same-day pin exits 0' 0 "$rc"
assert_not_contains 'apply: a same-day pin is not ahead' "$out" 'left as is'
assert_contains 'apply: a same-day pin advances to the tag form' "$(cat "$repo/$guard_caller")" "@${new_sha} # v0.9.2"

# Every enumerated caller ahead of the release is a clean no-op, not a
# failure and not a proposal: the tree stays clean for a later step.
repo="$scratch/repo-all-ahead"
lane_repo "$repo" "$old_sha" 'v0.9.1'
sed -i -E "s|# v0\.9\.1\$|# c136b27 2026-09-09|" "$repo"/components/claude-lanes/*.yml
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'every lane pinned ahead'
out_file="$scratch/out-apply-all-ahead"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.2' "$new_sha" '2026-08-21')" || rc=$?
assert_exit 'apply: every caller ahead exits 0' 0 "$rc"
assert_contains 'apply: every caller ahead reports changed=false' "$(cat "$out_file")" 'changed=false'
assert_contains 'apply: every caller ahead is a notice' "$out" 'ahead of v0.9.2; nothing to propose'
assert_silent 'apply: every caller ahead leaves the tree clean' "$(git -C "$repo" status --porcelain)"

# The date is the comparison's whole basis, so a missing or malformed one is
# refused before any file is touched.
repo="$scratch/repo-bad-date"
lane_repo "$repo" "$old_sha" 'v0.9.1'
rc=0; out="$(run_apply "$repo" "$scratch/out-bad-date" 'v0.9.2' "$new_sha" '21/08/2026')" || rc=$?
assert_nonzero 'apply: a malformed release date is refused' "$rc"
assert_contains 'apply: a malformed release date is named' "$out" '21/08/2026'
assert_silent 'apply: a malformed release date touches nothing' "$(git -C "$repo" status --porcelain)"

# A production-shaped repo that drops one extra must not silently skip it.
repo="$scratch/repo-partial-extras"
lane_repo "$repo" "$old_sha" 'v0.9.1'
mkdir -p "$repo/.github/workflows"
cat > "$repo/.github/workflows/claude-review.yml" <<YAML
name: local-review
on: pull_request
jobs:
  review:
    uses: melodic-software/ci-workflows/.github/workflows/claude-review.yml@${old_sha} # v0.9.1
YAML
cat > "$repo/.github/workflows/standards-sync-stuck-automerge-alert.yml" <<YAML
name: alert
on: schedule
jobs:
  alert:
    uses: melodic-software/ci-workflows/.github/workflows/standards-sync-stuck-automerge-alert.yml@${old_sha} # v0.9.1
YAML
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'partial extras'
out_file="$scratch/out-apply-partial-extras"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.2' "$new_sha")" || rc=$?
assert_nonzero 'apply: a partial extra-caller set is a hard failure' "$rc"
assert_contains 'apply: missing extra caller is named' "$out" 'sync.yml'

# A file that is not in the enumerated set must still fail if the rewrite
# somehow touches it — the extra-caller allowlist is not a blanket LANE_DIR
# exemption.
repo="$scratch/repo-stray"
lane_repo "$repo" "$old_sha" 'v0.9.1'
mkdir -p "$repo/.github/workflows"
printf 'uses: melodic-software/ci-workflows/.github/workflows/zizmor.yml@%s # v0.9.1\n' \
  "$old_sha" > "$repo/.github/workflows/zizmor.yml"
git -C "$repo" add -A
git -C "$repo" -c commit.gpgsign=false -c core.hooksPath= commit -qm 'stray pin'
# Force a stray diff the subject did not intend by rewriting the file after
# the commit so git sees an outside change if the guard is too wide. The
# subject itself must not touch this file; the guard assertion is that a
# non-enumerated path stays unmodified.
out_file="$scratch/out-apply-stray"
rc=0; out="$(run_apply "$repo" "$out_file" 'v0.9.2' "$new_sha")" || rc=$?
assert_exit 'apply: a stray non-enumerated workflow is left alone and apply exits 0' 0 "$rc"
assert_not_contains 'apply: a stray zizmor caller is not rewritten' \
  "$(cat "$repo/.github/workflows/zizmor.yml")" "$new_sha"
assert_eq 'apply: the stray workflow stays byte-identical' \
  "$(git -C "$repo" diff --name-only -- .github/workflows/zizmor.yml)" ''

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
rc=0; out="$(GITHUB_OUTPUT="$scratch/out-usage" bash "$script" apply v1.0.0 "$new_sha" 2>&1)" || rc=$?
assert_nonzero 'apply without the release date is a usage error' "$rc"
assert_contains 'apply usage names the date argument' "$out" '<date>'

[[ $FAILED -eq 0 ]] || exit 1
