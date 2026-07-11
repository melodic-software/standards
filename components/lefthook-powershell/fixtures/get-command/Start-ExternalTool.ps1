#Requires -Version 7.4
[CmdletBinding()]
param()

$command = Get-Command pwsh -CommandType Application -ErrorAction Stop
Write-Output $command.Source
