function Stop-WebView2Helper {
    <#
    .SYNOPSIS
    Stops the WebView2 helper application and cleans up resources.
    #>

    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        if ($Script:WebView2HelperProcess -and -not $Script:WebView2HelperProcess.HasExited) {
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
            if (-not $Script:WebView2HelperProcess.HasExited) {
                $Script:WebView2HelperProcess.Kill()
                $Script:WebView2HelperProcess.WaitForExit(2000)
            }

            $Script:WebView2HelperProcess.Dispose()
        }

        # Clean up script variables
        $Script:WebView2HelperProcess = $null
        $Script:WebView2HelperInitialized = $false
        $Script:WebView2Core = $null

        "WebView2 helper stopped and cleaned up" | Write-Verbose
    }
    catch {
        "Error stopping WebView2 helper: {0}" -f $_.Exception.Message | Write-Verbose
    }
}