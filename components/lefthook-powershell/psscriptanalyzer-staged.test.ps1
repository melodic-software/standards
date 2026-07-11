#Requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path -LiteralPath "$PSScriptRoot/../..").Path
$adapter = Join-Path $PSScriptRoot 'psscriptanalyzer-staged.ps1'
$worker = Join-Path $PSScriptRoot 'psscriptanalyzer-target.ps1'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "pssa-staged-$([guid]::NewGuid())"
$moduleRoot = Join-Path $temporaryRoot 'modules'
$moduleDirectory = Join-Path $moduleRoot 'PSScriptAnalyzer/99.0.0'
$log = Join-Path $temporaryRoot 'invocations.log'
$first = Join-Path $temporaryRoot 'First.ps1'
$second = Join-Path $temporaryRoot 'Second target.ps1'
$originalModulePath = $env:PSModulePath
$originalErrorPath = $env:FAKE_PSSA_ERROR_PATH
$originalLog = $env:FAKE_PSSA_LOG
$startingLocation = Get-Location

function Assert-Condition {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-AdapterProcess {
    param([Parameter(Mandatory)][string[]]$Files)

    $pwsh = (Get-Process -Id $PID).Path
    $output = & $pwsh -NoProfile -NonInteractive -File $adapter @Files 2>&1
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = @($output) -join [Environment]::NewLine
    }
}

function Read-InvocationLog {
    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) {
        return @()
    }

    @(
        Get-Content -LiteralPath $log | ForEach-Object {
            $fields = $_ -split "`t", 3
            [pscustomobject]@{
                Worker = $fields[0]
                PID    = $fields[1]
                Path   = $fields[2]
            }
        }
    )
}

try {
    New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $moduleDirectory 'PSScriptAnalyzer.psm1') -Value @'
$script:WorkerInstance = [guid]::NewGuid().ToString('N')

function Invoke-ScriptAnalyzer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Settings
    )

    Add-Content -LiteralPath $env:FAKE_PSSA_LOG -Value "$script:WorkerInstance`t$PID`t$Path"
    if ($Path -eq $env:FAKE_PSSA_ERROR_PATH) {
        Write-Error 'synthetic analyzer failure'
    }
}

