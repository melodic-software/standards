#!/usr/bin/env bash
# Contract tests for the managed-files-guard caller component: the workflow
# bytes the `managed-files-guard-caller` manifest component ships to every
# hosted-only-eligible target's .github/workflows/managed-files-guard.yml.
#
# Three layers, in order:
#   1. Shape — the parsed YAML carries exactly the locked design: pull_request
#      trigger, read-only token, the canonical concurrency block, one hosted
#      job with no selector, a full-history checkout, and the composite action
#      pinned by full SHA under the pin-comment convention with
#      `standards-ref: main` for the soak.
#   2. Manifest wiring — the component maps to the locked destination, is
#      managed only for hosted-only-eligible targets (never alongside a
#      selector-routed lane caller), is `locally-owned` by ci-workflows, and
#      accounts for every target one way or another.
#   3. Materialization — the engine writes the bytes where the manifest says,
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

component='managed-files-guard-caller'
source='components/managed-files-guard/managed-files-guard.yml'
destination='.github/workflows/managed-files-guard.yml'
manifest='distribution/sync-manifest.yml'
actionlint_config='.github/actionlint.yaml'
action_path='melodic-software/ci-workflows/.github/actions/managed-files-guard'
# shellcheck disable=SC2016  # a GitHub Actions expression, compared literally
canonical_group='${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}'

# shellcheck source=components/pin-comment-convention/pin-comment-patterns.sh
source "$root/components/pin-comment-convention/pin-comment-patterns.sh"

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

assert_file_exists 'the caller component exists' "$source"

# q <expr> — evaluate a yq expression against the caller, raw output.
q() { yq -r "$1" "$source"; }

# ------------------------------------------------------------------ 1. shape

assert_contains 'header marks the file sync-managed' "$(head -n 12 "$source")" 'SYNC-MANAGED FILE'
assert_contains 'header names the standards source path' "$(head -n 12 "$source")" "$source"
assert_contains 'header names the manifest component' "$(head -n 12 "$source")" "$component"

assert_eq 'workflow name is managed-files-guard' 'managed-files-guard' "$(q '.name')"
assert_eq 'triggers on pull_request only' 'pull_request' "$(q '.on | keys | join(",")')"
assert_eq 'workflow token is contents: read and nothing else' 'contents=read' \
  "$(q '.permissions | to_entries | map(.key + "=" + .value) | join(",")')"

assert_eq 'concurrency group is the canonical concurrency-policy expression' \
  "$canonical_group" "$(q '.concurrency.group')"
assert_eq 'concurrency cancels in-progress runs' 'true' "$(q '.concurrency["cancel-in-progress"]')"
assert_eq 'concurrency block carries exactly the two canonical keys' 'cancel-in-progress,group' \
  "$(q '.concurrency | keys | sort | join(",")')"

assert_eq 'exactly one job' '1' "$(q '.jobs | length')"
assert_eq 'the job is named managed-files-guard' 'managed-files-guard' "$(q '.jobs | keys | .[0]')"
assert_eq 'the job runs on the approved hosted label directly' 'ubuntu-24.04' \
  "$(q '.jobs["managed-files-guard"]["runs-on"]')"
assert_eq 'the job has a 10-minute timeout' '10' "$(q '.jobs["managed-files-guard"]["timeout-minutes"]')"
assert_eq 'no job calls a reusable workflow' '0' "$(q '[.jobs[] | select(has("uses"))] | length')"
# Tree positions only: the header prose legitimately NAMES the selector while
# explaining why the file does not use it.
assert_eq 'no uses: anywhere references select-runner' '0' \
  "$(q '[.jobs[] | .uses, .steps[].uses] | map(select(. != null and test("select-runner"))) | length')"
