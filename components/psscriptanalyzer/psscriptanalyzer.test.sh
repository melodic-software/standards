#!/usr/bin/env bash
set -uo pipefail
root="$(git rev-parse --show-toplevel)"
# shellcheck source=harness/shell/lib.sh
source "$root/harness/shell/lib.sh"

settings="$root/PSScriptAnalyzerSettings.psd1"

command -v pwsh >/dev/null 2>&1 || skip_suite 'pwsh not installed'
# The single-quoted argument is a PowerShell command — $_ is PowerShell syntax,
# not a bash expansion, so single quotes are intentional.
# shellcheck disable=SC2016
pwsh -NoProfile -NonInteractive -Command \
  'if (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object { $_.Version -ge [version]"1.25.0" }) { exit 0 } else { exit 1 }' \
  >/dev/null 2>&1 || skip_suite 'PSScriptAnalyzer >= 1.25.0 not installed'

to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
settings_n="$(to_native "$settings")"

# shellcheck disable=SC2016
run_pssa() {
  PSSA_FILE="$(to_native "$1")" PSSA_SETTINGS="$settings_n" \
    pwsh -NoProfile -NonInteractive -Command '
      $findings = Invoke-ScriptAnalyzer -Path $env:PSSA_FILE -Settings $env:PSSA_SETTINGS
      $findings | ForEach-Object { $_.RuleName }
      if ($findings) { exit 1 } else { exit 0 }
    '
}

run_pssa "$root/components/psscriptanalyzer/fixtures/good/Clean.ps1" >/dev/null
rc=$?
assert_exit 'good fixture has no findings' 0 "$rc"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp "$root/components/psscriptanalyzer/fixtures/bad/Violations.ps1.txt" "$tmp/Violations.ps1"

out="$(run_pssa "$tmp/Violations.ps1")"
rc=$?
assert_exit 'bad fixture has findings' 1 "$rc"
assert_contains 'bad fixture flags the alias rule' "$out" 'PSAvoidUsingCmdletAliases'
assert_contains 'bad fixture flags the params-kind rule behind the 1.25.0 floor' "$out" 'PSUseConsistentParametersKind'

[[ $FAILED -eq 0 ]] || exit 1
