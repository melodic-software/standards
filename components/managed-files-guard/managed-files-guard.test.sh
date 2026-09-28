#!/usr/bin/env bash
# Contract tests for the two managed-files-guard caller components: the
# hosted `managed-files-guard-caller` (.github/workflows/managed-files-guard.yml)
# and the fleet-routed `managed-files-guard-fleet-caller`
# (.github/workflows/managed-files-guard-fleet.yml).
#
# Three layers, in order:
#   1. Shape: each parsed YAML carries exactly the locked design: pull_request
#      trigger, read-only token, the canonical concurrency block, one job on
#      its approved label, a full-history checkout, and the composite action
#      pinned by full SHA under the pin-comment convention with
#      `standards-ref: main` for the soak. The two files differ only in
#      `runs-on` and comments.
#   2. Manifest wiring: each component maps to its locked destination; a
#      target that manages a `components/claude-lanes/`-sourced caller takes
#      the fleet sibling, never the hosted caller; no target manages both;
#      ci-workflows owns the guard locally; every target is accounted for.
#   3. Materialization: the engine writes the bytes where the manifest says,
#      byte-identical, and (when actionlint is present) they lint clean there.
#
# yq v4 parses the YAML so the assertions are about the tree, not about text
# a comment could imitate; the pin-comment check reuses the convention's own
# library rather than re-deriving its grammar.
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
hosted_destination='.github/workflows/managed-files-guard.yml'
fleet_component='managed-files-guard-fleet-caller'
fleet_source='components/managed-files-guard/managed-files-guard-fleet.yml'
fleet_destination='.github/workflows/managed-files-guard-fleet.yml'
manifest='distribution/sync-manifest.yml'
actionlint_config='.github/actionlint.yaml'
action_path='melodic-software/ci-workflows/.github/actions/managed-files-guard'
# shellcheck disable=SC2016  # a GitHub Actions expression, compared literally
canonical_group='${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}'

# shellcheck source=components/pin-comment-convention/pin-comment-patterns.sh
source "$root/components/pin-comment-convention/pin-comment-patterns.sh"

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

sibling_checkout="$(yq -r '.jobs.repin.steps[] | select(.uses | test("^actions/checkout@")) | .uses' \
  .github/workflows/claude-lanes-repin.yml)"

# ------------------------------------------------------------------ 1. shape

