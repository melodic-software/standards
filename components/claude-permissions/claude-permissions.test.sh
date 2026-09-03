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

# The Bash LEFTHOOK denies anchor on the inline-env spelling (`LEFTHOOK=0 cmd`),
# which PowerShell lacks — its bypass shapes all reference the env var by name:
#   $env:LEFTHOOK = '0'; git commit …
#   Set-Item env:LEFTHOOK 0; git commit …
#   ${env:LEFTHOOK} = "false"; git commit …
# PowerShell's Env: drive is case-insensitive while these rules are literal
# whole-string globs (`*` is the only metacharacter), so two anchors cover the
# realistic spellings: `*LEFTHOOK*` catches every uppercase-name reference
# whatever the drive-prefix casing ($env:/$Env:/$ENV:/Set-Item env:), and
# `*:lefthook*` catches the lowercase-name drive-qualified forms without
# denying a bare `lefthook run …` invocation. Exotic mixed-case names
# (LeftHook) remain out of glob reach — accepted residual, recorded here.
required_lefthook_denies=(
  'Bash(LEFTHOOK*=0 *)'
  'Bash(LEFTHOOK*=FALSE *)'
  'Bash(LEFTHOOK*=false *)'
  'PowerShell(*:lefthook*)'
  'PowerShell(*LEFTHOOK*)'
)
for pattern in "${required_lefthook_denies[@]}"; do
  if jq -e --arg pattern "$pattern" \
    '.claudePermissions.deny | index($pattern) != null' "$config" >/dev/null; then
    pass "deny includes $pattern"
  else
    fail "deny includes $pattern" "missing required lefthook bypass rule"
  fi
done

# settings.local.json is personal overrides, not a credential store, and a
# Read deny also blocks Edit — those rows must not return.
#
# The two .claude.json rows were retired for the same mechanical reason: a Read
# deny blocks Edit and Write on the same path, so they blocked the documented way
# to manage the file, not just reads of it. Official docs also record that a
# Read/Edit denial does not apply to a subprocess that opens the file itself, so
# the rows never denied a determined reader — they only denied the first-class
# tools. `Read()` rules are path/glob only, so no rule could keep the OAuth and
# MCP fields denied while exposing the rest; the file is protected by operator
# judgement rather than by a rule that could not express the distinction.
forbidden_read_denies=(
  'Read(**/.claude/settings.local.json)'
  'Read(.claude/settings.local.json)'
  'Read(**/.claude.json)'
  'Read(~/.claude.json)'
)
for pattern in "${forbidden_read_denies[@]}"; do
  if jq -e --arg pattern "$pattern" \
    '.claudePermissions.deny | index($pattern) != null' "$config" >/dev/null; then
    fail "deny omits $pattern" "retired Read deny must not return"
  else
    pass "deny omits $pattern"
  fi
done

[[ $FAILED -eq 0 ]] || exit 1
