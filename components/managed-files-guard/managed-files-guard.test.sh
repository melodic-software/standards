#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

command -v yq >/dev/null 2>&1 || skip_suite 'Mike Farah yq v4 is not installed'
[[ "$(yq --version 2>/dev/null)" =~ version[[:space:]]+v?4\. ]] ||
  skip_suite 'Mike Farah yq v4 is required'

hosted_component='managed-files-guard-caller'
hosted_source='components/managed-files-guard/managed-files-guard.yml'
hosted_destination='.github/workflows/pr-check-managed-files-hosted.yml'
fleet_component='managed-files-guard-fleet-caller'
fleet_source='components/managed-files-guard/managed-files-guard-fleet.yml'
fleet_destination='.github/workflows/pr-check-managed-files.yml'
manifest='distribution/sync-manifest.yml'
actionlint_config='.github/actionlint.yaml'
action_path='melodic-software/ci-workflows/.github/actions/check-managed-files'
# shellcheck disable=SC2016  # a GitHub Actions expression, compared literally
canonical_group='${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}'

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

mapfile -t all_targets < <(yq -r '.targets | keys[]' "$manifest")

dest_paths_failures=''
for t in "${all_targets[@]}"; do
  bash distribution/sync-manifest.sh dest-paths --source-root "$root" --target "$t" >/dev/null ||
    dest_paths_failures+="$t "
done
assert_eq 'the engine lists dest-paths for every target' '' "$dest_paths_failures"

title_case() {
  local words word title=''
  IFS=- read -r -a words <<<"$1"
  for word in "${words[@]}"; do
    case "$word" in
      pr | ci | api | wip) word="${word^^}" ;;
      *) word="${word^}" ;;
    esac
    title+="${title:+ }$word"
  done
  printf '%s' "$title"
}

check_shape() {
  local source="$1" component="$2" runs_on="$3" destination="$4" p="$1:" stem header
  local job='.jobs["pr-check-managed-files"]'
  q() { yq -r "$1" "$source"; }

  assert_file_exists "$p the caller component exists" "$source"
  header="$(head -n 12 "$source")"
  assert_contains "$p header marks the file sync-managed" "$header" 'SYNC-MANAGED FILE'
  assert_contains "$p header names the standards source path" "$header" "$source"
  assert_contains "$p header names the manifest component" "$header" "$component"

  stem="${destination##*/}"
  assert_eq "$p workflow name is the destination stem in Title Case" "$(title_case "${stem%.yml}")" "$(q '.name')"
  assert_eq "$p triggers on pull_request only" 'pull_request' "$(q '.on | keys | join(",")')"
  assert_eq "$p pull_request carries types only (no paths filter)" 'types' \
    "$(q '.on.pull_request | keys | join(",")')"
  assert_eq "$p pull_request types are the diff-changing default" 'opened,synchronize,reopened' \
    "$(q '.on.pull_request.types | join(",")')"
  assert_eq "$p workflow token is contents: read and pull-requests: read and nothing else" 'contents=read,pull-requests=read' \
    "$(q '.permissions | to_entries | map(.key + "=" + .value) | join(",")')"

  assert_eq "$p concurrency group is the canonical concurrency-policy expression" \
    "$canonical_group" "$(q '.concurrency.group')"
  assert_eq "$p concurrency cancels in-progress runs" 'true' "$(q '.concurrency["cancel-in-progress"]')"
  assert_eq "$p concurrency block carries exactly the two canonical keys" 'cancel-in-progress,group' \
    "$(q '.concurrency | keys | sort | join(",")')"

  assert_eq "$p exactly one job" '1' "$(q '.jobs | length')"
  assert_eq "$p the job is named pr-check-managed-files" 'pr-check-managed-files' "$(q '.jobs | keys | .[0]')"
  assert_eq "$p the job display name is the Title Case of its id (check context is PR Check Managed Files)" \
    'PR Check Managed Files' "$(q "$job.name")"
  assert_eq "$p the job runs on $runs_on directly" "$runs_on" \
    "$(q "$job"'["runs-on"]')"
  assert_eq "$p the job has a 10-minute timeout" '10' "$(q "$job"'["timeout-minutes"]')"
  assert_eq "$p no job calls a reusable workflow" '0' "$(q '[.jobs[] | select(has("uses"))] | length')"
  assert_eq "$p runs-on is a literal, not an expression" '0' \
    "$(q '[.jobs[]["runs-on"] | select(test("\\$\\{\\{"))] | length')"
  assert_eq "$p no job-level permissions block (the workflow grant is the whole grant)" '0' \
    "$(q '[.jobs[] | select(has("permissions"))] | length')"

  assert_eq "$p one step: the guard" '1' "$(q "$job.steps | length")"

  local guard_uses
  guard_uses="$(q "$job.steps[0].uses")"
  assert_contains "$p the step calls the ci-workflows check-managed-files action" "$guard_uses" "${action_path}@"
  assert_eq "$p guard action floats on main" "${action_path}@main" "$guard_uses"
  assert_eq "$p guard action uses line is unique in the file" '1' \
    "$(grep -c "uses: ${action_path}@" "$source")"
  assert_eq "$p standards-ref is main for the soak" 'main' \
    "$(q "$job"'.steps[0].with["standards-ref"]')"
  assert_eq "$p the guard step passes standards-ref and nothing else" 'standards-ref' \
    "$(q "$job"'.steps[0].with | keys | join(",")')"
}

check_shape "$hosted_source" "$hosted_component" 'ubuntu-24.04' "$hosted_destination"
check_shape "$fleet_source" "$fleet_component" 'melodic-ubuntu-24.04-x64' "$fleet_destination"

strip() { grep -vE '^([[:space:]]*(#|runs-on:)|name:)' "$1"; }
if diff <(strip "$hosted_source") <(strip "$fleet_source") >/dev/null; then
  pass 'the fleet sibling equals the hosted caller apart from comments, the workflow name and runs-on'
else
  fail 'the fleet sibling equals the hosted caller apart from comments, the workflow name and runs-on' \
    "$(diff <(strip "$hosted_source") <(strip "$fleet_source"))"
fi

for pair in "$hosted_component:$hosted_source:$hosted_destination" \
  "$fleet_component:$fleet_source:$fleet_destination"; do
  IFS=: read -r c s d <<<"$pair"
  assert_eq "manifest maps $c to its locked destination" "$d" \
    "$(yq -r ".components.\"$c\".files.\"$s\"" "$manifest")"
  assert_eq "$c ships exactly one file" '1' "$(yq -r ".components.\"$c\".files | length" "$manifest")"
