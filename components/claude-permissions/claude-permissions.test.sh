#!/usr/bin/env bash
# Guards the withdraw-tombstone contract the README states: `allow` and
# `withdraw` stay disjoint (the composer subtracts `withdraw` after its union,
# so a row present in both is evicted on the next apply — a regrant that
# forgets to delete its tombstone is silently defeated), and every tombstone
# is a non-empty exact string. Fails the build here instead of on the fleet.
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

cd "$root" || exit 1

if ! command -v jq >/dev/null 2>&1; then
  skip_suite 'jq not installed'
fi

config="components/claude-permissions/claude-permissions.json"

schema_version="$(jq -r '.claudePermissions.schemaVersion' "$config")"
assert_eq "schemaVersion is the supported value" "1" "$schema_version"

empty_tombstones="$(jq -r '[.claudePermissions.withdraw[] | select((type != "string") or (. == ""))] | length' "$config")"
assert_eq "every withdraw entry is a non-empty string" "0" "$empty_tombstones"

overlap="$(jq -r '(.claudePermissions.allow // []) as $allow
  | [(.claudePermissions.withdraw // [])[] | select(. as $row | $allow | index($row))]
  | join("\n")' "$config")"
if [[ -n "$overlap" ]]; then
  fail 'allow and withdraw are disjoint' \
    "rows present in both (regrant must delete its tombstone): $overlap"
else
  pass 'allow and withdraw are disjoint'
fi

# Mirror checkout's `--`-separator path-discard forms only. A bare
# `git restore *` catch-all would also deny `git restore --staged <path>`,
# and deny→ask→allow precedence cannot carve that exception back out.
required_restore_denies=(
  'Bash(git restore -- *)'
  'Bash(git restore * -- *)'
  'PowerShell(git restore -- *)'
  'PowerShell(git restore * -- *)'
  'PowerShell(git * restore -- *)'
)
for pattern in "${required_restore_denies[@]}"; do
  if jq -e --arg pattern "$pattern" \
    '.claudePermissions.deny | index($pattern) != null' "$config" >/dev/null; then
    pass "deny includes $pattern"
  else
    fail "deny includes $pattern" "missing required restore discard rule"
  fi
done

[[ $FAILED -eq 0 ]] || exit 1
