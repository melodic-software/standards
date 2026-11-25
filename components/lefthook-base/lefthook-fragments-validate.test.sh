#!/usr/bin/env bash
# The root lefthook.yml extends no component fragment, so `lefthook validate`
# on the root no longer loads them. Validate each components/lefthook-*/lefthook.yml
# on its own: a scratch consumer extends just that fragment and runs
# `lefthook validate`. A self-check plants an unknown key and expects a failure,
# so the loop cannot pass vacuously.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# validate_fragment <fragment-file> <scratch-name>: exit status of lefthook validate.
validate_fragment() {
  local repo="$work/$2"
  make_repo "$repo"
  mkdir -p "$repo/.lefthook"
  cp "$1" "$repo/.lefthook/fragment.yml"
  printf 'extends:\n  - .lefthook/fragment.yml\n' >"$repo/lefthook.yml"
  (cd "$repo" && lefthook validate >/dev/null 2>&1)
}

count=0
for fragment in "$root"/components/lefthook-*/lefthook.yml; do
  name="${fragment#"$root"/components/}"
  validate_fragment "$fragment" "${name%%/*}"
  assert_exit "lefthook validate accepts $name" 0 "$?"
  count=$((count + 1))
done
assert_eq 'every lefthook component fragment was validated' \
  "$(find "$root/components" -path '*/lefthook-*/lefthook.yml' | wc -l | tr -d ' ')" "$count"

# Self-check: an unknown key (commands renamed) in a fragment fails validation.
sed 's/^  commands:$/  xcommandsx:/' "$root/components/lefthook-python/lefthook.yml" >"$work/broken.yml"
assert_eq 'self-check fixture carries the planted key' '1' "$(grep -c '^  xcommandsx:$' "$work/broken.yml")"
validate_fragment "$work/broken.yml" broken
assert_nonzero 'lefthook validate rejects a fragment with an unknown key' "$?"

[[ $FAILED -eq 0 ]] || exit 1
