function Invoke-WebEdgeDriverFramework {

    $InstallOrUpdateEdgeDriver = $false
    $InstalledEdgeVersion = Get-Item $Script:InstalledEdgeFilePath
    if ($Null -ne $InstalledEdgeVersion) {
        $InstalledEdgeVersionMajor = "{0:d5}" -f [int]($($InstalledEdgeVersion.VersionInfo.ProductVersion).Substring(0, $($InstalledEdgeVersion.VersionInfo.ProductVersion).IndexOf(".")))
    }
    else {
        "Cannot find Edge at '{0}'. Is it installed?" -f $Script:InstalledEdgeFilePath | Write-Error -ErrorAction "Stop"
    }
    if (!(Test-Path $Script:EdgeDriverPath -PathType Leaf)) {
        "msedgedriver.exe missing, downloading latest version from Microsoft" | Write-Host
        $InstallOrUpdateEdgeDriver = $true
    }
    elseif (Test-Path $Script:EdgeDriverPath -PathType Leaf) {
        $MsEdgeDriverFileInfo = Get-Item $Script:EdgeDriverPath
        $MsEdgeDriverFileVersionMajor = "{0:d5}" -f [int]($($MsEdgeDriverFileInfo.VersionInfo.ProductVersion).Substring(0, $($MsEdgeDriverFileInfo.VersionInfo.ProductVersion).IndexOf(".")))
        if ($InstalledEdgeVersionMajor -ne $MsEdgeDriverFileVersionMajor) {
            "msedgedriver.exe must be updated, downloading correct version from Microsoft" | Write-Host
            $InstallOrUpdateEdgeDriver = $true
        }
    }

    $CheckNewtonSoftJson = $false
    if ($InstallOrUpdateEdgeDriver) {
        $InstallOrUpdateEdgeDriver = Install-EdgeDriver
    }

    if (!(Test-Path $Script:WebDriverPath -PathType Leaf)) {
        $CheckNewtonSoftJson = Install-Selenium
    }
    else {
        $WebDriverDll = Get-Item $Script:WebDriverPath
        if (($WebDriverDll.VersionInfo.ProductMajorPart -eq 4 -and $WebDriverDll.VersionInfo.ProductMinorPart -ge 12) -or $WebDriverDll.VersionInfo.ProductMajorPart -gt 4) {
            $CheckNewtonSoftJson = $true
        }
    }

    if ( $CheckNewtonSoftJson -and !(Test-Path $Script:NewtonsoftJsonPath -PathType Leaf)) {
        $CheckNewtonSoftJson = Install-NewtonSoftJson
    }

    $Missing = $false
    $MissingString = @()
    if (!(Test-Path $Script:EdgeDriverPath -PathType Leaf)) {
        $Missing = $true
        $MissingString += "'msedgedriver.exe'"

    }
    if (!(Test-Path $Script:WebDriverPath -PathType Leaf)) {
        $Missing = $true
        $MissingString += "'WebDriver.dll'"
    }
    if ($Missing) {
        "{0} cannot be found in folder '{1}'" -f ($MissingString -Join " and "), (Split-Path $Script:EdgeDriverPath) | Write-Error -ErrorAction "Stop"
    }
}
