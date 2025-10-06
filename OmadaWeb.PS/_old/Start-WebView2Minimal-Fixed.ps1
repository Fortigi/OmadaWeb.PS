function Start-WebView2Minimal {
    <#
    .SYNOPSIS
    Starts a minimal WebView2 instance using only the core APIs.

    .DESCRIPTION
    This function creates a WebView2 using only the core runtime APIs,
    avoiding Windows Forms compatibility issues in PowerShell Core.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .EXAMPLE
    Start-WebView2Minimal
    #>

    [CmdletBinding()]
    param(
        [string]$EdgeProfile,
        [switch]$InPrivate
    )

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        # Initialize WebView2 assemblies (Core only)
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

        # Create WebView2 environment using synchronous approach
        try {
            "Creating WebView2 environment..." | Write-Verbose

            # Use the synchronous CreateAsync pattern that works in PowerShell
            $environmentTask = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $userDataFolder)

            # Use a simple loop to wait for completion instead of async/await
            $maxWait = 30 # seconds
            $waited = 0
            while (-not $environmentTask.IsCompleted -and $waited -lt $maxWait) {
                Start-Sleep -Milliseconds 100
                $waited += 0.1
            }

            if ($environmentTask.IsCompleted) {
                if ($environmentTask.IsFaulted) {
                    throw "Environment creation failed: $($environmentTask.Exception.InnerException.Message)"
                }
                $Script:WebView2Environment = $environmentTask.Result
                "WebView2 environment created successfully" | Write-Verbose
            } else {
                throw "WebView2 environment creation timed out after $maxWait seconds"
            }
        }
        catch {
            "Failed to create WebView2 environment: {0}" -f $_.Exception.Message | Write-Error
            throw
        }

        # Create a message-only window for the controller (no actual UI)
        try {
            "Creating minimal controller..." | Write-Verbose

            # Use a simpler approach - create a minimal window handle using Win32 API
            Add-Type -TypeDefinition @'
                using System;
                using System.Runtime.InteropServices;

                public class Win32Window {
                    [DllImport("user32.dll", SetLastError = true)]
                    public static extern IntPtr CreateWindowEx(
                        uint dwExStyle, string lpClassName, string lpWindowName,
                        uint dwStyle, int x, int y, int nWidth, int nHeight,
                        IntPtr hWndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);

                    [DllImport("user32.dll")]
                    public static extern bool DestroyWindow(IntPtr hWnd);

                    [DllImport("kernel32.dll")]
                    public static extern IntPtr GetModuleHandle(string lpModuleName);

                    public static IntPtr CreateMessageWindow() {
                        IntPtr hInstance = GetModuleHandle(null);
                        return CreateWindowEx(0, "STATIC", "WebView2MessageWindow",
                            0, 0, 0, 1, 1, IntPtr.Zero, IntPtr.Zero, hInstance, IntPtr.Zero);
                    }
                }
'@

            $Script:WebView2MessageWindow = [Win32Window]::CreateMessageWindow()
            if ($Script:WebView2MessageWindow -eq [IntPtr]::Zero) {
                throw "Failed to create message window"
            }

            "Message window created: 0x{0:X}" -f $Script:WebView2MessageWindow.ToInt64() | Write-Verbose

            # Create controller using the message window
            $controllerTask = $Script:WebView2Environment.CreateCoreWebView2ControllerAsync($Script:WebView2MessageWindow)

            # Wait for controller creation
            $maxWait = 30 # seconds
            $waited = 0
            while (-not $controllerTask.IsCompleted -and $waited -lt $maxWait) {
                Start-Sleep -Milliseconds 100
                $waited += 0.1
            }

            if ($controllerTask.IsCompleted) {
                if ($controllerTask.IsFaulted) {
                    throw "Controller creation failed: $($controllerTask.Exception.InnerException.Message)"
                }
                $Script:WebView2Controller = $controllerTask.Result
                $Script:WebView2Core = $Script:WebView2Controller.CoreWebView2
                "WebView2 controller created successfully" | Write-Verbose
            } else {
                throw "WebView2 controller creation timed out after $maxWait seconds"
            }
        }
        catch {
            "Failed to create WebView2 controller: {0}" -f $_.Exception.Message | Write-Error
            if ($Script:WebView2MessageWindow -ne [IntPtr]::Zero) {
                [Win32Window]::DestroyWindow($Script:WebView2MessageWindow)
                $Script:WebView2MessageWindow = [IntPtr]::Zero
            }
            throw
        }

        # Configure WebView2 settings
        try {
            $settings = $Script:WebView2Core.Settings
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
        $Script:WebView2HeadlessMode = $true
        $Script:WebView2Form = $null
        $Script:WebView2Control = $null

        "WebView2 initialized successfully (minimal mode)" | Write-Verbose
        return $Script:WebView2Core
    }
    catch {
        "Failed to start WebView2 (minimal mode): {0}" -f $_.Exception.Message | Write-Error
        Close-WebView2
        throw
    }
}