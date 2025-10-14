function Install-EdgeDriver {
    [CmdletBinding()]
    PARAM()

    $EdgeDriverFileName = "msedgedriver.exe"

    try {
        "{0} - Check and install EdgeDriver" -f $MyInvocation.MyCommand | Write-Verbose
        $ComputerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
        switch ($ComputerInfo.SystemType) {
            "x64-based PC" { $Arch = "win64" }
            "x86-based PC" { $Arch = "win32" }
            default { $Arch = "win64" }
        }

        #Download correct version
        $EdgeWebdriverDownloadBaseUrl = "https://msedgedriver.microsoft.com/"
        $EdgeWebdriverFileName = "edgedriver_{0}.zip" -f $Arch
        #Example: https://msedgedriver.microsoft.com/128.0.2739.33/edgedriver_win64.zip
        $EdgeWebdriverDownloadUrl = "{0}{1}/{2}" -f $EdgeWebdriverDownloadBaseUrl, $($InstalledEdgeFileInfo.VersionInfo.ProductVersion), $EdgeWebdriverFileName
        "Download URL: {0}" -f $EdgeWebdriverDownloadUrl | Write-Verbose

        $null = New-Item (Split-Path $Script:EdgeDriverPath) -ItemType Directory -Force

        $TempFile = [System.IO.Path]::GetTempFileName()
        "Invoke-WebEdgeDriverFramework: {0}" -f $$ | Write-Verbose

        $TempFile = Invoke-DownloadFile -DownloadUrl $EdgeWebdriverDownloadUrl

        $TempZipPath = Expand-DownloadFile -FilePath $TempFile

    }
    catch {
        if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
            "Failed to update '{0}'. Try downloading the webdriver manually from '{1}' and place it here: '{2}'. Error:`r`n {3}" -f $EdgeDriverFileName, $EdgeWebdriverDownloadUrl, $WebDriverBasePath, $_.Exception | Write-Error -ErrorAction Stop
        }
        else {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }

    try {
        Get-Item (Join-Path $TempZipPath -ChildPath $EdgeDriverFileName ) | Move-Item -Destination (Split-Path $Script:EdgeDriverPath) -Force
    }
    catch {
        if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
            "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Error:`r`n {2}" -f $EdgeDriverFileName, $WebDriverBasePath, $_.Exception | Write-Error -ErrorAction Stop
        }
        else {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }

    if (Test-Path $TempZipPath -PathType Container) {
        Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse
    }

    return $false
}