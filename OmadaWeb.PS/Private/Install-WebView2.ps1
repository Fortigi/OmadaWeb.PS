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
        
        # Check if WebView2 runtime is installed
        $WebView2Registry = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -ErrorAction SilentlyContinue
        if (-not $WebView2Registry) {
            $WebView2Registry = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" -ErrorAction SilentlyContinue
        }

        if (-not $WebView2Registry) {
            "WebView2 runtime not found. Please install Microsoft Edge WebView2 Runtime from https://developer.microsoft.com/en-us/microsoft-edge/webview2/" | Write-Warning
            return $false
        }

        "WebView2 runtime version {0} found" -f $WebView2Registry.pv | Write-Verbose

        # Install WebView2 NuGet package for .NET assemblies
        $WebView2PackagePath = Join-Path -Path $Script:BinPath -ChildPath "Microsoft.Web.WebView2"
        
        if (-not (Test-Path $WebView2PackagePath)) {
            "Installing WebView2 NuGet package..." | Write-Verbose
            
            # Download and extract WebView2 NuGet package
            $PackageUrl = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2"
            $PackageFile = Join-Path -Path $Script:BinPath -ChildPath "Microsoft.Web.WebView2.nupkg"
            
            try {
                Invoke-WebRequest -Uri $PackageUrl -OutFile $PackageFile -UseBasicParsing
                
                # Extract the package
                Expand-Archive -Path $PackageFile -DestinationPath $WebView2PackagePath -Force
                Remove-Item -Path $PackageFile -Force
                
                "WebView2 package installed successfully" | Write-Verbose
            }
            catch {
                "Failed to download WebView2 package: {0}" -f $_.Exception.Message | Write-Error
                return $false
            }
        }

        # Set WebView2 assembly paths
        $Script:WebView2WinFormsPath = Get-ChildItem -Path $WebView2PackagePath -Filter "Microsoft.Web.WebView2.WinForms.dll" -Recurse | 
            Where-Object { $_.Directory.Name -eq "net462" -or $_.Directory.Name -eq "netcoreapp3.1" } | 
            Select-Object -First 1 -ExpandProperty FullName

        $Script:WebView2CorePath = Get-ChildItem -Path $WebView2PackagePath -Filter "Microsoft.Web.WebView2.Core.dll" -Recurse | 
            Where-Object { $_.Directory.Name -eq "net462" -or $_.Directory.Name -eq "netcoreapp3.1" } | 
            Select-Object -First 1 -ExpandProperty FullName

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