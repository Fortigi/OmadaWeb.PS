function Initialize-WebView2Assemblies {
    <#
    .SYNOPSIS
    Initializes and loads WebView2 assemblies with proper dependency resolution.

    .DESCRIPTION
    This function handles the complex assembly loading requirements for WebView2,
    including proper handling of different PowerShell versions and .NET frameworks.

    .EXAMPLE
    Initialize-WebView2Assemblies
    #>

    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        # Step 1: Load base Windows Forms assemblies
        "Loading Windows Forms assemblies..." | Write-Verbose

        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # PowerShell Core - use reflection to load assemblies
            try {
                # Try to load from GAC first
                $null = [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
                $null = [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
                "Base assemblies loaded from GAC" | Write-Verbose
            }
            catch {
                "Could not load from GAC, trying alternative approach: {0}" -f $_.Exception.Message | Write-Verbose

                # Alternative: Load specific assemblies if available
                try {
                    Add-Type -AssemblyName System.Windows.Forms
                    Add-Type -AssemblyName System.Drawing
                }
                catch {
                    "Failed to load Windows Forms assemblies: {0}" -f $_.Exception.Message | Write-Warning
                    # Continue - WebView2 might still work
                }
            }
        }
        else {
            # Windows PowerShell - standard approach
            Add-Type -AssemblyName System.Windows.Forms
            Add-Type -AssemblyName System.Drawing
            "Base assemblies loaded successfully (Windows PowerShell)" | Write-Verbose
        }

        # Step 2: Ensure WebView2 is installed
        if (-not (Install-WebView2)) {
            throw "WebView2 installation failed"
        }

        # Step 3: Load WebView2 assemblies
        "Loading WebView2 assemblies..." | Write-Verbose
        "WebView2 WinForms Path: {0}" -f $Script:WebView2WinFormsPath | Write-Verbose
        "WebView2 Core Path: {0}" -f $Script:WebView2CorePath | Write-Verbose

        if (-not (Test-Path $Script:WebView2WinFormsPath)) {
            throw "WebView2 WinForms assembly not found at: $Script:WebView2WinFormsPath"
        }

        if (-not (Test-Path $Script:WebView2CorePath)) {
            throw "WebView2 Core assembly not found at: $Script:WebView2CorePath"
        }

        # Load WebView2 Core first (dependency)
        try {
            $coreAssembly = [System.Reflection.Assembly]::LoadFrom($Script:WebView2CorePath)
            "WebView2 Core assembly loaded: {0}" -f $coreAssembly.FullName | Write-Verbose
        }
        catch {
            if ($_.Exception.Message -like '*Assembly with same name is already loaded*') {
                # Ignore
            }
            else {
                "Failed to load WebView2 Core assembly: {0}" -f $_.Exception.Message | Write-Error
                throw
            }
        }

        # Load WebView2 WinForms
        try {
            $Script:WinFormsAssembly = [System.Reflection.Assembly]::LoadFrom($Script:WebView2WinFormsPath)
            "WebView2 WinForms assembly loaded: {0}" -f $Script:WinFormsAssembly.FullName | Write-Verbose
        }
        catch {
            if ($_.Exception.Message -like '*Assembly with same name is already loaded*') {
                # Ignore
            }
            else {
                "Failed to load WebView2 WinForms assembly: {0}" -f $_.Exception.Message | Write-Error
                throw
            }
        }

        # Step 4: Verify required types are available
        try {
            $null = [Microsoft.Web.WebView2.WinForms.WebView2]
            $null = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]
            $null = [Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions]

            "WebView2 types verified successfully" | Write-Verbose
            return $true
        }
        catch {
            "WebView2 types not available after loading: {0}" -f $_.Exception.Message | Write-Error
            throw
        }
    }
    catch {
        "Failed to initialize WebView2 assemblies: {0}" -f $_.Exception.Message | Write-Error
        return $false
    }
}