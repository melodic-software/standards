# PSScriptAnalyzer

Strict cross-platform PowerShell 7.4+ policy for
[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer). The exported
payload is the root-canonical
[`PSScriptAnalyzerSettings.psd1`](../../PSScriptAnalyzerSettings.psd1), where
the analyzer and editor integration discover it.

Execution lives in `ci-workflows`. The separate `lefthook-powershell` adapter
provides fast staged-file feedback. `fixtures/` and
`psscriptanalyzer.test.sh` prove the settings load and flag a named rule. CI
installs and imports exactly PSScriptAnalyzer 1.25.0; the local contract test
accepts 1.25.0 or newer so a developer's later installed version can exercise
the same fixtures.

`PSUseCorrectCasing` is deliberately not blocking while upstream issue
[#1708](https://github.com/PowerShell/PSScriptAnalyzer/issues/1708) documents a
reproducible `NullReferenceException` from `CommandInfo.get_Parameters`. The
policy does not mask analyzer errors with retries. Re-enable the rule only
after an official release resolves that issue and the pinned CI version is
upgraded with a clean-process regression test.

`psscriptanalyzer-staged.test.ps1` supplies a fake analyzer module to prove the
Lefthook adapter invokes every staged target exactly once in a distinct process,
continues after an engine error, and fails the overall hook. It then repeatedly
starts the exact historical six-file no-profile hook contract, followed by the
current staged set, against pinned PSScriptAnalyzer 1.25.0. This covers both the
`PSUseCorrectCasing` exclusion for issue #1708 and the separate intermittent
cross-target engine-state failure that requires process isolation.
