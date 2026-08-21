function Install-WebView2 {
    [CmdletBinding()]
    param(
        [switch]$IncludeWpf,
        [switch]$Force
    )

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        if ($Script:WebView2Bundled) {
            # The assemblies ship with the module, fetched from the pinned URL and verified against
            # the pinned SHA-256 at build time. There is nothing to download, nothing to update
            # against - the pinned version is the bundled version, so Test-WebView2RuntimeVersion
            # would only compare the bundle against itself - and nowhere to write: the module may be
            # installed under Program Files, and the bundle is treated as read-only either way.
            # -Force has nothing to force here for the same reason.
            if ($IncludeWpf.IsPresent) {
                # Deliberately not bundled: nothing in the module hosts WebView2 in WPF. Falling
                # through to the download path is not an option, because the script-scope paths point
                # into the package and installing there would write into the module directory.
                "'Microsoft.Web.WebView2.Wpf.dll' is not part of the WebView2 assemblies bundled with the module. Import the module with -UpdateDependencies to install the full package into '{0}' instead." -f $Script:BinPath | Write-Error
                return $false
            }

            "Using the bundled 'Microsoft.Web.WebView2' assemblies from '{0}'" -f (Split-Path $Script:WebView2CorePath) | Write-Verbose
            return $true
        }

        $UpdateNeeded = Test-WebView2RuntimeVersion -IncludeWpf:$IncludeWpf.IsPresent

        if (
            (
                -not (Test-Path $Script:WebView2WinFormsPath -PathType Leaf) -or
                -not (Test-Path $Script:WebView2CorePath -PathType Leaf) -or
                -not (Test-Path $Script:WebView2LoaderPath -PathType Leaf) -or
                (
                    $IncludeWpf.IsPresent -and
                    -not (Test-Path $Script:WebView2WpfPath -PathType Leaf)
                )
            ) -or $Force -or $UpdateNeeded
        ) {
            "'Microsoft.Web.WebView2' needs to be downloaded. Downloading from NuGet" | Write-Host

            # Version and URL both come from the lock file, so the bytes can be hash-verified before
            # any of these assemblies is loaded into the session.
            $Artifact = Get-LockedArtifact -Id "Microsoft.Web.WebView2"
            $PackageUrl = $Artifact.Url
            "Retrieving '{0}' version {1}" -f $Artifact.PackageId, $Artifact.Version | Write-Host

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
                $TempFile = Invoke-DownloadFile -ArtifactId "Microsoft.Web.WebView2"

                $TempZipPath = Expand-DownloadFile -FilePath $TempFile

                if ($PSVersionTable.PSEdition -eq "Core") {
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WinFormsPath) -Force
                    "Installed 'Microsoft.Web.WebView2.WinForms.dll' version {0}" -f (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion | Write-Host
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2CorePath) -Force
                    "Installed 'Microsoft.Web.WebView2.Core.dll' version {0}" -f (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion | Write-Host
                    if ($IncludeWpf.IsPresent) {
                        Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Wpf.dll" -Recurse | Where-Object { $_.Directory.Name -eq $DirectoryName } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WpfPath) -Force
                        "Installed 'Microsoft.Web.WebView2.Wpf.dll' version {0}" -f (Get-Item $Script:WebView2WpfPath).VersionInfo.ProductVersion | Write-Host
                    }
                }
                else {
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WinFormsPath) -Force
                    "Installed 'Microsoft.Web.WebView2.WinForms.dll' version {0}" -f (Get-Item $Script:WebView2WinFormsPath).VersionInfo.ProductVersion | Write-Host
                    Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2CorePath) -Force
                    "Installed 'Microsoft.Web.WebView2.Core.dll' version {0}" -f (Get-Item $Script:WebView2CorePath).VersionInfo.ProductVersion | Write-Host
                    if ($IncludeWpf.IsPresent) {
                        Get-ChildItem -Path $TempZipPath -Filter "Microsoft.Web.WebView2.Wpf.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination (Split-Path $Script:WebView2WpfPath) -Force
                        "Installed 'Microsoft.Web.WebView2.Wpf.dll' version {0}" -f (Get-Item $Script:WebView2WpfPath).VersionInfo.ProductVersion | Write-Host
                    }
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

                if ($IncludeWpf.IsPresent) {
                    $DllFileListString = "'{0}', '{1}', '{2}' and '{3}'" -f ( $NuGetDirectoryPath, (Split-Path $Script:WebView2CorePath -Leaf) -join "\"), ($NuGetDirectoryPath, (Split-Path $Script:WebView2WinFormsPath -Leaf) -join "\"), ($NuGetDirectoryPath, (Split-Path $Script:WebView2WpfPath -Leaf) -join "\"), ( ".\runtimes", $RuntimeFolder , (Split-Path $Script:WebView2LoaderPath -Leaf) -join "\")
                }
                else {
                    $DllFileListString = "'{0}', '{1}' and '{2}'" -f ( $NuGetDirectoryPath, (Split-Path $Script:WebView2CorePath -Leaf) -join "\"), ($NuGetDirectoryPath, (Split-Path $Script:WebView2WinFormsPath -Leaf) -join "\"), ( ".\runtimes", $RuntimeFolder , (Split-Path $Script:WebView2LoaderPath -Leaf) -join "\")
                }
                "Failed to download the binaries. Try downloading the WebView2 NuGet package manually from '{0}', rename the extension to .zip and extract the files in a temporary location. Copy the following files {1} from the extracted NuGet package to {2} Error:`r`n {3}" -f $PackageUrl, $DllFileListString, ([System.IO.Path]::Combine($Script:BinPath, $RuntimeFolder)), $_.Exception | Write-Error -ErrorAction Stop
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
