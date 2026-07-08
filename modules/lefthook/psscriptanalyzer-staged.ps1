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
$settingsData = $null
$settings = "$PWD/PSScriptAnalyzerSettings.psd1"
if (Test-Path -LiteralPath $settings) {
    try {
        $settingsData = Import-PowerShellDataFile -LiteralPath $settings -ErrorAction Stop
    } catch {
        Write-Output "PSScriptAnalyzerSettings.psd1 could not be parsed: $($_.Exception.Message)"
        exit 1
    }
    $analyzerArgs['Settings'] = $settings
}

# PSUseCompatibleSyntax ships in the default rule set, so it runs unless the consumer's settings turn it
# off: an ExcludeRules entry drops it, or an explicit IncludeRules list that omits it. Only while it is
# actually in effect is its benign NullReferenceException (handled after the scan) tolerable; if the
# consumer disabled it, any NRE must originate elsewhere and has to surface.
$compatSyntaxRule = 'PSUseCompatibleSyntax'
$compatSyntaxEffective = $true
if ($settingsData) {
    $excludeRules = @($settingsData.ExcludeRules | Where-Object { $_ })
    $includeRules = @($settingsData.IncludeRules | Where-Object { $_ })
    if ($excludeRules -contains $compatSyntaxRule) { $compatSyntaxEffective = $false }
    if ($includeRules.Count -and ($includeRules -notcontains $compatSyntaxRule)) { $compatSyntaxEffective = $false }
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
$findings = @($findings | Where-Object { $_ })

# Re-surface every analyzer error as a failure, tolerating ONLY the one known-benign case: the
# NullReferenceException thrown by the built-in PSUseCompatibleSyntax rule itself. An error is treated as
# benign strictly when ALL of these hold:
#   * its message is the NRE signature ("Object reference not set"), AND
#   * PSUseCompatibleSyntax is actually effective for this scan (see $compatSyntaxEffective above), AND
#   * it did NOT originate from an external/custom rule. Custom rules execute via a separate engine path
#     (Invoke-ScriptAnalyzer's GetExternalRecord), surfacing as a RuntimeException with error id 80131501
#     that targets the analyzer engine object rather than the scanned file; built-in-rule errors do not.
# Every other analyzer error - a custom rule that throws an NRE, an NRE while PSUseCompatibleSyntax is
# disabled, or any rule that failed to load - is surfaced so a broken ruleset can never pass as clean.
$realErrors = @($saErrors | Where-Object {
    $isNullRefError = $_.Exception.Message -match 'Object reference not set'
    $fromExternalRule =
        ($_.FullyQualifiedErrorId -match '^80131501') -or
        ($_.Exception.StackTrace -match 'GetExternalRecord') -or
        ($null -ne $_.TargetObject -and $_.TargetObject.GetType().FullName -eq 'Microsoft.Windows.PowerShell.ScriptAnalyzer.ScriptAnalyzer')
    -not ($isNullRefError -and $compatSyntaxEffective -and -not $fromExternalRule)
})
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
