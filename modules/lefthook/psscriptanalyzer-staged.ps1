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

# Collect analyzer/engine errors instead of letting SilentlyContinue swallow them: SilentlyContinue
# suppresses the console spew while -ErrorVariable captures the errors, and a foreach statement (not
# ForEach-Object) keeps them in this scope so they accumulate across files.
#
# Retry a file once when its analysis reports an error: the analyzer runs rules in parallel over a
# shared, non-thread-safe CommandInfo cache and can throw a benign, intermittent NullReferenceException
# (https://github.com/PowerShell/PSScriptAnalyzer/issues/1867) - observed only on a fresh host's first analysis, with an immediate
# in-session retry reliably clean. The retry's result replaces the first attempt's (an errored run's
# findings may be incomplete). An error that survives the retry is real - a rule failed to load or a
# broken ruleset ran - and must fail the hook.
$saErrors = [System.Collections.Generic.List[object]]::new()
$findings = foreach ($file in $targets) {
    $result = Invoke-ScriptAnalyzer -Path $file @analyzerArgs -ErrorAction SilentlyContinue -ErrorVariable err
    if ($err) {
        $result = Invoke-ScriptAnalyzer -Path $file @analyzerArgs -ErrorAction SilentlyContinue -ErrorVariable err
        if ($err) { $saErrors.AddRange(@($err)) }
    }
    $result
}
$findings = @($findings | Where-Object { $_ })

# Surface every persistent analyzer error as a failure - nothing else is suppressed, and the scan must
# never pass as clean when a rule failed to load or a broken ruleset ran.
$realErrors = @($saErrors | Where-Object { $_ })
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
