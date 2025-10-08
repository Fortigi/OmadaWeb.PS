function Close-WebView2 {
    <#
    .SYNOPSIS
    Closes the WebView2 browser instance and cleans up resources.

    .DESCRIPTION
    This function properly disposes of the WebView2 control, environment, and form to free up resources.

    .EXAMPLE
    Close-WebView2
    #>

    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        # Dispose WebView2 controller (headless mode)
        if ($Script:WebViewController) {
            try {
                # Close the controller properly
                if ($Script:WebViewController.GetType().GetMethod("Close")) {
                    $Script:WebViewController.Close()
                }
                $Script:WebViewController = $null
                "WebView2 controller disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 controller: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        # Dispose dummy form (headless mode)
        if ($Script:WebViewDummyForm) {
            try {
                $Script:WebViewDummyForm.Dispose()
                $Script:WebViewDummyForm = $null
                "WebView2 dummy form disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 dummy form: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        # Dispose WebView2 core (headless mode)
        if ($Script:WebViewCore) {
            try {
                # CoreWebView2 doesn't have a dispose method, just null it
                $Script:WebViewCore = $null
                "WebView2 core disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 core: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        # Dispose WebView2 control (UI modes)
        if ($Script:WebViewControl) {
            try {
                $Script:WebViewControl.Dispose()
                "WebView2 control disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 control: {0}" -f $_.Exception.Message | Write-Verbose
            }
            $Script:WebViewControl = $null
        }

        if ($Script:WebViewEnvironment) {
            try {
                # WebView2 environment doesn't have a dispose method, just null it
                $Script:WebViewEnvironment = $null
                "WebView2 environment disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 environment: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        if ($Script:WebViewForm) {
            try {
                if ($Script:WebViewForm.Visible) {
                    $Script:WebViewForm.Hide()
                }
                $Script:WebViewForm.Dispose()
                "WebView2 form disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 form: {0}" -f $_.Exception.Message | Write-Verbose
            }
            $Script:WebViewForm = $null
        }

        # Clean up temporary InPrivate folders
        $tempWebView2Path = Join-Path $env:TEMP "OmadaWeb.PS\WebView2\InPrivate"
        if (Test-Path $tempWebView2Path) {
            try {
                Get-ChildItem -Path $tempWebView2Path -Directory | ForEach-Object {
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
                "Cleaned up temporary WebView2 folders" | Write-Verbose
            }
            catch {
                "Warning: Could not clean up temporary WebView2 folders: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        # Reset mode flags
        $Script:WebViewMinimalMode = $false
        $Script:WebViewHeadlessMode = $false

        "WebView2 cleanup completed" | Write-Verbose
    }
    catch {
        "Error during WebView2 cleanup: {0}" -f $_.Exception.Message | Write-Verbose
    }
}