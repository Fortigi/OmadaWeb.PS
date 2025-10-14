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

    if ($PSVersionTable.PSVersion.Major -le 5) {
        "Using version 4.23 of Selenium because newer versions are currently not compatible with PowerShell 5.1" | Write-Warning

        $TempZipPath = Get-GitHubRelease -Org $Org -Repo $Repo -TagFilter "*4.23*" -AssetFilter $AssetFilter
    }
    else {
        $TempZipPath = Get-GitHubRelease -Org $Org -Repo $Repo -AssetFilter $AssetFilter
    }

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
                $PSCmdlet.ThrowTerminatingError($PSItem)
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