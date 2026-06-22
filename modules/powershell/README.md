# PowerShell module

Opinionated PowerShell static analysis via [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer).

## Contents

- `PSScriptAnalyzerSettings.psd1` — the ruleset: OTBS (One True Brace Style),
  targets PowerShell 7.4/7.6, cross-platform, every rule justified inline.

This module ships the ruleset only. The CI runner that executes the analyzer
(per-file subprocess isolation, to dodge the analyzer's multi-file cache race)
is execution, not config: it lives in the `ci-workflows` repo and is consumed by
reference.

## Engine

Requires PowerShell 7.4+ and the **PSScriptAnalyzer** module (>= 1.25.0).

## Adopt in a repo

1. Copy `PSScriptAnalyzerSettings.psd1` into the consuming repo — canonical home
   `modules/powershell/`; PSScriptAnalyzer and the VS Code PowerShell extension
   also auto-discover a root-level copy.
2. Reference the `ci-workflows` PowerShell workflow from CI, pointing its
   settings input at the copied ruleset.

## Test

`fixtures/powershell/{good,bad}` exercise the ruleset; `pssa.test.sh` asserts the
good fixture is clean and the bad fixture is flagged, calling
`Invoke-ScriptAnalyzer` directly through the shell harness
(`harness/shell/run-tests.sh`). The `bad` fixture is intentionally
non-conforming and is excluded from the repo's own self-lint.
