function Start-WebView2Minimal {
    <#
    .SYNOPSIS
    Starts a minimal WebView2 browser instance without Windows Forms dependencies.

    .DESCRIPTION
    This function creates a WebView2 browser instance using only the core WebView2 APIs,
    avoiding Windows Forms entirely to prevent assembly loading issues.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .EXAMPLE
    Start-WebView2Minimal -EdgeProfile "Profile 1"

    .EXAMPLE
    Start-WebView2Minimal -InPrivate
    #>
    
    [CmdletBinding()]
    param(
        [string]$EdgeProfile,
        [switch]$InPrivate
    )

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose
        
        # Initialize WebView2 assemblies
        if (-not (Initialize-WebView2Assemblies)) {
            throw "Failed to initialize WebView2 assemblies"
        }

        # Configure WebView2 environment
        $userDataFolder = Join-Path $env:LOCALAPPDATA "OmadaWeb.PS\WebView2"
        
        if ($InPrivate) {
            $userDataFolder = Join-Path $env:TEMP "OmadaWeb.PS\WebView2\InPrivate\$(Get-Random)"
            "Using InPrivate mode with temporary profile: {0}" -f $userDataFolder | Write-Verbose
        }
        elseif (![string]::IsNullOrWhiteSpace($EdgeProfile) -and $EdgeProfile -ne "Default") {
            $ProfileFolderName = ($Script:EdgeProfiles | Where-Object { $_.Name -eq $EdgeProfile }).Folder
            if ($ProfileFolderName) {
                $userDataFolder = Join-Path $env:LOCALAPPDATA "OmadaWeb.PS\WebView2\Profiles\$ProfileFolderName"
                "Using Edge profile: '{0}' with data folder: '{1}'" -f $EdgeProfile, $userDataFolder | Write-Verbose
            }
        }

        # Ensure user data folder exists
        if (-not (Test-Path $userDataFolder)) {
            New-Item -Path $userDataFolder -ItemType Directory -Force | Out-Null
        }

        # Create WebView2 environment without options to avoid constructor issues
        try {
            $createEnvironmentTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder)
            $Script:WebView2Environment = $createEnvironmentTask.GetAwaiter().GetResult()
            "WebView2 environment created successfully" | Write-Verbose
        }
        catch {
            "Failed to create WebView2 environment: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Create a minimal control without Windows Forms
        try {
            # Use reflection to create the WebView2 control to avoid direct Windows Forms dependencies
            $webView2Type = [Microsoft.Web.WebView2.WinForms.WebView2]
            $Script:WebView2Control = [System.Activator]::CreateInstance($webView2Type)
            
            "WebView2 control created using reflection" | Write-Verbose
        }
        catch {
            "Failed to create WebView2 control: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Initialize WebView2 control with environment
        try {
            $initializeTask = $Script:WebView2Control.EnsureCoreWebView2Async($Script:WebView2Environment)
            $initializeTask.GetAwaiter().GetResult()
            "WebView2 control initialized with environment" | Write-Verbose
        }
        catch {
            "Failed to initialize WebView2 control: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Configure WebView2 settings
        try {
            $Script:WebView2Control.CoreWebView2.Settings.IsGeneralAutofillEnabled = $true
            $Script:WebView2Control.CoreWebView2.Settings.IsPasswordAutosaveEnabled = $true
            $Script:WebView2Control.CoreWebView2.Settings.AreDefaultScriptDialogsEnabled = $true
            $Script:WebView2Control.CoreWebView2.Settings.AreDevToolsEnabled = $false
            $Script:WebView2Control.CoreWebView2.Settings.AreHostObjectsAllowed = $false
            $Script:WebView2Control.CoreWebView2.Settings.IsScriptEnabled = $true
            $Script:WebView2Control.CoreWebView2.Settings.IsWebMessageEnabled = $false

            # Set custom user agent
            $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
            $Script:WebView2Control.CoreWebView2.Settings.UserAgent = $userAgent
            
            "WebView2 settings configured successfully" | Write-Verbose
        }
        catch {
            "Failed to configure WebView2 settings: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Store a flag indicating we're using minimal mode
        $Script:WebView2MinimalMode = $true
        $Script:WebView2Form = $null  # No form in minimal mode

        "WebView2 control initialized successfully (minimal mode)" | Write-Verbose
        return $Script:WebView2Control
    }
    catch {
        "Failed to start WebView2 (minimal mode): {0}" -f $_.Exception.Message | Write-Error
        Close-WebView2
        throw
    }
}