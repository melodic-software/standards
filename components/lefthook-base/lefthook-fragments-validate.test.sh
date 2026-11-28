#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

command -v lefthook >/dev/null 2>&1 || skip_suite 'lefthook not installed'

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

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

sed 's/^  commands:$/  xcommandsx:/' "$root/components/lefthook-python/lefthook.yml" >"$work/broken.yml"
assert_eq 'self-check fixture carries the planted key' '1' "$(grep -c '^  xcommandsx:$' "$work/broken.yml")"
validate_fragment "$work/broken.yml" broken
assert_nonzero 'lefthook validate rejects a fragment with an unknown key' "$?"

[[ $FAILED -eq 0 ]] || exit 1
