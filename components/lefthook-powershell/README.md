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
analyzer engine/rule error as a failed hook. This process boundary avoids
PSScriptAnalyzer 1.25.0's intermittent cross-target engine-state failure without
retrying, suppressing, or accepting a different result.

The focused `psscriptanalyzer-staged.test.ps1` regression supplies a fake
analyzer module to prove deterministic one-target/one-process isolation, then
repeatedly exercises the exact historical six-file commit-hook shape and the
current staged set against real PSScriptAnalyzer 1.25.0.

The process contract follows Microsoft's documented [`pwsh` `-NoProfile`,
`-NonInteractive`, and `-File` switches][1]. Each worker uses the documented
single-target [`Invoke-ScriptAnalyzer -Path ... -Settings ...` interface][2].

[1]: https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh
[2]: https://learn.microsoft.com/powershell/module/psscriptanalyzer/invoke-scriptanalyzer
