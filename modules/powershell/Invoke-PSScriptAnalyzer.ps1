#Requires -Version 7.4
<#
.SYNOPSIS
    Run PSScriptAnalyzer over PowerShell files with per-file subprocess isolation.

.DESCRIPTION
    Lints .ps1/.psm1 files against a PSScriptAnalyzerSettings.psd1 ruleset. Each
    file is analyzed in a fresh pwsh subprocess to avoid the PSScriptAnalyzer
    CommandInfoCache / RunspacePool race that surfaces (notably on Linux) when
    many files are analyzed in one process.

    File discovery uses Get-ChildItem -Force so dot-prefixed directories (for
    example .github) are not silently skipped by Linux pwsh.

.PARAMETER Path
    Files and/or directories to analyze. Directories are searched recursively.
    Defaults to the current directory.

.PARAMETER Settings
    Path to the PSScriptAnalyzerSettings.psd1 ruleset. Defaults to the copy that
    ships next to this script.

.PARAMETER AnalyzerVersion
    Required minimum PSScriptAnalyzer version. Default 1.25.0 — the floor that
    fixes the Linux NRE under pwsh 7.4.14+.

.PARAMETER ExcludePath
    Path substrings to skip (matched against forward-slash-normalized full
    paths). The .git directory is always skipped.

.OUTPUTS
    Exit 0: no findings (or PSScriptAnalyzer not installed — see note below).
    Exit 1: findings present (printed to the host).
    Exit 2: configuration error or a per-file analysis subprocess crashed.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Path = @('.'),
    [string]$Settings = (Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'),
    [string]$AnalyzerVersion = '1.25.0',
    [string[]]$ExcludePath = @()
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Test-PathExcluded {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$FullPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Patterns
    )

    $normalized = $FullPath -replace '\\', '/'
    if ($normalized -match '/\.git/') {
        return $true
    }
    foreach ($pattern in $Patterns) {
        $needle = ($pattern -replace '\\', '/').Trim('/')
        if ($needle -and $normalized -like "*$needle*") {
            return $true
        }
    }
    return $false
}

# Self-skip when the analyzer is unavailable (a contributor box without it).
# CI is the authoritative gate; a missing analyzer must not hard-fail local hooks.
$module = Get-Module -ListAvailable -Name PSScriptAnalyzer |
    Where-Object { $_.Version -ge [version]$AnalyzerVersion } |
    Select-Object -First 1
if (-not $module) {
    Write-Warning "PSScriptAnalyzer >= $AnalyzerVersion not installed — skipping (CI is the authoritative gate)."
    exit 0
}

if (-not (Test-Path -LiteralPath $Settings)) {
    # Non-terminating so the exit-2 contract holds under $ErrorActionPreference='Stop'.
    Write-Error "Settings file not found: $Settings" -ErrorAction Continue
    exit 2
}

# -Force so dot-prefixed directories (.github, etc.) are descended on Linux pwsh.
$files = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $Path) {
    if (Test-Path -LiteralPath $entry -PathType Leaf) {
        $resolved = (Resolve-Path -LiteralPath $entry).Path
        $ext = [System.IO.Path]::GetExtension($resolved)
        # Filter leaf inputs by extension too — a hook may pass a mixed file list.
        if (($ext -in '.ps1', '.psm1') -and -not (Test-PathExcluded -FullPath $resolved -Patterns $ExcludePath)) {
            $files.Add($resolved)
        }
    } elseif (Test-Path -LiteralPath $entry -PathType Container) {
        Get-ChildItem -LiteralPath $entry -Recurse -Force -File |
            Where-Object { $_.Extension -in '.ps1', '.psm1' } |
            ForEach-Object {
                if (-not (Test-PathExcluded -FullPath $_.FullName -Patterns $ExcludePath)) {
                    $files.Add($_.FullName)
                }
            }
    } else {
        Write-Error "Path not found: $entry" -ErrorAction Continue
        exit 2
    }
}

if ($files.Count -eq 0) {
    Write-Output 'No .ps1/.psm1 files to analyze.'
    exit 0
}

$findingCount = 0
foreach ($file in $files) {
    $env:PSSA_FILE = $file
    $env:PSSA_SETTINGS = $Settings
    $env:PSSA_VERSION = $AnalyzerVersion
    # Single-quoted here-string: variables expand in the child from its
    # inherited environment, not here.
    $output = pwsh -NoProfile -NonInteractive -Command @'
Import-Module PSScriptAnalyzer -MinimumVersion $env:PSSA_VERSION -ErrorAction Stop
Invoke-ScriptAnalyzer -Path $env:PSSA_FILE -Settings $env:PSSA_SETTINGS |
    ForEach-Object { '{0}:{1}:{2} {3} [{4}]' -f $_.ScriptName, $_.Line, $_.Column, $_.Message, $_.RuleName }
'@
    $childExit = $LASTEXITCODE
    if ($childExit -ne 0) {
        Write-Error "PSScriptAnalyzer subprocess crashed for ${file} (exit $childExit)." -ErrorAction Continue
        exit 2
    }
    if ($output) {
        $output | ForEach-Object { Write-Output $_ }
        $findingCount += @($output).Count
    }
}

if ($findingCount -gt 0) {
    Write-Output ''
    Write-Output "PSScriptAnalyzer: $findingCount finding(s) across $($files.Count) file(s)."
    exit 1
}

Write-Output "PSScriptAnalyzer: clean across $($files.Count) file(s)."
exit 0
