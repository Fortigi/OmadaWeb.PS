function Get-InstalledModuleInfo {
    param (
        [string]$ModuleName
    )

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