function Get-WebView2LogonPageError {
    <#
    .SYNOPSIS
        Reads the Omada logon page in the WebView2 window and stops a sign-in that was refused.

    .DESCRIPTION
        The WebView2 driver decides that a sign-in has succeeded by finding an oisauthtoken cookie,
        and decides nothing at all when it does not find one - the Omada response watchdog eventually
        closes the window and Get-DataFromWebView2 opens a new one. A federated sign-in that failed
        never sets that cookie: the identity provider hands the browser back to Omada, Omada renders
        the failure on its logon page, and the page then simply sits there. The result is three
        watchdog timeouts, half an hour, spent re-opening a window that lands on the same page.

        This function is what turns that page into an answer. It runs the scraper from
        Get-OmadaLogonErrorScript, hands the result to Test-OmadaLogonPageError, and for a refusal
        that a retry cannot change records it through Stop-OmadaLogin and closes the window - which
        is what Get-DataFromWebView2 needs to fail with the page's own message instead of counting
        retries.

        An error the user can still act on - a wrong password on Omada's own logon form - is reported
        once and otherwise left alone. The window stays open and typing the password again is exactly
        the right thing to do.

        Two details come from running inside a 150 ms timer tick:

          - The script is executed asynchronously and its result is picked up on a later tick, the
            same shape Invoke-WebView2MicrosoftLogin uses, so nothing blocks the UI thread and no
            work happens in a task continuation.
          - Scrapes are throttled to $Script:LogonPageErrorInterval, because a page that is merely
            loading does not need to be read seven times a second.

    .OUTPUTS
        System.Boolean. True when the sign-in was stopped, false in every other case - including
        while a scrape is still running.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    if ($null -ne $Script:LoginAbortReason) {
        # Already stopped; the window is on its way out.
        return $true
    }

    if ($null -eq $Script:WebView2 -or $null -eq $Script:WebView2.CoreWebView2) {
        return $false
    }

    if ($null -eq $Script:LogonPageErrorTask) {
        if ($null -ne $Script:LogonPageErrorLastCheck -and ([DateTime]::Now - $Script:LogonPageErrorLastCheck).TotalMilliseconds -lt $Script:LogonPageErrorInterval) {
            return $false
        }

        $Script:LogonPageErrorLastCheck = [DateTime]::Now
        $Script:LogonPageErrorTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync((Get-OmadaLogonErrorScript))
        return $false
    }

    if (-not $Script:LogonPageErrorTask.IsCompleted) {
        return $false
    }

    $Task = $Script:LogonPageErrorTask
    $Script:LogonPageErrorTask = $null

    if ($Task.IsFaulted) {
        # A navigation in flight cancels the script, which is normal here and says nothing about the
        # page. The next tick reads it again.
        "Get-WebView2LogonPageError - Could not read the page: {0}" -f (Protect-LogMessage -Message $Task.Exception.Message) | Write-Verbose
        return $false
    }

    $Scrape = $null
    try {
        $Json = ConvertFrom-JavaScriptResult $Task.Result
        if (-not [string]::IsNullOrWhiteSpace($Json)) {
            $Scrape = $Json | ConvertFrom-Json -ErrorAction Stop
        }
    }
    catch {
        "Get-WebView2LogonPageError - Could not decode the page result: {0}" -f (Protect-LogMessage -Message $_.Exception.Message) | Write-Verbose
        return $false
    }

    if ($null -eq $Scrape -or -not $Scrape.found) {
        return $false
    }

    $Verdict = Test-OmadaLogonPageError -Message $Scrape.message -Source $Scrape.source -HasLogonForm:([bool]$Scrape.hasLogonForm) -OnLogonPage:([bool]$Scrape.onLogonPage)
    if (-not $Verdict.IsError) {
        return $false
    }

    $PageUrl = $null
    if ($null -ne $Script:WebView2.Source) {
        $PageUrl = $Script:WebView2.Source.AbsoluteUri
    }

    if (-not $Verdict.IsFatal) {
        # Reported once per distinct message: the page keeps saying it, the user only needs telling
        # once, and the window has to stay open for them to correct it.
        if ($Script:LogonPageErrorReported -ne $Verdict.Message) {
            $Script:LogonPageErrorReported = $Verdict.Message
            "The Omada logon page reports: {0}" -f (Protect-LogMessage -Message $Verdict.Message) | Write-Warning
        }
        return $false
    }

    "Get-WebView2LogonPageError - Terminal logon page error found in '{0}'" -f $Verdict.Source | Write-Verbose

    Stop-OmadaLogin -Message $Verdict.Message -Code $Verdict.Code -Reason $Verdict.Reason -Url $PageUrl -Engine "WebView2" | Out-Null

    # The watchdog counters belong to the window that is closing, not to the next one.
    $Script:OmadaWatchdogStart = $null
    $Script:OmadaWatchdogRunning = $false
    $Script:ProgressCounter = 0
    $Script:LastFiredSecond = -1

    if ($null -ne $Script:WebView2) {
        $LoginForm = $Script:WebView2.FindForm()
        if ($null -ne $LoginForm) {
            $LoginForm.Close()
        }
    }

    return $true
}
