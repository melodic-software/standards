#!/usr/bin/env bash
# Tests the PSScriptAnalyzer component's root-canonical ruleset.
# the good fixture and flags the bad fixture. This asserts the config only —
# Invoke-ScriptAnalyzer is called directly. The CI runner that wraps the
# analyzer (per-file subprocess isolation) lives in the ci-workflows repo and is
# dogfooded there. Skips cleanly when the engine is absent.
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

# pwsh is a native Windows process under Git Bash; convert POSIX paths to
# Windows form there. On Linux cygpath is absent and the path passes through.
to_native() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
settings_n="$(to_native "$settings")"

# Analyze one fixture file against the ruleset: print rule names, exit 1 on any
# finding. Single file per call, so the multi-file analyzer race never applies.
# shellcheck disable=SC2016
run_pssa() {
  PSSA_FILE="$(to_native "$1")" PSSA_SETTINGS="$settings_n" \
    pwsh -NoProfile -NonInteractive -Command '
      $findings = Invoke-ScriptAnalyzer -Path $env:PSSA_FILE -Settings $env:PSSA_SETTINGS
      $findings | ForEach-Object { $_.RuleName }
      if ($findings) { exit 1 } else { exit 0 }
    '
}

out="$(run_pssa "$root/components/psscriptanalyzer/fixtures/good/Clean.ps1")"; rc=$?
assert_exit 'good fixture has no findings' 0 "$rc"

out="$(run_pssa "$root/components/psscriptanalyzer/fixtures/bad/Violations.ps1")"; rc=$?
assert_exit 'bad fixture has findings' 1 "$rc"
assert_contains 'bad fixture flags the alias rule' "$out" 'PSAvoidUsingCmdletAliases'
assert_contains 'bad fixture flags the params-kind rule behind the 1.25.0 floor' "$out" 'PSUseConsistentParametersKind'

[[ $FAILED -eq 0 ]] || exit 1
