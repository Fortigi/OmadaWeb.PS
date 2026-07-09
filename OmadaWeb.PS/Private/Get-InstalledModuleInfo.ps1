function Get-InstalledModuleInfo {
    [CmdletBinding()]
    param(
        [string]$ModuleName
    )

    "{0} - Getting installed module info for: {1}" -f $MyInvocation.MyCommand, $ModuleName | Write-Verbose
    $CallStack = Get-PSCallStack
    $ModuleStack = $CallStack | Where-Object { $_.Command -eq ("{0}.psm1" -f $ModuleName) }

    $Module = Get-Module -ListAvailable -Name $ModuleName | ForEach-Object {$_ | Where-Object { (Split-Path $_.Path) -eq (Split-Path $ModuleStack.ScriptName) }} | Sort-Object Version -Descending | Select-Object -First 1
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