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

        $Webview2WinformsDll = "Microsoft.Web.WebView2.WinForms.dll"
        $Webview2CoreDll = "Microsoft.Web.WebView2.Core.dll"

        $WebView2PackagePath = Join-Path -Path $Script:BinPath -ChildPath "Microsoft.Web.WebView2"

        if (-not (Test-Path $WebView2PackagePath -PathType Container) -or -not (Get-ChildItem -Path $WebView2PackagePath -Filter $Webview2WinformsDll -Recurse -ErrorAction SilentlyContinue) -or -not (Get-ChildItem -Path $WebView2PackagePath -Filter $Webview2CoreDll -Recurse -ErrorAction SilentlyContinue)) {
            "Installing WebView2 NuGet package..." | Write-Verbose

            $WebView2PackagePath = (New-Item -Path $WebView2PackagePath -ItemType Directory -Force).FullName

            $PackageUrl = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2"
            $PackageBasePath = Join-Path -Path $Env:Temp -ChildPath ([system.IO.Path]::GetRandomFileName())
            New-Item -Path $PackageBasePath -ItemType Directory -Force | Out-Null
            $PackageFile = Join-Path -Path $PackageBasePath -ChildPath "Microsoft.Web.WebView2.nupkg"

            try {
                Invoke-WebRequest -Uri $PackageUrl -OutFile $PackageFile -UseBasicParsing

                Expand-Archive -Path $PackageFile -DestinationPath $PackageBasePath -Force

                if ($PSVersionTable.PSEdition -eq "Core") {
                    Get-ChildItem -Path $PackageBasePath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq "netcoreapp3.0" } | Select-Object -First 1 | Copy-Item -Destination $WebView2PackagePath -Force
                    Get-ChildItem -Path $PackageBasePath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq "netcoreapp3.0" } | Select-Object -First 1 | Copy-Item -Destination $WebView2PackagePath -Force
                }
                else {
                    Get-ChildItem -Path $PackageBasePath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination $WebView2PackagePath -Force
                    Get-ChildItem -Path $PackageBasePath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Where-Object { $_.Directory.Name -eq "net462" } | Select-Object -First 1 | Copy-Item -Destination $WebView2PackagePath -Force
                }
                Remove-Item -Path $PackageBasePath -Force -Recurse
                "WebView2 package installed successfully" | Write-Verbose
            }
            catch {
                "Failed to download WebView2 package: {0}" -f $_.Exception.Message | Write-Error
                return $false
            }
        }

        $Script:WebView2WinFormsPath = Get-ChildItem -Path  $WebView2PackagePath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | Select-Object -First 1
        $Script:WebView2CorePath = Get-ChildItem -Path  $WebView2PackagePath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | Select-Object -First 1

        if (-not $Script:WebView2WinFormsPath -or -not $Script:WebView2CorePath) {
            "WebView2 assemblies not found in package" | Write-Error
            return $false
        }

        "WebView2 WinForms assembly: {0}" -f $Script:WebView2WinFormsPath | Write-Verbose
        "WebView2 Core assembly: {0}" -f $Script:WebView2CorePath | Write-Verbose

        return $true
    }
    catch {
        "Failed to install WebView2: {0}" -f $_.Exception.Message | Write-Error
        return $false
    }
}