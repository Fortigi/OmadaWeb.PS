function Start-WebView2Headless {
    <#
    .SYNOPSIS
    Starts a headless WebView2 browser instance for authentication.

    .DESCRIPTION
    This function creates a headless WebView2 browser instance using a robust approach
    that handles async operations properly in PowerShell without hanging.

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
            $Script:WebViewEnvironment = $createEnvironmentTask.GetAwaiter().GetResult()
            "WebView2 environment created successfully" | Write-Verbose
        }
        catch {
            "Failed to create WebView2 environment: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Create controller using a more robust approach
        try {
            # Load Windows Forms properly for PowerShell Core
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            }

            # Create a proper form that can be shown/hidden quickly
            $Script:WebViewForm = New-Object System.Windows.Forms.Form
            $Script:WebViewForm.Text = "OmadaWeb.PS WebView2"
            $Script:WebViewForm.Size = New-Object System.Drawing.Size(1024, 768)
            $Script:WebViewForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
            $Script:WebViewForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
            $Script:WebViewForm.ShowInTaskbar = $false
            $Script:WebViewForm.Visible = $false

            # Create the form handle
            $formHandle = $Script:WebViewForm.Handle

            # Use synchronous approach with timeout for PowerShell compatibility
            "Creating WebView2 controller (this may take a moment)..." | Write-Verbose

            # Create controller with proper timeout handling
            $createControllerTask = $Script:WebViewEnvironment.CreateCoreWebView2ControllerAsync($formHandle)

            # PowerShell-friendly synchronous wait with timeout
            $timeoutMs = 30000  # 30 seconds
            $completed = $createControllerTask.Wait($timeoutMs)

            if (-not $completed) {
                throw "WebView2 controller creation timed out after $($timeoutMs/1000) seconds"
            }

            $Script:WebViewController = $createControllerTask.Result
            $Script:WebViewCore = $Script:WebViewController.CoreWebView2

            # Configure the controller for headless operation
            $Script:WebViewController.IsVisible = $false
            $Script:WebViewController.Bounds = New-Object System.Drawing.Rectangle(0, 0, 1024, 768)

            "WebView2 controller created successfully (headless mode)" | Write-Verbose
        }
        catch {
            "Failed to create WebView2 controller: {0}" -f $_.Exception.Message | Write-Error
            if ($Script:WebViewForm) {
                $Script:WebViewForm.Dispose()
                $Script:WebViewForm = $null
            }
            throw
        }

        # Configure WebView2 settings
        try {
            $settings = $Script:WebViewCore.Settings
            $settings.IsGeneralAutofillEnabled = $true
            $settings.IsPasswordAutosaveEnabled = $true
            $settings.AreDefaultScriptDialogsEnabled = $true
            $settings.AreDevToolsEnabled = $false
            $settings.AreHostObjectsAllowed = $false
            $settings.IsScriptEnabled = $true
            $settings.IsWebMessageEnabled = $false

            # Set custom user agent
            $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
            $settings.UserAgent = $userAgent

            "WebView2 settings configured successfully" | Write-Verbose
        }
        catch {
            "Failed to configure WebView2 settings: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Store flags
        $Script:WebViewHeadlessMode = $true
        $Script:WebViewControl = $null  # Not using WinForms control in headless mode

        "WebView2 initialized successfully (headless mode)" | Write-Verbose
        return $Script:WebViewCore
    }
    catch {
        "Failed to start WebView2 (headless mode): {0}" -f $_.Exception.Message | Write-Error
        Close-WebView2
        throw
    }
}