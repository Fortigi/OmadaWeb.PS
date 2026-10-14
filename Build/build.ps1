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
    # The module list lives in InstallModules.ps1 alone, so CI and a local build install the same
    # pinned versions. Its failure path is a Write-Error, which $ErrorActionPreference = "Stop" above
    # turns into a terminating error here.
    & (Join-Path -Path $PSScriptRoot -ChildPath "InstallModules.ps1")
    # Loaded explicitly: Windows PowerShell 5.1 ships Pester 3.4.0 inbox, and autoloading would pick
    # whichever version happens to be newest rather than the pinned one.
    Import-Module -Name Pester -RequiredVersion "6.2.0" -Force

    Invoke-psake -buildFile "$PSScriptRoot\psakeBuild.ps1" -taskList $Task -Verbose:$VerbosePreference -parameters @{"BuildVersion" = $BuildVersion }

    if (!$psake.build_success) {
        throw "psake build failed, see output above for details."
    }
}
catch {
    $PSCmdlet.ThrowTerminatingError($PSItem)
    exit 1
}
