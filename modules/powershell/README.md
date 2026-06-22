# PowerShell module

Opinionated PowerShell static analysis via [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer).

## Contents

- `PSScriptAnalyzerSettings.psd1` — the ruleset: OTBS (One True Brace Style), targets PowerShell 7.4/7.6, cross-platform, every rule justified inline.
- `Invoke-Pssa.ps1` — a runner that analyzes files in a fresh `pwsh` subprocess **per file**, which avoids the PSScriptAnalyzer cache/runspace race that otherwise surfaces (notably on Linux) when many files are analyzed in one process.

## Engine

Requires PowerShell 7.4+ and the **PSScriptAnalyzer** module (≥ 1.25.0) — provisioned machine-wide via dotfiles. The runner **self-skips** (exit 0) when the module is absent, so a contributor without it isn't blocked locally; CI is the authoritative gate.

## Adopt in a repo

1. Copy `PSScriptAnalyzerSettings.psd1` to the consuming repo's **root** — PSScriptAnalyzer and the VS Code PowerShell extension auto-discover a root-level settings file.
2. Run the analyzer:

   ```powershell
   pwsh -File Invoke-Pssa.ps1 -Path .
   ```

   Exit `0` = clean, `1` = findings, `2` = configuration error / analyzer crash. Wire it into a git hook (pass staged files via `-Path`) and/or a CI lane.

## Test

`fixtures/powershell/{good,bad}` exercise the ruleset; `pssa.test.sh` runs them on the shell harness (`harness/shell/run-tests.sh`). The `bad` fixture is intentionally non-conforming and is excluded from the repo's own self-lint.
