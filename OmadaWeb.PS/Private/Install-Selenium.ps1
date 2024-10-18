function Install-Selenium {
    $CheckNewtonSoftJson = $false
    $null = New-Item (Split-Path $Script:WebDriverPath) -ItemType Directory -Force
    "Downloading latest WebDriver.Dll missing, downloading latest version from GitHub" | Write-Host
    $DownloadUrl = "https://api.github.com"
    $URI = $DownloadUrl, "/repos/SeleniumHQ/selenium/releases" -join ""
    try {
        $Result = Invoke-RestMethod -Method Get -Uri $URI -ErrorAction SilentlyContinue -UseBasicParsing
    }
    catch {
        "Could not download the Edge web driver. Please manually download the latest selenium-dotnet-x.x.0.zip from 'https://github.com/SeleniumHQ/selenium/releases/' extract the net48 or netstandard20 WebDriver.dll and place it in directory '{0}'." -f (Split-Path $Script:WebDriverPath) | Write-Error -ErrorAction "Stop"
    }
    $LatestRelease = $Result | Where-Object { $_.tag_name -ne "nightly" -and $_.prerelease -eq $false -and $_.draft -eq $false } | Sort-Object published_at | Select-Object -Last 1
    $Asset = $LatestRelease.assets | Where-Object { $_.name -match ".*dotnet.(?!strongnamed).*\.0\.zip" }
    $TempFile = [System.IO.Path]::GetTempFileName()
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile($Asset.'browser_download_url', $TempFile)

    $TempFile = Get-Item $TempFile | Rename-Item -NewName ("{0}.zip" -f $TempFile) -PassThru
    $TempZipFullName = (Join-Path (Get-Item $TempFile).PsParentPath -ChildPath $($TempFile.BaseName.Substring(0, $TempFile.BaseName.IndexOf("."))))
    $TempZipPath = New-Item $TempZipFullName -ItemType Directory -Force
    Get-Item $TempFile | Expand-Archive -DestinationPath $($TempZipPath.FullName)
    $Package = Get-ChildItem $TempZipPath -Filter "*WebDriver*.nupkg"
    $NuPkgZip = Get-Item $($Package.FullName) | Rename-Item -NewName ("{0}.zip" -f $Package.FullName) -PassThru
    $NuPkgPath = New-Item (Join-Path (Get-Item $NuPkgZip).PsParentPath -ChildPath $NuPkgZip.BaseName) -ItemType Directory -Force
    Get-Item $NuPkgZip | Expand-Archive -Destination $($NuPkgPath.FullName) -Force
    if ((((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "net4*")) | Measure-Object).Count -gt 0) {
        "Use net4* DLL" | Write-Verbose
        Get-ChildItem ((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "net4*" | Select-Object -Last 1)).FullName -Filter "WebDriver.dll" | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
    }
    else {
        "net4* DLL missing, using net2* DLL" | Write-Verbose
        Get-ChildItem ((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "netstandard2.0" | Select-Object -Last 1)).FullName -Filter "WebDriver.dll" | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
        $CheckNewtonSoftJson = $true
    }

    Remove-Item $TempZipPath -Force -Confirm:$false -Recurse
    Remove-Item $TempFile -Force -Confirm:$false -Recurse
    return $CheckNewtonSoftJson
}