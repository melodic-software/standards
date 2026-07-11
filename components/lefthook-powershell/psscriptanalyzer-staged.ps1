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
    ruleset would be silently ignored. Each target runs exactly once in its own fresh no-profile pwsh
    worker. PSScriptAnalyzer 1.25.0 can leak engine state between sequential targets in one process and
    intermittently throw a NullReferenceException even though every target passes in isolation.

    The PSScriptAnalyzer component owns the rules; this adapter only orchestrates isolated invocations.
    CI remains the authoritative gate and this lane is fast staged-file feedback.
.PARAMETER Files
    The staged PowerShell file paths Lefthook substitutes for {staged_files}.
#>
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)

$targets = @($Files | Where-Object { $_ })
if (-not $targets) { return }

# Resolve the consumer's ruleset from the repo root (Lefthook's working directory); fall back to the
# analyzer defaults if a repo has none. Validate it PARSES first so a malformed settings file fails
# loudly here instead of being silently swallowed - which would drop the consumer's ruleset and let the
# scan report clean while running unruled.
$settings = Join-Path $PWD 'PSScriptAnalyzerSettings.psd1'
$settingsPath = $null
if (Test-Path -LiteralPath $settings -PathType Leaf) {
    try {
        Import-PowerShellDataFile -LiteralPath $settings -ErrorAction Stop | Out-Null
    } catch {
        Write-Output "PSScriptAnalyzerSettings.psd1 could not be parsed: $($_.Exception.Message)"
        exit 1
    }
    $settingsPath = (Resolve-Path -LiteralPath $settings).Path
}

$worker = Join-Path $PSScriptRoot 'psscriptanalyzer-target.ps1'
if (-not (Test-Path -LiteralPath $worker -PathType Leaf)) {
    Write-Output "PSScriptAnalyzer isolated worker is missing: $worker"
    exit 1
}

$pwsh = (Get-Process -Id $PID).Path
$failed = $false
foreach ($file in $targets) {
    $workerArguments = @(
        '-NoProfile'
        '-NonInteractive'
        '-File'
        $worker
        '-Target'
        $file
    )
    if ($settingsPath) {
        $workerArguments += @('-Settings', $settingsPath)
    }

    $output = & $pwsh @workerArguments 2>&1
    $workerExitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Output $_ }
    if ($workerExitCode -ne 0) {
        $failed = $true
    }
}

if ($failed) {
    exit 1
}
