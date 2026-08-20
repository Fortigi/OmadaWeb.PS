function Get-NuGetLibraryFolder {
    [CmdletBinding()]
    PARAM(
        [parameter(Mandatory = $true)]
        [string]$PackagePath,
        [parameter(Mandatory = $false)]
        [ValidateSet("Net4OrNetStandard", "NetStandard")]
        [string]$TargetFramework = "Net4OrNetStandard"
    )

    # Picks the lib\<tfm> folder to install from, reproducing the choice the module has always made:
    # the highest net4* build when the package ships one, otherwise the netstandard2.0 build. The
    # caller can tell which it got from the returned folder's Name.
    $LibPath = Join-Path $PackagePath -ChildPath "lib"
    if (-not (Test-Path $LibPath -PathType Container)) {
        "The downloaded package at '{0}' has no 'lib' folder, so there is nothing to install from." -f $PackagePath | Write-Error -ErrorAction "Stop"
    }

    if ($TargetFramework -ne "NetStandard") {
        $Net4Folder = Get-ChildItem -Path $LibPath -Filter "net4*" -Directory | Sort-Object Name | Select-Object -Last 1
        if ($null -ne $Net4Folder) {
            "{0} - Using '{1}' build from '{2}'" -f $MyInvocation.MyCommand, $Net4Folder.Name, $PackagePath | Write-Verbose
            return $Net4Folder
        }
        "{0} - No net4* build present, falling back to netstandard2.0" -f $MyInvocation.MyCommand | Write-Verbose
    }

    $NetStandardFolder = Get-ChildItem -Path $LibPath -Filter "netstandard2.0" -Directory | Select-Object -Last 1
    if ($null -eq $NetStandardFolder) {
        "The downloaded package at '{0}' has neither a net4* nor a netstandard2.0 build." -f $PackagePath | Write-Error -ErrorAction "Stop"
    }

    "{0} - Using '{1}' build from '{2}'" -f $MyInvocation.MyCommand, $NetStandardFolder.Name, $PackagePath | Write-Verbose
    return $NetStandardFolder
}
