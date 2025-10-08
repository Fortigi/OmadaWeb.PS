function Stop-WebView2Helper {
    <#
    .SYNOPSIS
    Stops the WebView2 helper application and cleans up resources.
    #>

    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        if ($Script:WebViewHelperProcess -and -not $Script:WebViewHelperProcess.HasExited) {
            try {
                # Send close command
                $response = Send-WebView2Command -Action "close"
                "WebView2 helper close response: {0}" -f ($response | ConvertTo-Json -Compress) | Write-Verbose
            }
            catch {
                "Error sending close command: {0}" -f $_.Exception.Message | Write-Verbose
            }

            # Give it a moment to clean up
            Start-Sleep -Milliseconds 500

            # Kill the process if it's still running
            if (-not $Script:WebViewHelperProcess.HasExited) {
                $Script:WebViewHelperProcess.Kill()
                $Script:WebViewHelperProcess.WaitForExit(2000)
            }

            $Script:WebViewHelperProcess.Dispose()
        }

        # Clean up script variables
        $Script:WebViewHelperProcess = $null
        $Script:WebViewHelperInitialized = $false
        $Script:WebViewCore = $null

        "WebView2 helper stopped and cleaned up" | Write-Verbose
    }
    catch {
        "Error stopping WebView2 helper: {0}" -f $_.Exception.Message | Write-Verbose
    }
}