#!/usr/bin/env bash
# Tests the claude lane caller components at the MATERIALIZED consumer shape:
# the bytes are workflow files that only ever execute after `sync-manifest.sh
# apply` writes them into a consumer's .github/workflows/, and every
# workflow-shaped lane in this repository discovers files by that location, so
# a repo-root scan never sees them. This runs the consumer entrypoint —
# `apply`, then actionlint over the result — instead of linting the component
# in place. Skips cleanly when the engine is absent.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
manifest='distribution/sync-manifest.yml'
config='.github/actionlint.yaml'
source_prefix='components/claude-lanes/'
queue_message='unexpected key "queue" for "concurrency" section'

if ! command -v actionlint >/dev/null 2>&1; then
  skip_suite 'actionlint not installed'
fi
# The `paths` config key shipped in actionlint 1.7.4; older engines reject it.
require_min_version actionlint "$(actionlint -version | head -n 1)" 1.7.4

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

# `apply` verifies the checkout's origin identifies the target it was asked
# for, so a consumer stand-in must carry that remote to reach the copy path at
# all.
consumer_checkout() {
  local target="$1" dir="$2"
  make_repo "$dir"
  git -C "$dir" remote add origin "https://github.com/$target.git"
}

# component<TAB>source<TAB>destination for every lane caller, and the targets
# that manage one. Filtering happens in bash so the yq expressions stay plain
# traversal. Derived from the manifest rather than hardcoded: the security
# caller is parked with no managed target today and is meant to gain one, so
# a fixed count would have to be edited to keep passing.
#
# shellcheck disable=SC2016  # yq expressions; $c/$t are yq variables, not shell
mapfile -t lane_files < <(
  yq -r '.components | to_entries[] | .key as $c | .value.files | to_entries[]
    | $c + "\t" + .key + "\t" + .value' "$manifest" | grep -F "	$source_prefix"
)
assert_nonzero 'manifest carries at least one claude lane caller component' "${#lane_files[@]}"
mapfile -t lane_components < <(printf '%s\n' "${lane_files[@]}" | cut -f1 | sort -u)

declare -A is_lane_component=()
for component in "${lane_components[@]}"; do is_lane_component["$component"]=1; done

# Membership is an exact key lookup, not a substring match: a future component
# named as an extension of an existing one (`claude-review-caller-v2`) would
# match a substring test here and fail the exact test used per target below,
# and that asymmetry would silently drop this target's destination assertions.
# shellcheck disable=SC2016  # yq expression; $t is a yq variable, not shell
mapfile -t target_pairs < <(
  yq -r '.targets | to_entries[] | .key as $t | (.value.managed // [])[] | $t + "\t" + .' "$manifest"
)
declare -A seen_target=()
lane_targets=()
for pair in "${target_pairs[@]}"; do
  IFS=$'\t' read -r target component <<<"$pair"
  [[ -n "${is_lane_component[$component]-}" && -z "${seen_target[$target]-}" ]] || continue
  seen_target["$target"]=1
  lane_targets+=("$target")
done
assert_nonzero 'at least one target manages a lane caller' "${#lane_targets[@]}"

# Every lane caller's bytes at the destination path they take in a consumer,
# whether or not a target manages the component today. The target loop below
# cannot reach a PARKED component — `claude-security-review-caller` has no
# managed target and is kept precisely so its reviewed shape survives until it
# unparks — and bytes nothing lints are bytes nothing protects.
for entry in "${lane_files[@]}"; do
  IFS=$'\t' read -r component source destination <<<"$entry"
  standalone="$scratch/component-$component"
  make_repo "$standalone"
  mkdir -p "$standalone/${destination%/*}"
  cp "$source" "$standalone/$destination"
  cp "$config" "$standalone/$config"
  assert_file_exists "$component materializes at $destination" "$standalone/$destination"
  out="$(cd "$standalone" && actionlint -no-color 2>&1)"
  rc=$?
  assert_exit "$component lints clean at $destination" 0 "$rc"
  assert_silent "$component emits no findings at $destination" "$out"
done

# Every target receiving a lane caller, materialized the way its own sync PR
# materializes it. A target that owns actionlint locally receives no config
# from the manifest, so the canonical one stands in for the local equivalent
# it is required to carry (medley and github-iac both do today) — the
# assertion is that the SHIPPED BYTES lint clean under a conforming config,
# which is the property this repository can own.
for target in "${lane_targets[@]}"; do
  consumer="$scratch/${target##*/}"
  consumer_checkout "$target" "$consumer"
  bash distribution/sync-manifest.sh apply --target "$target" --target-root "$consumer" >/dev/null
  assert_exit "$target materializes" 0 "$?"

  # Skipping a component this target does not manage is correct — most targets
  # manage exactly one caller — but the skip must not be able to swallow every
  # destination assertion silently. Counting what actually ran and asserting
  # the count is what fails closed: a broken lookup, a renamed component, or a
  # membership test that stops matching all surface as a FAIL here rather than
  # as a suite that shrinks quietly and still exits 0.
  mapfile -t managed < <(yq -r ".targets.\"$target\".managed[]" "$manifest")
  declare -A manages=()
  for component in "${managed[@]}"; do manages["$component"]=1; done
  destinations=0
  for entry in "${lane_files[@]}"; do
    IFS=$'\t' read -r component _ destination <<<"$entry"
    [[ -n "${manages[$component]-}" ]] || continue
    destinations=$((destinations + 1))
    assert_file_exists "$target receives $destination" "$consumer/$destination"
  done
  assert_nonzero "$target ran a destination assertion" "$destinations"

  [[ -f "$consumer/$config" ]] || cp "$config" "$consumer/$config"
  out="$(cd "$consumer" && actionlint -no-color 2>&1)"
  rc=$?
  assert_exit "$target lints clean after sync" 0 "$rc"
  assert_silent "$target sync emits no findings" "$out"
done

# Control: the suppression is load-bearing for every one of those targets, not
# a nicety. A target that owns actionlint locally must carry its own
# equivalent or its first sync PR fails its own lane. When this case stops
# failing, the upstream fix shipped — fire the removal trigger recorded in the
# canonical config instead of patching this test.
control="$scratch/no-config"
consumer_checkout "${lane_targets[0]}" "$control"
bash distribution/sync-manifest.sh apply --target "${lane_targets[0]}" --target-root "$control" >/dev/null
rm -f "$control/$config"
out="$(cd "$control" && actionlint -no-color 2>&1)"
rc=$?
assert_nonzero 'a synced lane caller fails actionlint without the suppression' "$rc"
assert_contains 'control run reports the suppressed message' "$out" "$queue_message"

[[ $FAILED -eq 0 ]] || exit 1
