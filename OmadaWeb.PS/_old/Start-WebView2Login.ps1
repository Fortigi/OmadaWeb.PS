function Start-WebView2Login {
    <#
    .SYNOPSIS
    Navigates the WebView2 browser to the Omada login page.

    .DESCRIPTION
    This function navigates the WebView2 control to the appropriate Omada login URL
    and shows the authentication form to the user.

    .EXAMPLE
    Start-WebView2Login
    #>

    [CmdletBinding()]
    param()

    try {
        "{0}" -f $MyInvocation.MyCommand | Write-Verbose

        if (-not $Script:WebView2Control -or -not $Script:WebView2Form) {
            throw "WebView2 control not initialized. Call Start-WebView2 first."
        }

        # Construct the login URL
        $LoginUrl = "{0}/login" -f $Script:OmadaWebBaseUrl.TrimEnd('/')
        "Navigating to login URL: {0}" -f $LoginUrl | Write-Verbose

        # Navigate to the login page
        $Script:WebView2Control.CoreWebView2.Navigate($LoginUrl)

        # Show the form
        $Script:WebView2Form.Show()
        $Script:WebView2Form.BringToFront()
        $Script:WebView2Form.Activate()

        "WebView2 login form displayed" | Write-Verbose
    }
    catch {
        "Failed to start WebView2 login: {0}" -f $_.Exception.Message | Write-Error
        throw
    }
}