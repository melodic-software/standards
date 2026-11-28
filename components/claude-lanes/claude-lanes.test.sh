#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1
manifest='distribution/sync-manifest.yml'
config='.github/actionlint.yaml'
source_prefix_re='components/claude-lanes(-hosted)?/'

if ! command -v actionlint >/dev/null 2>&1; then
  skip_suite 'actionlint not installed'
fi
# The `paths` config key shipped in actionlint 1.7.4; older engines reject it:
# https://github.com/rhysd/actionlint/blob/main/CHANGELOG.md
require_min_version actionlint "$(actionlint -version | awk 'NR == 1 { print $NF }')" 1.7.4

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

consumer_checkout() {
  local target="$1" dir="$2"
  make_repo "$dir"
  git -C "$dir" remote add origin "https://github.com/$target.git"
}

lint_clean() {
  local out rc
  out="$(cd "$1" && actionlint -no-color 2>&1)"
  rc=$?
  assert_exit "$2" 0 "$rc"
  assert_silent "$3" "$out"
}

# shellcheck disable=SC2016  # yq expressions; $c/$t are yq variables, not shell
mapfile -t lane_files < <(
  yq -r '.components | to_entries[] | .key as $c | .value.files | to_entries[]
    | $c + "\t" + .key + "\t" + .value' "$manifest" | grep -E "	$source_prefix_re"
)
assert_nonzero 'manifest carries at least one claude lane caller component' "${#lane_files[@]}"
mapfile -t lane_components < <(printf '%s\n' "${lane_files[@]}" | cut -f1 | sort -u)

declare -A is_lane_component=()
for component in "${lane_components[@]}"; do is_lane_component["$component"]=1; done

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

for entry in "${lane_files[@]}"; do
  IFS=$'\t' read -r component source destination <<<"$entry"
  standalone="$scratch/component-$component"
  make_repo "$standalone"
  mkdir -p "$standalone/${destination%/*}"
  cp "$source" "$standalone/$destination"
  cp "$config" "$standalone/$config"
  assert_file_exists "$component materializes at $destination" "$standalone/$destination"
  lint_clean "$standalone" "$component lints clean at $destination" \
    "$component emits no findings at $destination"
done

for target in "${lane_targets[@]}"; do
  consumer="$scratch/${target##*/}"
  consumer_checkout "$target" "$consumer"
  bash distribution/sync-manifest.sh apply --target "$target" --target-root "$consumer" >/dev/null
  assert_exit "$target materializes" 0 "$?"

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
  lint_clean "$consumer" "$target lints clean after sync" "$target sync emits no findings"
done

[[ $FAILED -eq 0 ]] || exit 1
