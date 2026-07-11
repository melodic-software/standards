function Get-ExternalToolPath {
    <#
    .SYNOPSIS
        Resolves one external tool path for the analyzer regression fixture.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }
    return $null
}

Export-ModuleMember -Function Get-ExternalToolPath
