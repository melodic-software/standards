# PSScriptAnalyzer

Strict cross-platform PowerShell 7.4+ policy for
[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer). The exported
payload is the root-canonical
[`PSScriptAnalyzerSettings.psd1`](../../PSScriptAnalyzerSettings.psd1), where
the analyzer and editor integration discover it.

Execution lives in `ci-workflows`, including its per-file subprocess isolation.
The separate `lefthook-powershell` adapter provides fast staged-file feedback.
`fixtures/` and `psscriptanalyzer.test.sh` prove the settings load and flag a named
rule with PSScriptAnalyzer 1.25.0+.
