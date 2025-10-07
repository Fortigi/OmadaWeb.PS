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
        if ($Script:WebView2Controller) {
            try {
                # Close the controller properly
                if ($Script:WebView2Controller.GetType().GetMethod("Close")) {
                    $Script:WebView2Controller.Close()
                }
                $Script:WebView2Controller = $null
                "WebView2 controller disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 controller: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        # Dispose dummy form (headless mode)
        if ($Script:WebView2DummyForm) {
            try {
                $Script:WebView2DummyForm.Dispose()
                $Script:WebView2DummyForm = $null
                "WebView2 dummy form disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 dummy form: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        # Dispose WebView2 core (headless mode)
        if ($Script:WebView2Core) {
            try {
                # CoreWebView2 doesn't have a dispose method, just null it
                $Script:WebView2Core = $null
                "WebView2 core disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 core: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        # Dispose WebView2 control (UI modes)
        if ($Script:WebView2Control) {
            try {
                $Script:WebView2Control.Dispose()
                "WebView2 control disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 control: {0}" -f $_.Exception.Message | Write-Verbose
            }
            $Script:WebView2Control = $null
        }

        if ($Script:WebView2Environment) {
            try {
                # WebView2 environment doesn't have a dispose method, just null it
                $Script:WebView2Environment = $null
                "WebView2 environment disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 environment: {0}" -f $_.Exception.Message | Write-Verbose
            }
        }

        if ($Script:WebView2Form) {
            try {
                if ($Script:WebView2Form.Visible) {
                    $Script:WebView2Form.Hide()
                }
                $Script:WebView2Form.Dispose()
                "WebView2 form disposed" | Write-Verbose
            }
            catch {
                "Error disposing WebView2 form: {0}" -f $_.Exception.Message | Write-Verbose
            }
            $Script:WebView2Form = $null
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
        $Script:WebView2MinimalMode = $false
        $Script:WebView2HeadlessMode = $false

        "WebView2 cleanup completed" | Write-Verbose
    }
    catch {
        "Error during WebView2 cleanup: {0}" -f $_.Exception.Message | Write-Verbose
    }
}