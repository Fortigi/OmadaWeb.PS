function Install-SystemRunTime {
    [CmdletBinding()]
    PARAM()

    "{0} - Installing System.Runtime" -f $MyInvocation.MyCommand | Write-Verbose

    $DllFileName = "System.Runtime.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. " -f $DllFileName, $WebDriverBasePath | Write-Warning
        break
    }

    "'{0}' needs to be downloaded. Downloading from NuGet" -f $DllFileName | Write-Host

    $CheckJsonLibrary = Install-LockedPackageGroup -Group "SystemRuntime" -PrimaryDllFileName $DllFileName

    "Installed '{0}' version {1}" -f $DllFileName, (Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    return $CheckJsonLibrary
}
