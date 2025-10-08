function Start-WebView2 {
    <#
    .SYNOPSIS
    Starts a WebView2 browser instance for authentication.

    .DESCRIPTION
    This function creates and configures a WebView2 browser instance as an alternative to Selenium WebDriver.
    It supports profile selection and InPrivate mode.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .EXAMPLE
    Start-WebView2 -EdgeProfile "Profile 1"

    .EXAMPLE
    Start-WebView2 -InPrivate
    #>

    [CmdletBinding()]
    param(
        [string]$EdgeProfile,
        [switch]$InPrivate
    )

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        # Ensure WebView2 is installed
        if (-not (Install-WebView2)) {
            throw "WebView2 installation failed"
        }

        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        try {
            Add-Type -Path $Script:WebView2WinFormsPath
            Add-Type -Path $Script:WebView2CorePath
        }
        catch {
            "Failed to load WebView2 assemblies: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Create the form
        $Script:WebViewForm = New-Object System.Windows.Forms.Form
        $Script:WebViewForm.Text = "Omada Authentication"
        $Script:WebViewForm.Size = New-Object System.Drawing.Size(564, 973)
        $Script:WebViewForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $Script:WebViewForm.MinimizeBox = $false
        $Script:WebViewForm.MaximizeBox = $false
        $Script:WebViewForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle

        # Create WebView2 control
        $Script:WebViewControl = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $Script:WebViewControl.Dock = [System.Windows.Forms.DockStyle]::Fill

        # Configure WebView2 environment
        $userDataFolder = Join-Path $env:LOCALAPPDATA "OmadaWeb.PS\WebView2"

        if ($InPrivate) {
            # For InPrivate mode, use a temporary folder that gets cleaned up
            $userDataFolder = Join-Path $env:TEMP "OmadaWeb.PS\WebView2\InPrivate\$(Get-Random)"
            "Using InPrivate mode with temporary profile: {0}" -f $userDataFolder | Write-Verbose
        }
        elseif (![string]::IsNullOrWhiteSpace($EdgeProfile) -and $EdgeProfile -ne "Default") {
            # Use specific profile folder
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
        $environmentOptions = New-Object Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions
        $environmentOptions.AdditionalBrowserArguments = "--disable-web-security --disable-features=VizDisplayCompositor --lang=en"

        if ($InPrivate) {
            $environmentOptions.AdditionalBrowserArguments += " --inprivate"
        }

        # Initialize WebView2 environment
        $Script:WebViewEnvironment = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder, $environmentOptions).GetAwaiter().GetResult()

        # Initialize WebView2 control
        $Script:WebViewControl.EnsureCoreWebView2Async($Script:WebViewEnvironment).GetAwaiter().GetResult()

        # Add the WebView2 control to the form
        $Script:WebViewForm.Controls.Add($Script:WebViewControl)

        # Configure additional WebView2 settings
        $Script:WebViewControl.CoreWebView2.Settings.IsGeneralAutofillEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.IsPasswordAutosaveEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.AreDefaultScriptDialogsEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.AreDevToolsEnabled = $false
        $Script:WebViewControl.CoreWebView2.Settings.AreHostObjectsAllowed = $false
        $Script:WebViewControl.CoreWebView2.Settings.IsScriptEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.IsWebMessageEnabled = $false

        # Set custom user agent to match Edge
        $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
        $Script:WebViewControl.CoreWebView2.Settings.UserAgent = $userAgent

        "WebView2 control initialized successfully" | Write-Verbose
        return $Script:WebViewControl
    }
    catch {
        "Failed to start WebView2: {0}" -f $_.Exception.Message | Write-Error
        Close-WebView2
        throw
    }
}