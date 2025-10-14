function Install-NewtonSoftJson {
    [CmdletBinding()]
    PARAM()

    "{0} - Check and install Newtonsoft.Json" -f $MyInvocation.MyCommand | Write-Verbose

    $DllFileName = "Newtonsoft.Json.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. " -f $DllFileName, $WebDriverBasePath | Write-Warning
        break
    }

    "'{0}' needs to be downloaded. Downloading from GitHub" -f $DllFileName | Write-Host
    $null = New-Item (Split-Path $Script:NewtonsoftJsonPath) -ItemType Directory -Force
    $TempZipPath = Get-GitHubRelease -Org "JamesNK" -Repo "Newtonsoft.Json" -TagFilter "13**" -AssetFilter "Json130.*.zip"

    try {
        Get-ChildItem ((Get-ChildItem (Join-Path $($TempZipPath.FullName) -ChildPath "bin") -Filter "netstandard2.0" | Select-Object -Last 1)).FullName -Filter $DllFileName | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force
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

    "Installed '{0}' version {1}" -f $DllFileName, (Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    Remove-Item $($TempZipPath.FullName) -Force -Confirm:$false -Recurse

    return $false
}