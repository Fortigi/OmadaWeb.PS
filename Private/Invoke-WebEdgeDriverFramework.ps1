function Invoke-WebEdgeDriverFramework {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'CheckJsonLibrary', Justification = 'The CheckJsonLibrary variable is used in a function called from here')]
    PARAM()
    $InstallOrUpdateEdgeDriver = $false
    $InstalledEdgeVersion = Get-Item $Script:InstalledEdgeFilePath
    if ($Null -ne $InstalledEdgeVersion) {
        $InstalledEdgeVersionMajor = "{0:d5}" -f [int]($($InstalledEdgeVersion.VersionInfo.ProductVersion).Substring(0, $($InstalledEdgeVersion.VersionInfo.ProductVersion).IndexOf(".")))
    }
    else {
        "Cannot find Edge at '{0}'. Is it installed?" -f $Script:InstalledEdgeFilePath | Write-Error -ErrorAction "Stop"
    }
    if (!(Test-Path $Script:EdgeDriverPath -PathType Leaf)) {
        "msedgedriver.exe needs to be downloaded. Downloading from Microsoft" | Write-Host
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

    $CheckJsonLibrary = $false
    $JsonLibraryType = $null
    if ($InstallOrUpdateEdgeDriver) {
        $InstallOrUpdateEdgeDriver = Install-EdgeDriver
    }

    if (!(Test-Path $Script:WebDriverPath -PathType Leaf)) {
        Install-Selenium
    }

    $WebDriverDll = Get-Item $Script:WebDriverPath
    switch ($WebDriverDll.VersionInfo.ProductMajorPart) {
        { $_ -eq 4 } {
            switch ($WebDriverDll.VersionInfo.ProductMinorPart) {
                { $_ -ge 12 -and $_ -lt 24 } {
                    $JsonLibraryType = "Newtonsoft.Json"
                    if (!(Test-Path $Script:NewtonsoftJsonPath -PathType Leaf)) {
                        $CheckJsonLibrary = Install-NewtonSoftJson
                    }
                }
                { $PSVersionTable.PSVersion.Major -le 5 -and $_ -ge 24 } {
                    $JsonLibraryType = "System.Text.Json"

                    if (!(Test-Path $Script:SystemTextJsonPath -PathType Leaf)) {
                        $CheckJsonLibrary = Install-SystemTextJson
                    }
                    if (!(Test-Path $Script:SystemRuntimePath -PathType Leaf)) {
                        $CheckJsonLibrary = Install-SystemRunTime
                    }
                }
                default {}
            }
        }
        { $_ -gt 4 } {
            if ($PSVersionTable.PSVersion.Major -le 5 -and $WebDriverDll.VersionInfo.ProductMinorPart -ge 24) {
                $JsonLibraryType = "System.Text.Json"
                if (!(Test-Path $Script:SystemTextJsonPath -PathType Leaf)) {
                    $CheckJsonLibrary = Install-SystemTextJson
                }
                if (!(Test-Path $Script:SystemRuntimePath -PathType Leaf)) {
                    $CheckJsonLibrary = Install-SystemRunTime
                }
            }
        }
        default {
            "Version {0} is not supported" -f $_.FileVersion.ProductVersion | Write-Error -ErrorAction Stop
            break
        }
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
    else{
        "Using '{0}' version {1}" -f (Get-Item $Script:EdgeDriverPath).Name,(Get-Item $Script:EdgeDriverPath).VersionInfo.ProductVersion | Write-Host
    }

    return $JsonLibraryType
}