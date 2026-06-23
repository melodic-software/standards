#Requires -Version 7.4
<#
.SYNOPSIS
    Pre-commit PSScriptAnalyzer check over staged PowerShell files (Lefthook lane).
.DESCRIPTION
    Invoked by lefthook-powershell.yml as `pwsh -NoProfile -File <this> {staged_files}`. A
    dedicated script (rather than an inline `-Command "..."`) keeps the invocation portable across
    the shells Lefthook spawns on Windows, macOS, and Linux, where nested quoting of a complex
    inline command is fragile and breaks under their differing quoting rules.

    It resolves PSScriptAnalyzerSettings.psd1 from the working directory (the repo root where
    Lefthook runs) and passes it explicitly: Invoke-ScriptAnalyzer does not reliably auto-discover
    a root settings file when the analyzed path is in a subdirectory, so without this the consumer's
    ruleset would be silently ignored. The runner therefore needs no path configuration from the
    consumer yet still applies their settings; the PowerShell module owns the rules, this only
    invokes them. It is a minimal, module-owned runner with no dependency on the ci-workflows pwsh
    action; CI remains the authoritative gate and this lane is fast staged-file feedback.
.PARAMETER Files
    The staged PowerShell file paths Lefthook substitutes for {staged_files}.
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)

$targets = @($Files | Where-Object { $_ })
if (-not $targets) { return }

Import-Module PSScriptAnalyzer -ErrorAction Stop

# Resolve the consumer's ruleset from the repo root (Lefthook's working directory); fall back to
# the analyzer defaults if a repo has none. -ErrorAction SilentlyContinue swallows a benign
# non-terminating "Object reference not set" that PSUseCompatibleSyntax can emit in a fresh
# -NoProfile host; findings are still returned, and the authoritative full-tree scan runs in CI.
$analyzerArgs = @{ ErrorAction = 'SilentlyContinue' }
$settings = "$PWD/PSScriptAnalyzerSettings.psd1"
if (Test-Path -LiteralPath $settings) { $analyzerArgs['Settings'] = $settings }

$findings = @($targets | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ @analyzerArgs })
if ($findings.Count) {
    $findings | ForEach-Object {
        Write-Output ('{0}:{1}: {2} - {3}' -f $_.ScriptName, $_.Line, $_.RuleName, $_.Message)
    }
    exit 1
}
