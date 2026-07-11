#Requires -Version 7.4
<#
.SYNOPSIS
    Analyzes one PowerShell target in an isolated process for the staged-file adapter.
.DESCRIPTION
    This internal worker is launched once per target by psscriptanalyzer-staged.ps1. Process
    isolation prevents PSScriptAnalyzer engine state from leaking between targets while preserving
    fail-closed behavior: analyzer errors and findings both return nonzero, and no target is retried.
.PARAMETER Target
    The one PowerShell file to analyze.
.PARAMETER Settings
    An optional validated PSScriptAnalyzer settings-file path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [string]$Settings
)

try {
    $resolvedTarget = (Resolve-Path -LiteralPath $Target -ErrorAction Stop).Path
    Import-Module PSScriptAnalyzer -ErrorAction Stop

    $analysisErrors = @()
    $invocationArguments = @{
        Path          = $resolvedTarget
        ErrorAction   = 'SilentlyContinue'
        ErrorVariable = 'analysisErrors'
    }
    if ($Settings) {
        $invocationArguments['Settings'] = $Settings
    }

    $findings = @(Invoke-ScriptAnalyzer @invocationArguments | Where-Object { $_ })
    $realErrors = @($analysisErrors | Where-Object { $_ })
    if ($realErrors) {
        $realErrors | ForEach-Object {
            Write-Output "PSScriptAnalyzer error for '$Target': $($_.Exception.Message)"
        }
        exit 1
    }

    if ($findings.Count) {
        $findings | ForEach-Object {
            Write-Output ('{0}:{1}: {2} - {3}' -f $_.ScriptName, $_.Line, $_.RuleName, $_.Message)
        }
        exit 1
    }
} catch {
    Write-Output "PSScriptAnalyzer error for '$Target': $($_.Exception.Message)"
    exit 1
}
