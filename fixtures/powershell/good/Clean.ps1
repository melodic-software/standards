#Requires -Version 7.4
<#
.SYNOPSIS
    Conforming sample — must pass the PowerShell module's ruleset cleanly.
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
