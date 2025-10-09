function Install-WebView2 {
    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        if (-not (Test-Path $Script:WebView2WinFormsPath -PathType Leaf) -or -not (Test-Path $Script:WebView2CorePath -PathType Leaf) -or -not (Test-Path $Script:WebView2LoaderPath -PathType Leaf)) {
            "'Microsoft.Web.WebView2' needs to be downloaded. Downloading from NuGet" | Write-Host

            #TODO: Troubleshoot why Get-NuGetPackage does not work here as expected
            #$NuGetResults = Get-NuGetPackage -PackageName "Microsoft.Web.WebView2"

            $PackageUrl = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.3537.50"

            $DirectoryName = "net462"
            $NuGetDirectoryPath = ".\lib\net462"
            if ($PSVersionTable.PSEdition -eq "Core") {
                $DirectoryName = "netcoreapp3.0"
                $NuGetDirectoryPath = ".\lib_manual\netcoreapp3.0"
            }
            $RuntimeFolder = "win-x64"
            if ($Env:PROCESSOR_ARCHITECTURE -eq "x86") {
                $RuntimeFolder = "win-x86"
            }

            try {
                $TempFile = Invoke-DownloadFile -DownloadUrl $PackageUrl

                $TempZipPath = Expand-DownloadFile -FilePath $TempFile

                if ($PSVersionTable.PSEdition -eq "Core") {
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WinFormsPath) -Force
                    "Installed 'Microsoft.Web.WebView2.WinForms.dll' version {0}" -f (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion | Write-Host
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2CorePath) -Force
                    "Installed 'Microsoft.Web.WebView2.Core.dll' version {0}" -f (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion | Write-Host
                }
                else {
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WinFormsPath) -Force
                    "Installed 'Microsoft.Web.WebView2.WinForms.dll' version {0}" -f (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion | Write-Host
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2CorePath) -Force
                    "Installed 'Microsoft.Web.WebView2.Core.dll' version {0}" -f (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion | Write-Host
                }

                Get-ChildItem -Path $TempZipPath -Filter "WebView2Loader.dll" -Recurse | Where-Object { $_.Directory -like ("*runtimes\{0}*" -f $RuntimeFolder) } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2LoaderPath) -Force
                "Installed 'WebView2Loader.dll' version {0}" -f (Get-Item $Script:WebView2LoaderPath).VersionInfo.ProductVersion | Write-Host

                Remove-Item -Path $TempZipPath -Force -Recurse
                "WebView2 package installed successfully" | Write-Verbose
            }
            catch {
                $RuntimeFolder = "win-x64"
                if ($Env:PROCESSOR_ARCHITECTURE -eq "x86") {
                    $RuntimeFolder = "win-x86"
                }
                "Failed to download the binaries. Try downloading the WebView2 NuGet package manually from '{0}', rename the extension to .zip and extract the files in a temporary location. Copy the following files {1} from the extracted NuGet package to {2} Error:`r`n {3}" -f $PackageUrl, $("'{0}', '{1}' and '{2}'" -f ( $NuGetDirectoryPath, (Split-Path $Script:WebView2CorePath -Leaf) -join "\"), ($NuGetDirectoryPath, (Split-Path $Script:WebView2WinFormsPath -Leaf) -join "\"), ( ".\runtimes", $RuntimeFolder , (Split-Path $Script:WebView2LoaderPath -Leaf) -join "\")), ([System.IO.Path]::Combine($Script:BinPath, $RuntimeFolder)), $_.Exception | Write-Error -ErrorAction Stop
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