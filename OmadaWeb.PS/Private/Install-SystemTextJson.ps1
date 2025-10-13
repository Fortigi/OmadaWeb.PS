function Install-SystemTextJson {
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'CheckJsonLibrary', Justification = 'The CheckJsonLibrary returned from this function')]
    [CmdletBinding()]
    PARAM()

    "{0} - Installing System.Text.Json" -f $MyInvocation.MyCommand | Write-Verbose

    $DllFileName = "System.Text.Json.dll"
    if (Test-Path (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName) -PathType Leaf) {
        "Failed to update '{0}'. Retry restarting this PowerShell session or manually remove the contents of folder '{1}'. Reuse current version for now. " -f $DllFileName, $WebDriverBasePath | Write-Warning
        break
    }

    $CheckJsonLibrary = $false

    "'{0}' needs to be downloaded. Downloading from NuGet" -f $DllFileName | Write-Host
    $null = New-Item (Split-Path $Script:WebDriverPath) -ItemType Directory -Force
    $NuGetResults = Get-NuGetPackage -PackageName "System.Text.Json" -TargetFramework ".NETFramework4*" -RequiredVersion "8.0.5"
    $NuGetResults | ForEach-Object {
        $NuGetResult = $_
        $NuGetResult.PackageEntries | Where-Object { $_ -like "*lib\net4*" } | ForEach-Object {
            if (Test-Path $_ -PathType Leaf) {
                "Copy net4 version" | Write-Verbose
                Copy-Item -Path $_ -Destination (Split-Path $Script:WebDriverPath) -Force
            }
            else {
                "Net4 version not found, using netstandard2.0 version" | Write-Verbose
                Get-Item ($NuGetResult.PackageEntries | Where-Object { $_ -like "*lib\netstandard2.0*" } | Select-Object -Last 1) | Copy-Item -Destination (Split-Path $Script:WebDriverPath) -Force

                if ($_ -like "*$DllFileName") {
                    $CheckJsonLibrary = $true
                }
            }
        }
        Remove-Item $($_.PackageTempPath) -Force -Confirm:$false -Recurse
    }
    "Installed '{0}' version {1}" -f $DllFileName, (Get-Item (Join-Path (Split-Path $Script:WebDriverPath) -ChildPath $DllFileName)).VersionInfo.ProductVersion | Write-Host
    return $CheckJsonLibrary
}