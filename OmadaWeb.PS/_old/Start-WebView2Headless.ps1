function Start-WebView2Headless {
    <#
    .SYNOPSIS
    Starts a headless WebView2 browser instance for authentication.

    .DESCRIPTION
    This function creates a headless WebView2 browser instance that runs in the background
    without showing a UI. This is useful for automated authentication scenarios.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .EXAMPLE
    Start-WebView2Headless -EdgeProfile "Profile 1"

    .EXAMPLE
    Start-WebView2Headless -InPrivate
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

        # Create WebView2 environment
        try {
            $createEnvironmentTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder)
            $Script:WebView2Environment = $createEnvironmentTask.GetAwaiter().GetResult()
            "WebView2 environment created successfully" | Write-Verbose
        }
        catch {
            "Failed to create WebView2 environment: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Create a CoreWebView2Controller directly (headless)
        try {
            # Create a dummy window handle for the controller
            $dummyHwnd = [System.IntPtr]::Zero

            # Create controller
            $createControllerTask = $Script:WebView2Environment.CreateAsync($dummyHwnd)
            $Script:WebView2Controller = $createControllerTask.GetAwaiter().GetResult()

            # Get the CoreWebView2 from the controller
            $Script:WebView2Core = $Script:WebView2Controller.CoreWebView2

            "WebView2 controller created successfully (headless)" | Write-Verbose
        }
        catch {
            "Failed to create WebView2 controller: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Configure WebView2 settings
        try {
            $Script:WebView2Core.Settings.IsGeneralAutofillEnabled = $true
            $Script:WebView2Core.Settings.IsPasswordAutosaveEnabled = $true
            $Script:WebView2Core.Settings.AreDefaultScriptDialogsEnabled = $true
            $Script:WebView2Core.Settings.AreDevToolsEnabled = $false
            $Script:WebView2Core.Settings.AreHostObjectsAllowed = $false
            $Script:WebView2Core.Settings.IsScriptEnabled = $true
            $Script:WebView2Core.Settings.IsWebMessageEnabled = $false

            # Set custom user agent
            $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
            $Script:WebView2Core.Settings.UserAgent = $userAgent

            "WebView2 settings configured successfully" | Write-Verbose
        }
        catch {
            "Failed to configure WebView2 settings: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Store flags
        $Script:WebView2HeadlessMode = $true
        $Script:WebView2Form = $null
        $Script:WebView2Control = $null

        "WebView2 initialized successfully (headless mode)" | Write-Verbose
        return $Script:WebView2Core
    }
    catch {
        "Failed to start WebView2 (headless mode): {0}" -f $_.Exception.Message | Write-Error
        Close-WebView2
        throw
    }
}