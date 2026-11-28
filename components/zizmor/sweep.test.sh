#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
config="$root/.github/zizmor.yml"
fixtures='components/zizmor/fixtures'
sweep='components/zizmor/sweep.sh'

if ! command -v zizmor >/dev/null 2>&1; then
  skip_suite 'zizmor not installed'
fi
version_output="$(zizmor --version)"
require_min_version zizmor "${version_output##* }" 1.29.0

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
checkout() { mkdir -p "$scratch/$1/.github/workflows" && cp "${@:2}" "$scratch/$1/.github/workflows/"; }
checkout clean "$fixtures/good/first-party-float.yml" "$fixtures/sweep/other-finding.yml"
checkout dirty "$fixtures/bad/third-party-tag.yml"
checkout ignored "$fixtures/sweep/ignored-tag.yml"
mkdir -p "$scratch/empty/.github"

out="$(bash "$sweep" --config "$config" "$scratch/clean" "$scratch/empty" 2>&1)"
rc=$?
assert_exit 'a clean checkout and one with no workflows pass' 0 "$rc"
assert_contains 'the clean checkout is reported clean' "$out" 'CLEAN: clean'
assert_contains 'the empty checkout is skipped' "$out" 'NO-INPUTS: empty'
assert_not_contains 'another audit finding is dropped' "$out" 'UNPINNED'

out="$(bash "$sweep" --config "$config" "$scratch/clean" "$scratch/dirty" "$scratch/ignored" 2>&1)"
rc=$?
assert_exit 'a third-party tag fails the sweep' 1 "$rc"
assert_contains 'the finding names repository, path and line' "$out" \
  'UNPINNED: dirty: .github/workflows/third-party-tag.yml:8: '
assert_contains 'an ignore comment does not hide the finding' "$out" \
  'UNPINNED: ignored: .github/workflows/ignored-tag.yml:8: docker/setup-buildx-action@v3'
assert_contains 'the clean checkout stays clean beside them' "$out" 'CLEAN: clean'

out="$(bash "$sweep" --config "$config" "$scratch/missing" 2>&1)"
rc=$?
assert_exit 'a missing checkout is a tool error' 2 "$rc"

out="$(bash "$sweep" "$scratch/clean" 2>&1)"
rc=$?
assert_exit 'no config is a usage error' 2 "$rc"

[[ $FAILED -eq 0 ]] || exit 1