Export-ModuleMember -Function Invoke-ScriptAnalyzer
'@
    $manifestParameters = @{
        Path              = Join-Path $moduleDirectory 'PSScriptAnalyzer.psd1'
        RootModule        = 'PSScriptAnalyzer.psm1'
        ModuleVersion     = '99.0.0'
        FunctionsToExport = 'Invoke-ScriptAnalyzer'
    }
    New-ModuleManifest @manifestParameters
    Set-Content -LiteralPath $first -Value "Write-Output 'first'"
    Set-Content -LiteralPath $second -Value "Write-Output 'second'"

    $env:PSModulePath = "$moduleRoot$([System.IO.Path]::PathSeparator)$originalModulePath"
    $env:FAKE_PSSA_LOG = $log
    Set-Location -LiteralPath $root

    Remove-Item Env:FAKE_PSSA_ERROR_PATH -ErrorAction SilentlyContinue
    $clean = Invoke-AdapterProcess -Files @($first)
    Assert-Condition ($clean.ExitCode -eq 0) 'A clean single-pass analysis must succeed.'
    $cleanInvocations = @(Read-InvocationLog)
    Assert-Condition ($cleanInvocations.Count -eq 1) 'The clean target must be analyzed exactly once.'
    Assert-Condition ($cleanInvocations[0].Path -eq $first) 'The clean invocation must analyze the requested target.'

    Clear-Content -LiteralPath $log
    $env:FAKE_PSSA_ERROR_PATH = $first
    $failed = Invoke-AdapterProcess -Files @($first, $second)
    Assert-Condition ($failed.ExitCode -ne 0) 'An analyzer engine error must fail the staged adapter.'
    Assert-Condition ($failed.Output -match 'synthetic analyzer failure') 'The analyzer error must be reported.'
    $failedInvocations = @(Read-InvocationLog)
    Assert-Condition ($failedInvocations.Count -eq 2) 'An analyzer error must not cause a retry.'
    $firstCount = @($failedInvocations | Where-Object { $_.Path -eq $first }).Count
    $secondCount = @($failedInvocations | Where-Object { $_.Path -eq $second }).Count
    Assert-Condition ($firstCount -eq 1) 'The failing target must be analyzed exactly once.'
    Assert-Condition ($secondCount -eq 1) 'Later targets must still be analyzed exactly once.'
    $workerInstances = @($failedInvocations | Select-Object -ExpandProperty Worker -Unique)
    Assert-Condition ($workerInstances.Count -eq 2) 'Every target must load the analyzer in a fresh worker process.'

    $settingsData = Import-PowerShellDataFile -LiteralPath (Join-Path $root 'PSScriptAnalyzerSettings.psd1')
    $correctCasingDisabled = -not $settingsData.Rules.ContainsKey('PSUseCorrectCasing')
    $correctCasingFailure = 'PSUseCorrectCasing must remain disabled until upstream issue #1708 is fixed.'
    Assert-Condition $correctCasingDisabled $correctCasingFailure

    $env:PSModulePath = $originalModulePath
    Remove-Item Env:FAKE_PSSA_ERROR_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_PSSA_LOG -ErrorAction SilentlyContinue
    $analyzer = Get-Module -ListAvailable PSScriptAnalyzer |
        Where-Object { $_.Version -eq [version]'1.25.0' } |
        Select-Object -First 1
    if ($analyzer) {
        $fixtureRoot = Join-Path $PSScriptRoot 'fixtures/get-command'
        $fixtureFiles = Get-ChildItem -LiteralPath $fixtureRoot -File
        $fixtures = @($fixtureFiles | Sort-Object Name | Select-Object -ExpandProperty FullName)
        $historicalHookFiles = @(
            Join-Path $root 'PSScriptAnalyzerSettings.psd1'
            $fixtures
            $adapter
            $PSCommandPath
        )
        Assert-Condition ($historicalHookFiles.Count -eq 6) 'The historical commit-hook regression must use six files.'

        # The PSScriptAnalyzer 1.25.0 cross-target state failure is intermittent. Repeating the exact
        # six-file hook shape made the old shared-process adapter fail reliably, while the fake-module
        # assertion above deterministically proves each target now receives an isolated worker.
        foreach ($iteration in 1..8) {
            $real = Invoke-AdapterProcess -Files $historicalHookFiles
            $realSucceeded = $real.ExitCode -eq 0
            $realFailure = "The six-file no-profile regression failed on iteration ${iteration}: $($real.Output)"
            Assert-Condition $realSucceeded $realFailure
        }

        $currentHookFiles = @($historicalHookFiles + $worker)
        $current = Invoke-AdapterProcess -Files $currentHookFiles
        $currentSucceeded = $current.ExitCode -eq 0
        $currentFailure = "The current staged PowerShell set must pass in one adapter call: $($current.Output)"
        Assert-Condition $currentSucceeded $currentFailure
    } else {
        Write-Output 'SKIP: PSScriptAnalyzer 1.25.0 is unavailable for the no-profile regression.'
    }

    Write-Output 'PSScriptAnalyzer staged adapter regressions passed.'
} finally {
    Set-Location -LiteralPath $startingLocation
    $env:PSModulePath = $originalModulePath
    if ($null -eq $originalErrorPath) {
        Remove-Item Env:FAKE_PSSA_ERROR_PATH -ErrorAction SilentlyContinue
    } else {
        $env:FAKE_PSSA_ERROR_PATH = $originalErrorPath
    }
    if ($null -eq $originalLog) {
        Remove-Item Env:FAKE_PSSA_LOG -ErrorAction SilentlyContinue
    } else {
        $env:FAKE_PSSA_LOG = $originalLog
    }
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