done

# Every claude-lanes-sourced (fleet-routed) caller component.
# shellcheck disable=SC2016  # yq expression; $c is a yq variable, not shell
mapfile -t lane_components < <(
  yq -r '.components | to_entries[] | .key as $c | .value.files | keys[] | $c + "\t" + .' "$manifest" |
    grep -F $'\tcomponents/claude-lanes/' | cut -f1 | sort -u
)
assert_nonzero 'manifest carries at least one fleet-routed lane caller' "${#lane_components[@]}"
declare -A is_lane_component=()
for c in "${lane_components[@]}"; do is_lane_component["$c"]=1; done

hosted_targets=()
fleet_targets=()
locally_owned_targets=()
unaccounted=()
for target in "${all_targets[@]}"; do
  mapfile -t managed < <(yq -r ".targets.\"$target\".managed // [] | .[]" "$manifest")
  mapfile -t owned < <(yq -r ".targets.\"$target\".\"locally-owned\" // [] | .[]" "$manifest")
  has_hosted=0 has_fleet=0 owns_guard=0 routes_fleet=0
  for c in "${managed[@]}"; do
    [[ "$c" == "$hosted_component" ]] && has_hosted=1
    [[ "$c" == "$fleet_component" ]] && has_fleet=1
    [[ -n "${is_lane_component[$c]-}" ]] && routes_fleet=1
  done
  for c in "${owned[@]}"; do
    [[ "$c" == "$hosted_component" || "$c" == "$fleet_component" ]] && owns_guard=1
  done
  [[ "$has_hosted" -eq 1 && "$has_fleet" -eq 1 ]] &&
    fail "$target manages at most one guard caller" 'manages both the hosted and the fleet-routed caller'
  if [[ "$routes_fleet" -eq 1 ]]; then
    assert_eq "$target manages a fleet-routed lane caller, so it manages the fleet guard" '1' "$has_fleet"
    assert_eq "$target manages a fleet-routed lane caller, so not the hosted guard" '0' "$has_hosted"
  fi
  if [[ "$has_hosted" -eq 1 ]]; then
    hosted_targets+=("$target")
  elif [[ "$has_fleet" -eq 1 ]]; then
    fleet_targets+=("$target")
  elif [[ "$owns_guard" -eq 1 ]]; then
    locally_owned_targets+=("$target")
  else
    unaccounted+=("$target")
  fi
done

assert_nonzero 'at least one target manages the hosted caller' "${#hosted_targets[@]}"
assert_nonzero 'at least one target manages the fleet-routed caller' "${#fleet_targets[@]}"
assert_eq 'ci-workflows owns the guard locally (it runs the action from its own tree)' \
  'melodic-software/ci-workflows' "$(printf '%s\n' "${locally_owned_targets[@]}" | paste -sd, -)"
assert_eq 'every sync target is covered: hosted, fleet-routed, or locally-owned' \
  '' "$(printf '%s\n' "${unaccounted[@]-}" | paste -sd, -)"

have_actionlint=0
if command -v actionlint >/dev/null 2>&1; then
  have_actionlint=1
else
  skip_case 'actionlint not installed; the materialized callers are not linted'
fi

materialize() {
  local target="$1" source="$2" destination="$3" absent="$4" consumer out rc
  consumer="$scratch/${target##*/}"
  make_repo "$consumer"
  git -C "$consumer" remote add origin "https://github.com/$target.git"
  bash distribution/sync-manifest.sh apply --target "$target" --target-root "$consumer" >/dev/null
  assert_exit "$target materializes" 0 "$?"
  assert_file_absent "$target receives no $absent" "$consumer/$absent"
  [[ -n "$source" ]] || return 0
  assert_file_exists "$target receives $destination" "$consumer/$destination"
  if cmp -s "$source" "$consumer/$destination"; then
    pass "$target receives the component bytes unchanged"
  else
    fail "$target receives the component bytes unchanged" "destination differs from $source"
  fi
  if [[ "$have_actionlint" -eq 1 ]]; then
    [[ -f "$consumer/$actionlint_config" ]] || cp "$actionlint_config" "$consumer/$actionlint_config"
    out="$(cd "$consumer" && actionlint -no-color 2>&1)"
    rc=$?
    assert_exit "$target lints clean after sync" 0 "$rc"
    assert_silent "$target sync emits no findings" "$out"
  fi
}

for target in "${hosted_targets[@]}"; do
  materialize "$target" "$hosted_source" "$hosted_destination" "$fleet_destination"
done
for target in "${fleet_targets[@]}"; do
  materialize "$target" "$fleet_source" "$fleet_destination" "$hosted_destination"
done
for target in "${locally_owned_targets[@]}"; do
  materialize "$target" '' '' "$hosted_destination"
  assert_file_absent "$target (locally-owned) receives no fleet caller" \
    "$scratch/${target##*/}/$fleet_destination"
done

[[ $FAILED -eq 0 ]] || exit 1
