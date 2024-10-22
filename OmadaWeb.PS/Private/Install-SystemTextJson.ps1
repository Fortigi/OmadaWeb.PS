function Install-SystemTextJson {
    $DllFileName = "System.Text.Json.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName, $WebDriverBasePath, $_.Exception | Write-Warning
        break
    }

    "'{0}' is needs to be downloaded. Downloading from GitHub" -f $DllFileName | Write-Host
    $Uri = "https://www.nuget.org/api/v2/package/System.Text.Json/"

    $null = New-Item (Split-Path $Script:WebDriverPath) -ItemType Directory -Force

    $TempFile = Invoke-DownloadFile -DownloadUrl $Uri

    $TempZipPath = Expand-DownloadFile -FilePath $TempFile


    if ((((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "lib") -Filter "net4*")) | Measure-Object).Count -gt 0) {
        "Use net4* DLL" | Write-Verbose

        try {
            Get-ChildItem ((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "lib") -Filter "net4*" | Select-Object -Last 1)).FullName -Filter $DllFileName | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
        }
        catch {
            if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
                "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName, $WebDriverBasePath, $_.Exception | Write-Warning
                return $false
            }
            else {
                Throw $_
            }
        }
    }
    else {
        "net4* DLL missing, using net2* DLL" | Write-Verbose

        try {
            Get-ChildItem ((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "lib") -Filter "netstandard2.0" | Select-Object -Last 1)).FullName -Filter $DllFileName | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
            $CheckJsonLibrary = $true
        }
        catch {
            if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
                "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName, $WebDriverBasePath, $_.Exception | Write-Warning
                return $false
            }
            else {
                Throw $_
            }
        }
    }
    "Installed '{0}' version {1}" -f $DllFileName, (Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host

    Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse

    return $CheckJsonLibrary
}


