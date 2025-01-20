[CmdletBinding(SupportsShouldProcess)]
PARAM(
    [validateSet("AllUsers", "CurrentUser", "System")]
    $Scope = "CurrentUser"
)
$ErrorActionPreference = "Stop"
try {
    $ModuleName = "OmadaWeb.PS"
    "ModuleName {0}" -f $ModuleName | Write-Verbose

    $ModuleSourceFolder = Join-Path $PSScriptRoot -ChildPath "buildoutput\OmadaWeb.PS"
    if (!(Test-Path $ModuleSourceFolder -PathType Container)) {
        $ModuleSourceFolder = Join-Path $PSScriptRoot -ChildPath "buildoutput"
    }
    if (!(Test-Path $ModuleSourceFolder -PathType Container)) {
        "Module source folder {0} does not exist" -f $ModuleSourceFolder | Write-Error -ErrorAction Stop
    }

    "ModuleSourceFolder {0}" -f $ModuleTargetFolder | Write-Verbose

    $ModulePsd1 = Import-PowerShellDataFile (Join-Path -Path $ModuleSourceFolder -ChildPath ("{0}.psd1" -f $ModuleName))
    [System.Version]$Version = $ModulePsd1.ModuleVersion

    "Scope: {0}" -f $Scope | Write-Verbose
    switch ($Scope) {

        "AllUsers" {
            if ($PSVersionTable.PsEdition -eq "Desktop") {
                $ModuleTargetFolder = Join-Path $env:ProgramFiles -ChildPath ("WindowsPowerShell\Modules\{0}\{1}" -f $ModuleName, $Version.ToString())
            }
            else {
                $ModuleTargetFolder = Join-Path $env:ProgramFiles -ChildPath ("PowerShell\Modules\{0}\{1}" -f $ModuleName, $Version.ToString())
            }
        }
        "System" {
            if ($PSVersionTable.PsEdition -eq "Desktop") {
                $ModuleTargetFolder = Join-Path $env:WinDir -ChildPath ("System32\WindowsPowerShell\v1.0\Modules\{0}\{1}" -f $ModuleName, $Version.ToString())
            }
            else {
                $ModuleTargetFolder = Join-Path $env:WinDir -ChildPath ("Program Files\PowerShell\Modules\{0}\{1}" -f $ModuleName, $Version.ToString())
            }
        }
        default {
            if ($PSVersionTable.PsEdition -eq "Desktop") {
                $ModuleTargetFolder = Join-Path $HOME -ChildPath ("Documents\WindowsPowerShell\Modules\{0}\{1}" -f $ModuleName, $Version.ToString())
            }
            else {
                $ModuleTargetFolder = Join-Path $HOME -ChildPath ("Documents\PowerShell\Modules\{0}\{1}" -f $ModuleName, $Version.ToString())
            }
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

    "Deploy {0} PowerShell module from {1} to {2}" -f $ModuleName, $ModuleSourceFolder, $ModuleTargetFolder | Write-Host
    New-Item $ModuleTargetFolder -ItemType Directory -Force | Out-Null
    Get-ChildItem -Path $ModuleSourceFolder | Copy-Item -Destination $ModuleTargetFolder -Recurse -Force
    Get-ChildItem $ModuleTargetFolder -Recurse | Unblock-File
    Get-ChildItem $ModuleTargetFolder | Where-Object { $_.Name -notin @("OmadaWeb.PS.psm1", "OmadaWeb.PS.psd1") } | Remove-Item -Force
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
