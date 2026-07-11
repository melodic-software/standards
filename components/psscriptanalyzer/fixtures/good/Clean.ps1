#Requires -Version 7.4
<#
.SYNOPSIS
    Conforming sample — must pass the PSScriptAnalyzer component cleanly.
.NOTES
    The em-dash above is load-bearing: it keeps this file non-ASCII with no BOM,
    so a clean pass proves the ruleset's PSUseBOMForUnicodeEncodedFile exclusion
    holds. Don't "fix" it to ASCII.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Name
)

Set-StrictMode -Version 3.0

$greeting = "Hello, $Name"

if (-not $Name) {
    throw 'Name is required.'
}

Write-Output $greeting

function New-Greeting {
    <#
    .SYNOPSIS
        Constructs a greeting object — a data constructor, not a state change.
    .NOTES
        The New-* verb is load-bearing: a clean pass proves the ruleset's
        PSUseShouldProcessForStateChangingFunctions exclusion holds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subject
    )

    [pscustomobject]@{ Subject = $Subject }
}

Write-Output (New-Greeting -Subject $Name)
