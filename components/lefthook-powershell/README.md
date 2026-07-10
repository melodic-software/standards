# Lefthook PowerShell

Opt-in staged PowerShell analysis. This component exports `lefthook.yml` and
`psscriptanalyzer-staged.ps1` as one atomic payload: the fragment invokes the
runner at `.lefthook/psscriptanalyzer-staged.ps1`, and the runner discovers the
root `PSScriptAnalyzerSettings.psd1` policy.

Compose the fragment with `lefthook-base` for shared strict settings and
root-aware glob matching.

The runner exists because nested cross-shell quoting is unreliable on Windows.
PSScriptAnalyzer policy remains owned by the `psscriptanalyzer` component; this
adapter only shortens local feedback.
