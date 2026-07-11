#Requires -Version 7.4
[CmdletBinding()]
param()

$module = Join-Path $PSScriptRoot 'CommandLookup.psm1'
Import-Module $module -Force
$resolved = Get-ExternalToolPath -Name 'pwsh'
if (-not $resolved) {
    throw 'The fixture expected pwsh to be discoverable.'
}
