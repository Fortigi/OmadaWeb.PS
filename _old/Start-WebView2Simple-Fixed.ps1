function Start-WebView2Simple {
    <#
    .SYNOPSIS
    Starts a simple WebView2 browser instance that works reliably in PowerShell.

    .DESCRIPTION
    This function creates a WebView2 browser using the WinForms control approach
    which is more compatible with PowerShell's threading model.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .PARAMETER Visible
    Whether to show the browser window (default: false for headless operation).

    .EXAMPLE
    Start-WebView2Simple -Visible:$false
    #>

    [CmdletBinding()]
    param(
        [string]$EdgeProfile,
        [switch]$InPrivate,
        [bool]$Visible = $false
    )

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        # Initialize WebView2 assemblies
        if (-not (Initialize-WebView2Assemblies)) {
            throw "Failed to initialize WebView2 assemblies"
        }

        # Configure user data folder
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

        if (-not (Test-Path $userDataFolder)) {
            New-Item -Path $userDataFolder -ItemType Directory -Force | Out-Null
        }

        # Create form and WebView2 control using WinForms approach
        try {
            # Ensure Windows Forms is loaded
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue

            # Create the main form
            $Script:WebViewForm = New-Object System.Windows.Forms.Form
            $Script:WebViewForm.Text = "OmadaWeb.PS WebView2"
            $Script:WebViewForm.Size = New-Object System.Drawing.Size(1024, 768)
            $Script:WebViewForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

            if (-not $Visible) {
                $Script:WebViewForm.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
                $Script:WebViewForm.ShowInTaskbar = $false
                $Script:WebViewForm.Visible = $false
            }

            # Create WebView2 control using WinForms wrapper
            $Script:WebViewControl = New-Object Microsoft.Web.WebView2.WinForms.WebView2
            $Script:WebViewControl.Dock = [System.Windows.Forms.DockStyle]::Fill

            # Add control to form
            $Script:WebViewForm.Controls.Add($Script:WebViewControl)

            "WebView2 form and control created" | Write-Verbose

            # Set environment options before initialization
            $environmentOptions = New-Object Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions

            # Configure the WebView2 control's environment
            $Script:WebViewControl.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
            $Script:WebViewControl.CreationProperties.UserDataFolder = $userDataFolder
            $Script:WebViewControl.CreationProperties.EnvironmentOptions = $environmentOptions

            "WebView2 environment configuration set" | Write-Verbose

            # Initialize WebView2 - this is synchronous in WinForms approach
            "Initializing WebView2 control..." | Write-Verbose

            # Create a manual reset event for synchronization
            $initEvent = New-Object System.Threading.ManualResetEventSlim($false)
            $initSuccess = $false
            $initError = $null

            # Set up event handler for initialization completion
            $navigationCompletedHandler = {
                param($eventSender, $eventArgs)
                try {
                    $Script:WebViewCore = $Script:WebViewControl.CoreWebView2
                    $script:initSuccess = $true
                    "WebView2 core ready" | Write-Verbose
                } catch {
                    $script:initError = $_.Exception
                } finally {
                    $initEvent.Set()
                }
            }

            # Register event handler
            $Script:WebViewControl.add_CoreWebView2InitializationCompleted($navigationCompletedHandler)

            # Start initialization
            $null = $Script:WebViewControl.EnsureCoreWebView2Async($null)

            # Wait for initialization with timeout
            if ($initEvent.Wait(15000)) { # 15 seconds timeout
                if ($script:initSuccess -and $Script:WebViewCore) {
                    "WebView2 initialization successful" | Write-Verbose
                } else {
                    throw "WebView2 initialization failed: $script:initError"
                }
            } else {
                throw "WebView2 initialization timed out"
            }

            # Configure settings
            $settings = $Script:WebViewCore.Settings
            $settings.IsGeneralAutofillEnabled = $true
            $settings.IsPasswordAutosaveEnabled = $true
            $settings.AreDefaultScriptDialogsEnabled = $true
            $settings.AreDevToolsEnabled = $false
            $settings.AreHostObjectsAllowed = $false
            $settings.IsScriptEnabled = $true
            $settings.IsWebMessageEnabled = $false

            # Set user agent
            $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
            $settings.UserAgent = $userAgent

            "WebView2 settings configured" | Write-Verbose

            # Store references
            $Script:WebViewHeadlessMode = (-not $Visible)
            $Script:WebViewController = $null  # Using WinForms control instead
            $Script:WebViewEnvironment = $null  # Managed by WinForms control

            "WebView2 started successfully (WinForms mode, Visible: $Visible)" | Write-Verbose
            return $Script:WebViewCore

        } catch {
            "Failed to create WebView2 control: {0}" -f $_.Exception.Message | Write-Error
            if ($Script:WebViewForm) {
                $Script:WebViewForm.Dispose()
                $Script:WebViewForm = $null
            }
            if ($Script:WebViewControl) {
                $Script:WebViewControl.Dispose()
                $Script:WebViewControl = $null
            }
            throw
        }

    } catch {
        "Failed to start WebView2 (simple mode): {0}" -f $_.Exception.Message | Write-Error
        Close-WebView2
        throw
    }
}