# check_shape <source> <component> <runs-on>: the locked design, per file.
check_shape() {
  local source="$1" component="$2" runs_on="$3" p="$1:"
  q() { yq -r "$1" "$source"; }

  assert_file_exists "$p the caller component exists" "$source"
  assert_contains "$p header marks the file sync-managed" "$(head -n 12 "$source")" 'SYNC-MANAGED FILE'
  assert_contains "$p header names the standards source path" "$(head -n 12 "$source")" "$source"
  assert_contains "$p header names the manifest component" "$(head -n 12 "$source")" "$component"

  assert_eq "$p workflow name is managed-files-guard" 'managed-files-guard' "$(q '.name')"
  assert_eq "$p triggers on pull_request only" 'pull_request' "$(q '.on | keys | join(",")')"
  assert_eq "$p workflow token is contents: read and nothing else" 'contents=read' \
    "$(q '.permissions | to_entries | map(.key + "=" + .value) | join(",")')"

  assert_eq "$p concurrency group is the canonical concurrency-policy expression" \
    "$canonical_group" "$(q '.concurrency.group')"
  assert_eq "$p concurrency cancels in-progress runs" 'true' "$(q '.concurrency["cancel-in-progress"]')"
  assert_eq "$p concurrency block carries exactly the two canonical keys" 'cancel-in-progress,group' \
    "$(q '.concurrency | keys | sort | join(",")')"

  assert_eq "$p exactly one job" '1' "$(q '.jobs | length')"
  assert_eq "$p the job is named managed-files-guard" 'managed-files-guard' "$(q '.jobs | keys | .[0]')"
  assert_eq "$p the job display name equals its id (check context stays managed-files-guard)" \
    'managed-files-guard' "$(q '.jobs["managed-files-guard"].name')"
  assert_eq "$p the job runs on $runs_on directly" "$runs_on" \
    "$(q '.jobs["managed-files-guard"]["runs-on"]')"
  assert_eq "$p the job has a 10-minute timeout" '10' "$(q '.jobs["managed-files-guard"]["timeout-minutes"]')"
  assert_eq "$p no job calls a reusable workflow" '0' "$(q '[.jobs[] | select(has("uses"))] | length')"
  assert_eq "$p runs-on is a literal, not an expression" '0' \
    "$(q '[.jobs[]["runs-on"] | select(test("\\$\\{\\{"))] | length')"
  assert_eq "$p no job-level permissions block (the workflow grant is the whole grant)" '0' \
    "$(q '[.jobs[] | select(has("permissions"))] | length')"

  assert_eq "$p two steps: checkout, then the guard" '2' "$(q '.jobs["managed-files-guard"].steps | length')"

  local checkout_uses guard_uses guard_sha rc out
  checkout_uses="$(q '.jobs["managed-files-guard"].steps[0].uses')"
  assert_contains "$p first step is actions/checkout" "$checkout_uses" 'actions/checkout@'
  assert_eq "$p checkout is pinned to the same SHA as the sibling workflows" "$sibling_checkout" "$checkout_uses"
  if [[ "$checkout_uses" =~ @[0-9a-f]{40}$ ]]; then
    pass "$p checkout pin is a full 40-character SHA"
  else
    fail "$p checkout pin is a full 40-character SHA" "got $checkout_uses"
  fi
  assert_eq "$p checkout does not persist credentials" 'false' \
    "$(q '.jobs["managed-files-guard"].steps[0].with["persist-credentials"]')"
  assert_eq "$p checkout fetches full history so the guard can diff base...head" '0' \
    "$(q '.jobs["managed-files-guard"].steps[0].with["fetch-depth"]')"

  guard_uses="$(q '.jobs["managed-files-guard"].steps[1].uses')"
  assert_contains "$p second step calls the ci-workflows managed-files-guard action" "$guard_uses" "${action_path}@"
  guard_sha="${guard_uses##*@}"
  if [[ "$guard_sha" =~ ^[0-9a-f]{40}$ ]]; then
    pass "$p guard action pin is a full lowercase 40-character SHA"
  else
    fail "$p guard action pin is a full lowercase 40-character SHA" "got $guard_sha"
  fi
  assert_eq "$p guard action pin line is unique in the file" '1' \
    "$(grep -c "uses: ${action_path}@" "$source")"
  assert_eq "$p standards-ref is main for the soak" 'main' \
    "$(q '.jobs["managed-files-guard"].steps[1].with["standards-ref"]')"
  assert_eq "$p the guard step passes standards-ref and nothing else" 'standards-ref' \
    "$(q '.jobs["managed-files-guard"].steps[1].with | keys | join(",")')"

  # The pin comment: exactly one of the convention's two forms, checked by the
  # convention's own library. A bare SHA, prose, or a fallback short-sha that
  # does not prefix the pin all fail here.
  rc=0
  out="$(pcc::scan_text "$(<"$source")")" || rc=$?
  assert_exit "$p the ci-workflows pin carries a convention-conforming comment" 0 "$rc"
  assert_silent "$p the pin-comment scan reports no violation" "$out"
}

check_shape "$hosted_source" "$hosted_component" 'ubuntu-24.04'
check_shape "$fleet_source" "$fleet_component" 'melodic-ubuntu-24.04-x64'

# Beyond comments and `runs-on`, the siblings are the same bytes, so one pin
# advance and one review cover both.
pin_of() { grep -oE "${action_path}@[0-9a-f]{40}" "$1"; }
assert_eq 'the fleet sibling pins the same guard action SHA as the hosted caller' \
  "$(pin_of "$hosted_source")" "$(pin_of "$fleet_source")"
strip() { grep -vE '^[[:space:]]*(#|runs-on:)' "$1"; }
if diff <(strip "$hosted_source") <(strip "$fleet_source") >/dev/null; then
  pass 'the fleet sibling equals the hosted caller apart from comments and runs-on'
else
  fail 'the fleet sibling equals the hosted caller apart from comments and runs-on' \
    "$(diff <(strip "$hosted_source") <(strip "$fleet_source"))"
fi

# ------------------------------------------------------- 2. manifest wiring

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

mapfile -t all_targets < <(yq -r '.targets | keys[]' "$manifest")
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
  # A target that manages a fleet-routed lane caller is a private repo
  # enrolled for local routing, where a fixed hosted job fails runner-policy:
  # it takes the fleet sibling, never the hosted caller.
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

# ------------------------------------------------------ 3. materialization

have_actionlint=0
if command -v actionlint >/dev/null 2>&1; then
  have_actionlint=1
else
  skip_case 'actionlint not installed; the materialized callers are not linted'
fi

consumer_checkout() {
  local target="$1" dir="$2"
  make_repo "$dir"
  git -C "$dir" remote add origin "https://github.com/$target.git"
}

# materialize <target> <expected source> <expected destination> <absent destination>
materialize() {
  local target="$1" source="$2" destination="$3" absent="$4" consumer out rc
  consumer="$scratch/${target##*/}"
  consumer_checkout "$target" "$consumer"
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
# A target that owns the guard locally must receive neither caller.
for target in "${locally_owned_targets[@]}"; do
  materialize "$target" '' '' "$hosted_destination"
  assert_file_absent "$target (locally-owned) receives no fleet caller" \
    "$scratch/${target##*/}/$fleet_destination"
done

[[ $FAILED -eq 0 ]] || exit 1
