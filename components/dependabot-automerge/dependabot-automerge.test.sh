#!/usr/bin/env bash
# Contract tests for the two dependabot-automerge caller components:
# `dependabot-automerge-caller`
# (.github/workflows/pr-automerge-dependabot-hosted.yml) and
# `dependabot-automerge-fleet-caller`
# (.github/workflows/pr-automerge-dependabot.yml).
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

command -v yq >/dev/null 2>&1 || skip_suite 'Mike Farah yq v4 is not installed'
[[ "$(yq --version 2>/dev/null)" =~ version[[:space:]]+v?4\. ]] ||
  skip_suite 'Mike Farah yq v4 is required'

hosted_component='dependabot-automerge-caller'
hosted_source='components/dependabot-automerge/dependabot-automerge.yml'
hosted_destination='.github/workflows/pr-automerge-dependabot-hosted.yml'
fleet_component='dependabot-automerge-fleet-caller'
fleet_source='components/dependabot-automerge/dependabot-automerge-fleet.yml'
fleet_destination='.github/workflows/pr-automerge-dependabot.yml'
manifest='distribution/sync-manifest.yml'
actionlint_config='.github/actionlint.yaml'
reusable_ref='melodic-software/ci-workflows/.github/workflows/pr-automerge-dependabot.yml@main'
# shellcheck disable=SC2016  # GitHub Actions expression compared literally
canonical_group='${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}'

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

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
  local source="$1" component="$2" runner="$3" destination="$4" p="$1:" stem header
  local job='.jobs["pr-automerge-dependabot"]'
  q() { yq -r "$1" "$source"; }

  assert_file_exists "$p the caller component exists" "$source"
  header="$(head -n 12 "$source")"
  assert_contains "$p header marks the file sync-managed" "$header" 'SYNC-MANAGED FILE'
  assert_contains "$p header names the standards source path" "$header" "$source"
  assert_contains "$p header names the manifest component" "$header" "$component"

  stem="${destination##*/}"
  assert_eq "$p workflow name is the destination stem in Title Case" "$(title_case "${stem%.yml}")" "$(q '.name')"
  assert_eq "$p triggers on pull_request only" 'pull_request' "$(q '.on | keys | join(",")')"
  assert_eq "$p workflow permissions is deny-all" '{}' "$(q '.permissions')"

  assert_eq "$p concurrency group is the canonical concurrency-policy expression" \
    "$canonical_group" "$(q '.concurrency.group')"
  assert_eq "$p concurrency cancels in-progress runs" 'true' "$(q '.concurrency["cancel-in-progress"]')"
  assert_eq "$p concurrency block carries exactly the two canonical keys" 'cancel-in-progress,group' \
    "$(q '.concurrency | keys | sort | join(",")')"

  assert_eq "$p exactly one job" '1' "$(q '.jobs | length')"
  assert_eq "$p the job is named pr-automerge-dependabot" 'pr-automerge-dependabot' "$(q '.jobs | keys | .[0]')"
  assert_eq "$p the job display name is PR Automerge Dependabot" \
    'PR Automerge Dependabot' "$(q "$job.name")"
  assert_eq "$p job permissions are contents: write and pull-requests: write only" \
    'contents=write,pull-requests=write' \
    "$(q "$job"'.permissions | to_entries | sort_by(.key) | map(.key + "=" + .value) | join(",")')"
  assert_eq "$p the job calls the ci-workflows reusable at @main" \
    "$reusable_ref" "$(q "$job.uses")"
  assert_eq "$p the job passes runner and nothing else" 'runner' \
    "$(q "$job"'.with | keys | join(",")')"
  assert_eq "$p the job passes the expected literal runner" "$runner" \
    "$(q "$job"'.with.runner')"
  assert_eq "$p no secrets block is forwarded" 'null' "$(q "$job.secrets")"
}

check_shape "$hosted_source" "$hosted_component" 'ubuntu-24.04' "$hosted_destination"
check_shape "$fleet_source" "$fleet_component" 'melodic-ubuntu-24.04-x64' "$fleet_destination"

strip() { grep -vE '^([[:space:]]*(#|runner:)|name:)' "$1"; }
if diff <(strip "$hosted_source") <(strip "$fleet_source") >/dev/null; then
  pass 'the fleet sibling equals the hosted caller apart from comments, the workflow name and runner'
else
  fail 'the fleet sibling equals the hosted caller apart from comments, the workflow name and runner' \
    "$(diff <(strip "$hosted_source") <(strip "$fleet_source"))"
fi

for pair in "$hosted_component:$hosted_source:$hosted_destination" \
  "$fleet_component:$fleet_source:$fleet_destination"; do
  IFS=: read -r c s d <<<"$pair"
  assert_eq "manifest maps $c to its locked destination" "$d" \
    "$(yq -r ".components.\"$c\".files.\"$s\"" "$manifest")"
  assert_eq "$c ships exactly one file" '1' "$(yq -r ".components.\"$c\".files | length" "$manifest")"
  assert_eq "$c requires no component (the reusable reads standards main)" '0' \
    "$(yq -r ".components.\"$c\".requires // [] | length" "$manifest")"
done

mapfile -t all_targets < <(yq -r '.targets | keys[]' "$manifest")

hosted_targets=()
fleet_targets=()
locally_owned_targets=()
for target in "${all_targets[@]}"; do
  mapfile -t managed < <(yq -r ".targets.\"$target\".managed // [] | .[]" "$manifest")
  mapfile -t owned < <(yq -r ".targets.\"$target\".\"locally-owned\" // [] | .[]" "$manifest")
  has_hosted=0 has_fleet=0 owns_caller=0
  for c in "${managed[@]}"; do
    [[ "$c" == "$hosted_component" ]] && has_hosted=1
    [[ "$c" == "$fleet_component" ]] && has_fleet=1
  done
  for c in "${owned[@]}"; do
    [[ "$c" == "$hosted_component" || "$c" == "$fleet_component" ]] && owns_caller=1
  done
  [[ "$has_hosted" -eq 1 && "$has_fleet" -eq 1 ]] &&
    fail "$target manages at most one dependabot-automerge caller" 'manages both the hosted and the fleet-routed caller'
  if [[ "$has_hosted" -eq 1 ]]; then
    hosted_targets+=("$target")
  elif [[ "$has_fleet" -eq 1 ]]; then
    fleet_targets+=("$target")
  elif [[ "$owns_caller" -eq 1 ]]; then
    locally_owned_targets+=("$target")
  fi
done

assert_nonzero 'at least one target manages the hosted caller' "${#hosted_targets[@]}"
assert_nonzero 'at least one target manages the fleet-routed caller' "${#fleet_targets[@]}"
assert_eq 'ci-workflows and medley own dependabot-automerge locally' \
  'melodic-software/ci-workflows,melodic-software/medley' \
  "$(printf '%s\n' "${locally_owned_targets[@]}" | sort | paste -sd, -)"

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
