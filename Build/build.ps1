#Requires -Version 7.0
#Requires -PSEdition Core
[CmdletBinding()]
param(
    [string[]]$Task = 'default',
    [string[]]$BuildVersion = ""
)
$Error.Clear()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
try {
    if (!(Get-Module -Name Pester -ListAvailable)) { Install-Module -Name Pester -Scope CurrentUser -Force }
    if (!(Get-Module -Name psake -ListAvailable)) { Install-Module -Name psake -Scope CurrentUser -Force }
    if (!(Get-Module -Name PSDeploy -ListAvailable)) { Install-Module -Name PSDeploy -Scope CurrentUser -Force }
    if (!(Get-Module -Name PSScriptAnalyzer -ListAvailable)) { Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force }


    Invoke-psake -buildFile "$PSScriptRoot\psakeBuild.ps1" -taskList $Task -Verbose:$VerbosePreference -parameters @{"BuildVersion" = $BuildVersion }
}
catch {
    $PSCmdlet.ThrowTerminatingError($PSItem)
    exit 1
}
