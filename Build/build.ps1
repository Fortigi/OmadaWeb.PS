#Requires -Version 5.1
[CmdletBinding()]
param(
    [string[]]$Task = 'default',
    [string[]]$BuildVersion = ""
)
$Error.Clear()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
try {
    # Version floors below avoid picking up Windows PowerShell's older inbox/cached module versions:
    # Pester 5+ is required for New-PesterContainer/New-PesterConfiguration (Pester 3.4.0 ships inbox with PS 5.1),
    # and PSScriptAnalyzer 1.22.0+ is required for the PSAvoidAssignmentToAutomaticVariable suppression used in the module.
    if (!(Get-Module -Name Pester -ListAvailable | Where-Object Version -ge '5.0')) { Install-Module -Name Pester -Scope CurrentUser -Force -SkipPublisherCheck }
    if (!(Get-Module -Name psake -ListAvailable)) { Install-Module -Name psake -Scope CurrentUser -Force }
    if (!(Get-Module -Name PSDeploy -ListAvailable)) { Install-Module -Name PSDeploy -Scope CurrentUser -Force }
    if (!(Get-Module -Name PSScriptAnalyzer -ListAvailable | Where-Object Version -ge '1.22.0')) { Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force -SkipPublisherCheck }
    if (!(Get-Module -Name ThreadJob -ListAvailable) -and !(Get-Command -Name Start-ThreadJob -ErrorAction SilentlyContinue)) { Install-Module -Name ThreadJob -Scope CurrentUser -Force -AllowClobber }


    Invoke-psake -buildFile "$PSScriptRoot\psakeBuild.ps1" -taskList $Task -Verbose:$VerbosePreference -parameters @{"BuildVersion" = $BuildVersion }

    if (!$psake.build_success) {
        throw "psake build failed, see output above for details."
    }
}
catch {
    $PSCmdlet.ThrowTerminatingError($PSItem)
    exit 1
}
