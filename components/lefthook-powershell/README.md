# Lefthook PowerShell

Opt-in staged PowerShell analysis. This component exports `lefthook.yml` and
`psscriptanalyzer-staged.ps1` and `psscriptanalyzer-target.ps1` as one atomic
payload: the fragment invokes the orchestrator at
`.lefthook/psscriptanalyzer-staged.ps1`, and the orchestrator discovers the root
`PSScriptAnalyzerSettings.psd1` policy.

Compose the fragment with `lefthook-base` for shared strict settings and
root-aware glob matching.

The runner exists because nested cross-shell quoting is unreliable on Windows.
PSScriptAnalyzer policy remains owned by the `psscriptanalyzer` component; this
adapter only shortens local feedback. It launches one fresh
`pwsh -NoProfile -NonInteractive` worker per target, analyzes that target exactly
once, continues through later targets to report all failures, and treats every
analyzer engine/rule error as a failed hook. No target is retried.

PSScriptAnalyzer 1.25.0 runs rules in parallel against a shared CommandInfo
cache, so a single file in a fresh process can intermittently throw a
`NullReferenceException` ([PowerShell/PSScriptAnalyzer#1867][3], [#1708][4]).
The per-target worker keeps one failure from masking other targets; it does
not prevent the race. Until the upstream fix ([#2206][5]) ships in a release,
remove the triggers: keep `PSUseCorrectCasing` disabled, and drop
`Export-ModuleMember` from a `.psm1` that exports every function it defines
(without the call, a script module exports all its functions and aliases).

The focused `psscriptanalyzer-staged.test.ps1` regression supplies a fake
analyzer module to prove deterministic one-target/one-process isolation, then
repeatedly exercises the exact historical six-file commit-hook shape and the
current staged set against real PSScriptAnalyzer 1.25.0.

The process contract follows Microsoft's documented [`pwsh` `-NoProfile`,
`-NonInteractive`, and `-File` switches][1]. Each worker uses the documented
single-target [`Invoke-ScriptAnalyzer -Path ... -Settings ...` interface][2].

[1]: https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh
[2]: https://learn.microsoft.com/powershell/module/psscriptanalyzer/invoke-scriptanalyzer
[3]: https://github.com/PowerShell/PSScriptAnalyzer/issues/1867
[4]: https://github.com/PowerShell/PSScriptAnalyzer/issues/1708
[5]: https://github.com/PowerShell/PSScriptAnalyzer/pull/2206
