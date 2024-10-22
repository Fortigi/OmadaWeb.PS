function Install-NewtonSoftJson {

    $DllFileName = "Newtonsoft.Json.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName, $WebDriverBasePath, $_.Exception | Write-Warning
        break
    }

    $null = New-Item (Split-Path $Script:NewtonsoftJsonPath) -ItemType Directory -Force
    "'{0}' needs to be downloaded. Downloading from GitHub" -f $DllFileName | Write-Host
    $DownloadUrl = "https://api.github.com"
    $URI = $DownloadUrl, "/repos/JamesNK/Newtonsoft.Json/releases" -join ""
    try {
        $Result = Invoke-RestMethod -Method Get -Uri $URI -ErrorAction SilentlyContinue -UseBasicParsing

    }
    catch {
        "Could not download the Newtonsoft.Json.dll. Please manually download the latest Json130*.zip from 'https://github.com/JamesNK/Newtonsoft.Json/releases/' extract the net48 or netstandard20 Newtonsoft.Json.dll and place it in directory '{0}'." -f (Split-Path $Script:WebDriverPath) | Write-Error -ErrorAction "Stop"
    }
    $LatestRelease = $Result | Where-Object { $_.tag_name -ne "nightly" -and $_.prerelease -eq $false -and $_.draft -eq $false -and $_.name.startswith("13") } | Sort-Object published_at | Select-Object -Last 1
    "Installing '{0}' version {1}" -f $DllFileName, ($LatestRelease.tag_name) | Write-Host

    $Asset = $LatestRelease.assets | Where-Object { $_.name -match "(Json130)*.zip" }

    $TempFile = Invoke-DownloadFile -DownloadUrl $Asset.'browser_download_url'

    $TempZipPath = Expand-DownloadFile -FilePath $TempFile

    try {
        Get-ChildItem ((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "bin") -Filter "netstandard2.0" | Select-Object -Last 1)).FullName -Filter $DllFileName | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
    }
    catch {
        if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
            "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName,$WebDriverBasePath, $_.Exception | Write-Warning
            return $false
        }
        else {
            Throw $_
        }
    }

    "Installed '{0}' version {1}" -f $DllFileName,(Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse

    return $false
}