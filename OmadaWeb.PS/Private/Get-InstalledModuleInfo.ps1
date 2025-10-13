function Get-InstalledModuleInfo {
    [CmdletBinding()]
    PARAM(
        [string]$ModuleName
    )

    "{0} - Getting installed module info for: {1}" -f $MyInvocation.MyCommand, $ModuleName | Write-Verbose
    $Module = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
    if ($Module) {
        $ModuleInfo = @{
            Name             = $Module.Name
            Version          = $Module.Version
            RepositorySource = $Module.RepositorySourceLocation
        }
        return $ModuleInfo
    }
    else {
        return $null
    }
}