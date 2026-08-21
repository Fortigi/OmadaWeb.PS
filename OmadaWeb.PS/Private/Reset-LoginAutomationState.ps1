function Reset-LoginAutomationState {
    <#
    .SYNOPSIS
        Gives credential autofill a clean slate for a new sign-in window.

    .DESCRIPTION
        Switch-ToManualLogin deliberately leaves its state set for the rest of a sign-in: that is what
        keeps a 150 ms timer from repeating the same warning forever, and what keeps the drivers from
        fighting a user who is typing. It has to be cleared somewhere, and it cannot be cleared by
        Invoke-WebView2MicrosoftLogin's "left the sign-in page" branch - after a fallback that function
        returns at the top, because autofill is off, and never reaches it.

        So the reset belongs where a new browser window starts: Initialize-WebView2 for WebView2 and
        Get-DataFromWebDriver for Edge WebDriver. Without it, a second window in the same session
        would drive the page again (Initialize-WebView2 re-enables autofill) while the fallback still
        counted as reported, and the user would never see the diagnostic for it.
    #>
    [CmdletBinding()]
    param()

    $Script:ManualLoginFallbackActive = $false
    $Script:UnmatchedPageSignature = $null
    $Script:UnmatchedPageSince = $null

    # Scrape state of Get-WebView2LogonPageError. It belongs to a browser window - a pending script
    # task cannot outlive the CoreWebView2 that was asked to run it - so it is cleared here with the
    # rest of the per-window state. $Script:LoginAbortReason deliberately is not: a refused sign-in
    # closes its window, and the reason has to survive that or the driver would just open another one.
    $Script:LogonPageErrorTask = $null
    $Script:LogonPageErrorLastCheck = $null
    $Script:LogonPageErrorReported = $null
}
