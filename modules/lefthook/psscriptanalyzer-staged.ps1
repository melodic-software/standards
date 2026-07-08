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

# Resolve the consumer's ruleset from the repo root (Lefthook's working directory); fall back to the
# analyzer defaults if a repo has none. Validate it PARSES first so a malformed settings file fails
# loudly here instead of being silently swallowed - which would drop the consumer's ruleset and let the
# scan report clean while running unruled.
$analyzerArgs = @{}
$settings = "$PWD/PSScriptAnalyzerSettings.psd1"
if (Test-Path -LiteralPath $settings) {
    try {
        Import-PowerShellDataFile -LiteralPath $settings -ErrorAction Stop | Out-Null
    } catch {
        Write-Output "PSScriptAnalyzerSettings.psd1 could not be parsed: $($_.Exception.Message)"
        exit 1
    }
    $analyzerArgs['Settings'] = $settings
}

# Capture non-terminating analyzer errors rather than blanket-swallowing them. PSUseCompatibleSyntax can
# emit a benign NullReferenceException ("Object reference not set") in a fresh -NoProfile host, which is
# safe to ignore - but ANY OTHER error (a rule that failed to load, a broken custom-rule path) must
# surface, not be silently dropped. SilentlyContinue suppresses the console spew; -ErrorVariable collects
# the errors, and a foreach statement (not ForEach-Object) keeps them in this scope so they accumulate.
$saErrors = [System.Collections.Generic.List[object]]::new()
$findings = foreach ($file in $targets) {
    Invoke-ScriptAnalyzer -Path $file @analyzerArgs -ErrorAction SilentlyContinue -ErrorVariable err
    if ($err) { $saErrors.AddRange(@($err)) }
}
$findings = @($findings)

# Re-surface any non-benign analyzer error as a failure (only the benign PSUseCompatibleSyntax NRE
# above is tolerated), so a broken ruleset or rule can never masquerade as a clean scan.
$realErrors = @($saErrors | Where-Object { $_.Exception.Message -notmatch 'Object reference not set' })
if ($realErrors) {
    $realErrors | ForEach-Object { Write-Output "PSScriptAnalyzer error: $($_.Exception.Message)" }
    exit 1
}

if ($findings.Count) {
    $findings | ForEach-Object {
        Write-Output ('{0}:{1}: {2} - {3}' -f $_.ScriptName, $_.Line, $_.RuleName, $_.Message)
    }
    exit 1
}
