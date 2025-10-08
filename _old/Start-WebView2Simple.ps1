function Start-WebView2Simple {
    <#
    .SYNOPSIS
    Starts a simplified WebView2 browser instance using minimal Windows Forms dependencies.

    .DESCRIPTION
    This function creates a WebView2 browser instance with minimal Windows Forms usage
    to avoid assembly loading issues on different PowerShell versions.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .EXAMPLE
    Start-WebView2Simple -EdgeProfile "Profile 1"

    .EXAMPLE
    Start-WebView2Simple -InPrivate
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

        # Configure WebView2 environment options
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

        # Create WebView2 environment options
        $environmentOptions = New-Object Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions
        $environmentOptions.AdditionalBrowserArguments = "--disable-web-security --disable-features=VizDisplayCompositor --lang=en"

        if ($InPrivate) {
            $environmentOptions.AdditionalBrowserArguments += " --inprivate"
        }

        # Create WebView2 environment
        $createEnvironmentTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder, $environmentOptions)
        $Script:WebViewEnvironment = $createEnvironmentTask.GetAwaiter().GetResult()

        # Create a simple form using basic properties only
        $Script:WebViewForm = New-Object System.Windows.Forms.Form
        $Script:WebViewForm.Text = "Omada Authentication"
        $Script:WebViewForm.Width = 564
        $Script:WebViewForm.Height = 973
        $Script:WebViewForm.MinimizeBox = $false
        $Script:WebViewForm.MaximizeBox = $false

        # Center the form manually
        $screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Width
        $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
        $Script:WebViewForm.Left = [System.Math]::Max(0, ($screenWidth - $Script:WebViewForm.Width) / 2)
        $Script:WebViewForm.Top = [System.Math]::Max(0, ($screenHeight - $Script:WebViewForm.Height) / 2)

        # Create WebView2 control
        $Script:WebViewControl = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $Script:WebViewControl.Width = $Script:WebViewForm.ClientSize.Width
        $Script:WebViewControl.Height = $Script:WebViewForm.ClientSize.Height
        $Script:WebViewControl.Left = 0
        $Script:WebViewControl.Top = 0

        # Set anchor styles manually instead of using Dock
        # This avoids the DockStyle enum issue
        try {
            $anchorProperty = $Script:WebViewControl.GetType().GetProperty("Anchor")
            if ($anchorProperty) {
                $anchorStyleType = [System.Type]::GetType("System.Windows.Forms.AnchorStyles")
                $anchorValue = [System.Enum]::Parse($anchorStyleType, "Top, Bottom, Left, Right")
                $anchorProperty.SetValue($Script:WebViewControl, $anchorValue)
                "Set Anchor property for WebView2 control" | Write-Verbose
            }
        }
        catch {
            "Could not set Anchor property, using manual sizing" | Write-Verbose
        }

        # Initialize WebView2 control with environment
        $initializeTask = $Script:WebViewControl.EnsureCoreWebView2Async($Script:WebViewEnvironment)
        $initializeTask.GetAwaiter().GetResult()

        # Configure WebView2 settings
        $Script:WebViewControl.CoreWebView2.Settings.IsGeneralAutofillEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.IsPasswordAutosaveEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.AreDefaultScriptDialogsEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.AreDevToolsEnabled = $false
        $Script:WebViewControl.CoreWebView2.Settings.AreHostObjectsAllowed = $false
        $Script:WebViewControl.CoreWebView2.Settings.IsScriptEnabled = $true
        $Script:WebViewControl.CoreWebView2.Settings.IsWebMessageEnabled = $false

        # Set custom user agent
        $userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"
        $Script:WebViewControl.CoreWebView2.Settings.UserAgent = $userAgent

        # Add resize event handler to keep WebView2 control sized properly
        $Script:WebViewForm.Add_Resize({
            if ($Script:WebViewControl) {
                $Script:WebViewControl.Width = $Script:WebViewForm.ClientSize.Width
                $Script:WebViewControl.Height = $Script:WebViewForm.ClientSize.Height
            }
        })

        # Add the WebView2 control to the form
        $Script:WebViewForm.Controls.Add($Script:WebViewControl)

        "WebView2 control initialized successfully (simple mode)" | Write-Verbose
        return $Script:WebViewControl
    }
    catch {
        "Failed to start WebView2 (simple mode): {0}" -f $_.Exception.Message | Write-Error
        Close-WebView2
        throw
    }
}