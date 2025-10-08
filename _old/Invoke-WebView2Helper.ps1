function Start-WebView2Helper {
    <#
    .SYNOPSIS
    Starts the WebView2 C# helper application for reliable WebView2 functionality.

    .DESCRIPTION
    This function starts the OmadaWebView2Helper.exe application which provides
    reliable WebView2 functionality without PowerShell threading limitations.

    .PARAMETER EdgeProfile
    The Edge profile to use for the browser session.

    .PARAMETER InPrivate
    Use InPrivate browsing mode.

    .PARAMETER UserDataFolder
    Custom user data folder path.

    .EXAMPLE
    Start-WebView2Helper -InPrivate

    .EXAMPLE
    Start-WebView2Helper -EdgeProfile "Profile 1"
    #>

    [CmdletBinding()]
    param(
        [string]$EdgeProfile,
        [switch]$InPrivate,
        [string]$UserDataFolder
    )

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        # Find the helper executable
        $helperPath = Join-Path $PSScriptRoot "..\WebView2Helper\bin\Release\net6.0-windows\OmadaWebView2Helper.exe"
        if (-not (Test-Path $helperPath)) {
            # Try debug build
            $helperPath = Join-Path $PSScriptRoot "..\WebView2Helper\bin\Debug\net6.0-windows\OmadaWebView2Helper.exe"
        }

        if (-not (Test-Path $helperPath)) {
            throw "WebView2 helper application not found. Please build the C# helper first."
        }

        "Starting WebView2 helper: {0}" -f $helperPath | Write-Verbose

        # Start the helper process
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $helperPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $Script:WebViewHelperProcess = [System.Diagnostics.Process]::Start($startInfo)

        if (-not $Script:WebViewHelperProcess) {
            throw "Failed to start WebView2 helper process"
        }

        # Wait for ready message
        $readyResponse = $Script:WebViewHelperProcess.StandardOutput.ReadLine()
        $readyData = ConvertFrom-Json $readyResponse

        if ($readyData.status -ne "ready") {
            throw "WebView2 helper failed to start: $($readyData.message)"
        }

        "WebView2 helper started successfully" | Write-Verbose

        # Initialize WebView2
        $initParams = @{}

        if ($InPrivate) {
            $initParams["inPrivate"] = $true
        }

        if (![string]::IsNullOrWhiteSpace($EdgeProfile)) {
            $initParams["profile"] = $EdgeProfile
        }

        if (![string]::IsNullOrWhiteSpace($UserDataFolder)) {
            $initParams["userDataFolder"] = $UserDataFolder
        }

        $response = Send-WebView2Command -Action "initialize" -Parameters $initParams

        if (-not $response.Success) {
            throw "WebView2 initialization failed: $($response.Error)"
        }

        "WebView2 initialized: {0}" -f ($response.Data | ConvertTo-Json -Compress) | Write-Verbose

        # Store helper process info
        $Script:WebViewHelperInitialized = $true
        $Script:WebViewCore = [PSCustomObject]@{
            HelperProcess = $Script:WebViewHelperProcess
            Source = ""
            DocumentTitle = ""
        }

        return $Script:WebViewCore
    }
    catch {
        "Failed to start WebView2 helper: {0}" -f $_.Exception.Message | Write-Error
        if ($Script:WebViewHelperProcess) {
            $Script:WebViewHelperProcess.Kill()
            $Script:WebViewHelperProcess = $null
        }
        throw
    }
}










