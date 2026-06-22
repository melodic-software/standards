#!/usr/bin/env bash
# Tests the PowerShell module: the runner passes the good fixture, flags the
# bad fixture, and lints itself clean. Skips cleanly when the engine is absent.
set -uo pipefail
# shellcheck source=harness/shell/lib.sh
source "$(git rev-parse --show-toplevel)/harness/shell/lib.sh"

root="$(git rev-parse --show-toplevel)"
runner="$root/modules/powershell/Invoke-PSScriptAnalyzer.ps1"

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
runner_n="$(to_native "$runner")"
run_pssa() { pwsh -NoProfile -File "$runner_n" -Path "$(to_native "$1")" 2>&1; }

FAILED=0
CASE_NUM=0

out="$(run_pssa "$root/fixtures/powershell/good")"; rc=$?
assert_exit 'good fixture exits 0' 0 "$rc"
assert_contains 'good fixture reports clean' "$out" 'clean'

out="$(run_pssa "$root/fixtures/powershell/bad")"; rc=$?
assert_exit 'bad fixture exits 1' 1 "$rc"
assert_contains 'bad fixture flags the alias rule' "$out" 'PSAvoidUsingCmdletAliases'

out="$(run_pssa "$runner")"; rc=$?
assert_exit 'runner lints itself clean' 0 "$rc"

[[ $FAILED -eq 0 ]] || exit 1
