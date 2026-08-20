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

    "WebDriver.dll needs to be downloaded. Downloading from NuGet" | Write-Host
    $null = New-Item (Split-Path $Script:WebDriverPath) -ItemType Directory -Force

    # Selenium's .NET bindings dropped .NET Framework (net4*) targets and went netstandard2.0-only
    # starting with selenium-4.12.0, which Windows PowerShell 5.1 (Desktop, .NET Framework) cannot
    # load, so Desktop and Core resolve to different pins in the lock file.
    $ArtifactId = "Selenium.Core"
    if ($Script:PowerShellType -eq "Desktop") {
        $ArtifactId = "Selenium.Desktop"
    }

    $Artifact = Get-LockedArtifact -Id $ArtifactId
    "Retrieving '{0}' version {1}" -f $Artifact.PackageId, $Artifact.Version | Write-Host

    $TempFile = Invoke-DownloadFile -ArtifactId $ArtifactId
    $TempZipPath = Expand-DownloadFile -FilePath $TempFile

    $LibraryFolder = Get-NuGetLibraryFolder -PackagePath $($TempZipPath.FullName) -TargetFramework $Artifact.TargetFramework

    try {
        # Filter and destination both match the historical behaviour: newer Selenium releases name the
        # assembly Selenium.WebDriver.dll, and copying to the full path lands it as WebDriver.dll.
        Get-ChildItem $($LibraryFolder.FullName) -Filter "*$DllFileName" | Select-Object -First 1 | Copy-Item -Destination $Script:WebDriverPath -Force
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

    if ($LibraryFolder.Name -eq "netstandard2.0") {
        $CheckJsonLibrary = $true
    }

    "Installed '{0}' version {1}" -f $DllFileName, (Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse
}
