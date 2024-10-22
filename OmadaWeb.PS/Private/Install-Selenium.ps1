function Install-Selenium {
    $DllFileName = "WebDriver.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName, $WebDriverBasePath, $_.Exception | Write-Warning
        break
    }

    $CheckJsonLibrary = $false

    "WebDriver.dll needs to be downloaded. Downloading from GitHub" | Write-Host
    $DownloadUrl = "https://api.github.com"
    $URI = $DownloadUrl, "/repos/SeleniumHQ/selenium/releases" -join ""
    $null = New-Item (Split-Path $Script:WebDriverPath) -ItemType Directory -Force

    try {
        $Result = Invoke-RestMethod -Method Get -Uri $URI -ErrorAction SilentlyContinue -UseBasicParsing
    }
    catch {
        "Could not download the Edge web driver. Please manually download the latest selenium-dotnet-x.x.0.zip from 'https://github.com/SeleniumHQ/selenium/releases/' extract the net48 or netstandard20 WebDriver.dll and place it in directory '{0}'." -f (Split-Path $Script:WebDriverPath) | Write-Error -ErrorAction "Stop"
    }

    if ($PSVersionTable.PSVersion.Major -le 5) {
        "Using version 4.23 of Selenium because newer versions are currently not compatible with PowerShell 5.1" | Write-Warning
        $LatestRelease = $Result | Where-Object { $_.tag_name -like "*4.23*" } | Sort-Object published_at | Select-Object -Last 1
    }
    else {
        $LatestRelease = $Result | Where-Object { $_.tag_name -ne "nightly" -and $_.prerelease -eq $false -and $_.draft -eq $false } | Sort-Object published_at | Select-Object -Last 1
        "Installing Selenium version {0}" -f ($LatestRelease.tag_name.Split("-")[-1]) | Write-Host
    }
    $Asset = $LatestRelease.assets | Where-Object { $_.name -match ".*dotnet.(?!strongnamed).*\.0\.zip" }

    $TempFile = Invoke-DownloadFile -DownloadUrl $Asset.'browser_download_url'

    $TempZipPath = Expand-DownloadFile -FilePath $TempFile

    $Package = Get-ChildItem $($TempZipPath.FullName) -Filter "*WebDriver*.nupkg"
    $NuPkgZip = Get-Item $($Package.FullName) | Rename-Item -NewName ("{0}.zip" -f $Package.FullName) -PassThru
    $NuPkgPath = New-Item (Join-Path (Get-Item $NuPkgZip).PsParentPath -ChildPath $NuPkgZip.BaseName) -ItemType Directory -Force
    Get-Item $NuPkgZip | Expand-Archive -Destination $($NuPkgPath.FullName) -Force
    if ((((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "net4*")) | Measure-Object).Count -gt 0) {
        "Use net4* DLL" | Write-Verbose
        try {
            Get-ChildItem ((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "net4*" | Select-Object -Last 1)).FullName -Filter $DllFileName | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
        }
        catch {
            if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
                "Failed to update 'Webdriver.dll'. Retry restarting this PowerShell session or manually remove the contents of folder '{0}'. Reuse current version for now. Error:`r`n {1}" -f $WebDriverBasePath, $_.Exception | Write-Warning
            }
            else {
                Throw $_
            }
        }

    }
    else {
        "net4* DLL missing, using net2* DLL" | Write-Verbose
        try {
            Get-ChildItem ((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "netstandard2.0" | Select-Object -Last 1)).FullName -Filter "WebDriver.dll" | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
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

        $CheckJsonLibrary = $true
    }

    "Installed '{0}' version {1}" -f $DllFileName,(Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse

}