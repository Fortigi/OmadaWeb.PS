function Install-Selenium {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'CheckJsonLibrary', Justification = 'The CheckJsonLibrary variable is used in a function called from here')]
    [CmdletBinding()]
    PARAM()

    "{0} - Installing Selenium WebDriver" -f $MyInvocation.MyCommand | Write-Verbose

    $DllFileName = "WebDriver.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. " -f $DllFileName, $WebDriverBasePath | Write-Warning
        break
    }

    $CheckJsonLibrary = $false

    "WebDriver.dll needs to be downloaded. Downloading from GitHub" | Write-Host
    $null = New-Item (Split-Path $Script:WebDriverPath) -ItemType Directory -Force

    $Org = "SeleniumHQ"
    $Repo = "selenium"
    $AssetFilter = ".*dotnet.(?!strongnamed).*\.0\.zip"

    if ($Script:PowerShellType -eq "Desktop") {
        # Selenium's .NET bindings dropped .NET Framework (net4*) targets and went netstandard2.0-only
        # starting with selenium-4.12.0, which Windows PowerShell 5.1 (Desktop, .NET Framework) cannot load.
        # Pin to the last release that still ships a net4* build. Downloaded directly by tag/asset name
        # instead of via Get-GitHubRelease, since that helper lists only the ~30 most recent releases and
        # would never find a release this old among Selenium's frequent release cadence.
        $PinnedTag = "selenium-4.11.0"
        $PinnedAsset = "selenium-dotnet-4.11.0.zip"
        $DownloadUrl = "https://github.com/{0}/{1}/releases/download/{2}/{3}" -f $Org, $Repo, $PinnedTag, $PinnedAsset
        "Retrieving '{0}' version {1}" -f $Repo, $PinnedTag | Write-Host
        $TempFile = Invoke-DownloadFile -DownloadUrl $DownloadUrl
        $TempZipPath = Expand-DownloadFile -FilePath $TempFile
    }
    else {
        $TempZipPath = Get-GitHubRelease -Org $Org -Repo $Repo -AssetFilter $AssetFilter
    }

    $Package = Get-ChildItem $($TempZipPath.FullName) -Filter "*WebDriver*.nupkg" -Recurse
    if (-not $Package) {
        "Could not find a '*WebDriver*.nupkg' package inside the downloaded archive from '{0}'" -f $TempZipPath.FullName | Write-Error -ErrorAction Stop
    }
    $NuPkgZip = Get-Item $($Package.FullName) | Rename-Item -NewName ("{0}.zip" -f $Package.FullName) -PassThru
    $NuPkgPath = New-Item (Join-Path (Get-Item $NuPkgZip).PsParentPath -ChildPath $NuPkgZip.BaseName) -ItemType Directory -Force
    Get-Item $NuPkgZip | Expand-Archive -Destination $($NuPkgPath.FullName) -Force
    if ((((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "net4*")) | Measure-Object).Count -gt 0) {
        "Use net4* DLL" | Write-Verbose
        try {
            Get-ChildItem ((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "net4*" | Select-Object -Last 1)).FullName -Filter "*$DllFileName" | Select-Object -First 1 | Copy-Item -Destination $Script:WebDriverPath -Force
        }
        catch {
            if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
                "Failed to update 'Webdriver.dll'. Retry restarting this PowerShell session or manually remove the contents of folder '{0}'. Reuse current version for now. Error:`r`n {1}" -f $WebDriverBasePath, $_.Exception | Write-Warning
            }
            else {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }

    }
    else {
        "net4* DLL missing, using net2* DLL" | Write-Verbose
        try {
            Get-ChildItem ((Get-ChildItem (Join-Path $($NuPkgPath.FullName) -ChildPath "lib") -Filter "netstandard2.0" | Select-Object -Last 1)).FullName -Filter "*$DllFileName" | Select-Object -First 1 | Copy-Item -Destination $Script:WebDriverPath -Force
        }
        catch {
            if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
                "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. Error:`r`n {2}" -f $DllFileName, $WebDriverBasePath, $_.Exception | Write-Warning
                return $false
            }
            else {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }

        $CheckJsonLibrary = $true
    }

    "Installed '{0}' version {1}" -f $DllFileName, (Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse
}