assert_eq 'runs-on is a literal, not an expression' '0' \
  "$(q '[.jobs[]["runs-on"] | select(test("\\$\\{\\{"))] | length')"
assert_eq 'no job-level permissions block (the workflow grant is the whole grant)' '0' \
  "$(q '[.jobs[] | select(has("permissions"))] | length')"

steps="$(q '.jobs["managed-files-guard"].steps | length')"
assert_eq 'two steps: checkout, then the guard' '2' "$steps"

checkout_uses="$(q '.jobs["managed-files-guard"].steps[0].uses')"
sibling_checkout="$(yq -r '.jobs.repin.steps[] | select(.uses | test("^actions/checkout@")) | .uses' \
  .github/workflows/claude-lanes-repin.yml)"
assert_contains 'first step is actions/checkout' "$checkout_uses" 'actions/checkout@'
assert_eq 'checkout is pinned to the same SHA as the sibling workflows' "$sibling_checkout" "$checkout_uses"
if [[ "$checkout_uses" =~ @[0-9a-f]{40}$ ]]; then
  pass 'checkout pin is a full 40-character SHA'
else
  fail 'checkout pin is a full 40-character SHA' "got $checkout_uses"
fi
assert_eq 'checkout does not persist credentials' 'false' \
  "$(q '.jobs["managed-files-guard"].steps[0].with["persist-credentials"]')"
assert_eq 'checkout fetches full history so the guard can diff base...head' '0' \
  "$(q '.jobs["managed-files-guard"].steps[0].with["fetch-depth"]')"

guard_uses="$(q '.jobs["managed-files-guard"].steps[1].uses')"
assert_contains 'second step calls the ci-workflows managed-files-guard action' "$guard_uses" "${action_path}@"
guard_sha="${guard_uses##*@}"
if [[ "$guard_sha" =~ ^[0-9a-f]{40}$ ]]; then
  pass 'guard action pin is a full lowercase 40-character SHA'
else
  fail 'guard action pin is a full lowercase 40-character SHA' "got $guard_sha"
fi
assert_eq 'guard action pin line is unique in the file' '1' \
  "$(grep -c "uses: ${action_path}@" "$source")"
assert_eq 'standards-ref is main for the soak' 'main' \
  "$(q '.jobs["managed-files-guard"].steps[1].with["standards-ref"]')"
assert_eq 'the guard step passes standards-ref and nothing else' 'standards-ref' \
  "$(q '.jobs["managed-files-guard"].steps[1].with | keys | join(",")')"

# The pin comment: exactly one of the convention's two forms, checked by the
# convention's own library. A bare SHA, prose, or a fallback short-sha that
# does not prefix the pin all fail here.
rc=0
out="$(pcc::scan_text "$(<"$source")")" || rc=$?
assert_exit 'the ci-workflows pin carries a convention-conforming comment' 0 "$rc"
assert_silent 'the pin-comment scan reports no violation' "$out"

# ------------------------------------------------------- 2. manifest wiring

assert_eq 'manifest maps the component source to the locked destination' "$destination" \
  "$(yq -r ".components.\"$component\".files.\"$source\"" "$manifest")"
assert_eq 'the component ships exactly one file' '1' \
  "$(yq -r ".components.\"$component\".files | length" "$manifest")"

# component<TAB>source for every claude-lanes-sourced (selector-routed) caller.
# shellcheck disable=SC2016  # yq expression; $c is a yq variable, not shell
mapfile -t selector_components < <(
  yq -r '.components | to_entries[] | .key as $c | .value.files | keys[] | $c + "\t" + .' "$manifest" |
    grep -F $'\tcomponents/claude-lanes/' | cut -f1 | sort -u
)
assert_nonzero 'manifest carries at least one selector-routed lane caller to exclude against' \
  "${#selector_components[@]}"
declare -A is_selector_component=()
for c in "${selector_components[@]}"; do is_selector_component["$c"]=1; done

mapfile -t all_targets < <(yq -r '.targets | keys[]' "$manifest")
managed_targets=()
locally_owned_targets=()
unaccounted=()
for target in "${all_targets[@]}"; do
  mapfile -t managed < <(yq -r ".targets.\"$target\".managed // [] | .[]" "$manifest")
  mapfile -t owned < <(yq -r ".targets.\"$target\".\"locally-owned\" // [] | .[]" "$manifest")
  has_guard=0
  owns_guard=0
  routes_selector=0
  for c in "${managed[@]}"; do
    [[ "$c" == "$component" ]] && has_guard=1
    [[ -n "${is_selector_component[$c]-}" ]] && routes_selector=1
  done
  for c in "${owned[@]}"; do
    [[ "$c" == "$component" ]] && owns_guard=1
  done
  if [[ "$has_guard" -eq 1 ]]; then
    managed_targets+=("$target")
    # A target that manages a selector-routed lane caller is a private repo
    # enrolled for local routing, where a fixed hosted job fails
    # runner-policy — the second hop's sibling serves it, not this file.
    assert_eq "$target manages the hosted-only caller and no selector-routed lane caller" '0' "$routes_selector"
  elif [[ "$owns_guard" -eq 1 ]]; then
    locally_owned_targets+=("$target")
  elif [[ "$routes_selector" -eq 1 ]]; then
    : # deferred to the selector-routed sibling; accounted for
  else
    unaccounted+=("$target")
  fi
done

assert_nonzero 'at least one target manages the caller' "${#managed_targets[@]}"
assert_eq 'ci-workflows owns the guard locally (it runs the action from its own tree)' \
  'melodic-software/ci-workflows' "$(printf '%s\n' "${locally_owned_targets[@]}" | paste -sd, -)"
assert_eq 'every sync target is covered: managed, locally-owned, or deferred to the selector-routed hop' \
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

for target in "${managed_targets[@]}"; do
  consumer="$scratch/${target##*/}"
  consumer_checkout "$target" "$consumer"
  bash distribution/sync-manifest.sh apply --target "$target" --target-root "$consumer" >/dev/null
  assert_exit "$target materializes" 0 "$?"
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
done

# A target that owns the guard locally must receive nothing at the destination.
for target in "${locally_owned_targets[@]}"; do
  consumer="$scratch/${target##*/}"
  consumer_checkout "$target" "$consumer"
  bash distribution/sync-manifest.sh apply --target "$target" --target-root "$consumer" >/dev/null
  assert_exit "$target materializes" 0 "$?"
  assert_file_absent "$target (locally-owned) receives no caller" "$consumer/$destination"
done

[[ $FAILED -eq 0 ]] || exit 1
