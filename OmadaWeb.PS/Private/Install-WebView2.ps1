function Install-WebView2 {
    <#
    .SYNOPSIS
    Installs or verifies the WebView2 runtime and assemblies.

    .DESCRIPTION
    This function ensures that the Microsoft WebView2 runtime is available and installs the WebView2 NuGet package
    for PowerShell integration if needed.

    .EXAMPLE
    Install-WebView2
    #>

    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        if (-not (Test-Path $Script:WebView2WinFormsPath -PathType Leaf) -or -not (Test-Path $Script:WebView2CorePath -PathType Leaf)) {
            "'Microsoft.Web.WebView2' needs to be downloaded. Downloading from NuGet" | Write-Host

            #TODO: Troubleshoot why Get-NuGetPackage does not work here as expected
            #$NuGetResults = Get-NuGetPackage -PackageName "Microsoft.Web.WebView2"

            $PackageUrl = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2"

            try {
                $TempFile = Invoke-DownloadFile -DownloadUrl $PackageUrl

                $TempZipPath = Expand-DownloadFile -FilePath $TempFile

                if ($PSVersionTable.PSEdition -eq "Core") {
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq "netcoreapp3.0" } | Select-Object -First 1 | Copy-Item -Destination $Script:BinPath -Force
                    "Installed 'Microsoft.Web.WebView2.WinForms.dll' version {0}" -f (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion | Write-Host
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq "netcoreapp3.0" } | Select-Object -First 1 | Copy-Item -Destination $Script:BinPath -Force
                    "Installed 'Microsoft.Web.WebView2.Core.dll' version {0}" -f (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion | Write-Host
                }
                else {
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination $Script:BinPath -Force
                    "Installed 'Microsoft.Web.WebView2.WinForms.dll' version {0}" -f (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion | Write-Host
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination $Script:BinPath -Force
                    "Installed 'Microsoft.Web.WebView2.Core.dll' version {0}" -f (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion | Write-Host
                }
                Remove-Item -Path $TempZipPath -Force -Recurse
                "WebView2 package installed successfully" | Write-Verbose
            }
            catch {
                "Failed to download WebView2 package: {0}" -f $_.Exception.Message | Write-Error
                return $false
            }
        }

        return $true
    }
    catch {
        "Failed to install WebView2: {0}" -f $_.Exception.Message | Write-Error
        return $false
    }
}