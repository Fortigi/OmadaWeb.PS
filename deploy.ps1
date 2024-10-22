[CmdletBinding(SupportsShouldProcess)]
PARAM(
    [validateSet("AllUsers", "CurrentUser", "System")]
    $Scope = "CurrentUser"
)
$ErrorActionPreference = "Stop"
try {
    $ModuleName = "OmadaWeb.PS"
    "ModuleName {0}" -f $ModuleName | Write-Verbose

    $ModuleSourceFolder = Join-Path $PSScriptRoot -ChildPath $ModuleName
    "ModuleSourceFolder {0}" -f $ModuleTargetFolder | Write-Verbose

    "Scope: {0}" -f $Scope | Write-Verbose
    switch ($Scope) {

        "AllUsers" {
            $ModuleTargetFolder = Join-Path $env:PROGRAMFILES -ChildPath ("PowerShell\Modules\{0}" -f $ModuleName)
        }
        "System" {
            $ModuleTargetFolder = Join-Path $PSHOME -ChildPath ("Modules\{0}" -f $ModuleName)
        }
        default {
            $ModuleTargetFolder = Join-Path $HOME -ChildPath ("Documents\WindowsPowerShell\Modules\{0}" -f $ModuleName)
        }
    }
    "ModuleTargetFolder {0}" -f $ModuleTargetFolder | Write-Verbose

    if (Test-Path $ModuleTargetFolder) {
        if ($null -ne (Get-Module $ModuleName)) {
            "Unload module {0}" -f $ModuleName | Write-Verbose
            Remove-Module $ModuleName
        }
        "Remove current module files at {0}" -f $ModuleTargetFolder | Write-Verbose
        Get-Item $ModuleTargetFolder | Remove-Item -Force -Recurse
    }

    "Deploy {0} PowerShell module from {1} to {2}" -f $ModuleName,$ModuleSourceFolder, $ModuleTargetFolder | Write-Host
    Get-Item -Path $ModuleSourceFolder | Copy-Item -Destination $ModuleTargetFolder -Recurse -Force
    Get-ChildItem $ModuleTargetFolder -Recurse | Unblock-File
    Get-ChildItem $ModuleTargetFolder -Filter "*.dll" | Remove-Item -Force
    Get-ChildItem $ModuleTargetFolder -Filter "OmadaWeb.PS2.psm1" | Remove-Item -Force
    "Finished" | Write-Host
}
catch {
    if ($_.Exception -like "*denied*" -and $Scope -ne "CurrentUser") {
        "Access denied exception occurred,.Running as administrator? Exception:" | Write-Host -ForegroundColor Red
        Throw $_
    }
    else {
        Throw $_
    }
}
