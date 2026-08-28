function Invoke-WebView2MicrosoftLogin {
    <#
    .SYNOPSIS
        Drives the Microsoft Entra ID sign-in page from the supplied credential, one timer tick at a
        time.

    .DESCRIPTION
        Called from the 150 ms WebView2 timer while the browser is on login.microsoftonline.com. Each
        tick does one small piece of work and returns, because everything here runs on the UI thread
        of an open window: blocking it would freeze the browser the user may still have to type in.

        The work is split in three so that the part worth testing can be tested. Reading the page is
        one asynchronous script - the one Get-EntraSignInProbeScript builds - which returns a snapshot
        carrying no rendered text at all. Deciding what that snapshot means is Resolve-EntraSignInScreen,
        an ordinary function with no browser behind it. Acting on the decision is this function, and
        it is deliberately dull: fill a field, click an element, read a number, or stop.

        Two of those outcomes end the sign-in rather than continuing it, and the difference matters:

          - Stop. Entra ID reported a failure that no retry can change - a Conditional Access block,
            a locked account, a refused password. Stop-OmadaLogin records why and closes the window,
            and the driver reports that instead of opening another one. A wrong password belongs
            here: sending it again is what drives an account into smart lockout.
          - Wait. The page is one this module cannot drive, or has never seen. Nothing happens
            immediately, because a page caught mid-navigation looks exactly the same; only when
            Test-LoginAutomationStalled says the page has stopped changing does Switch-ToManualLogin
            hand the sign-in to the user, quoting what the decision said about it.

        The credential's password is read here and nowhere else. It is passed to the page through
        ConvertTo-JavaScriptLiteral, which is what keeps a password containing a quote from ending the
        string literal it is written into (issue #19).

    .OUTPUTS
        System.Boolean. True when this tick moved the sign-in forward, false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param()

    try {
        # Check if login has already failed - don't attempt again
        if ($Script:LoginFailed) {
            "Login previously failed - not attempting again" | Write-Verbose
            return $false
        }

        if (!$Script:MicrosoftOnlineLogin) {
            return $false
        }

        if ($null -eq $Script:WebView2 -or $null -eq $Script:WebView2.CoreWebView2) {
            return $false
        }

        # Writes a value into a field and raises the events the sign-in app listens for. Applied to
        # its arguments by the call site, so it stays a bare function expression.
        $SetElementValueScript = @"
(function(elementId, value) {
    var element = document.getElementById(elementId);
    if (element) {
        element.value = value;
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
    }
    return false;
})
"@

        $ClickElementScript = @"
(function(elementId) {
    var element = document.getElementById(elementId);
    if (element) {
        element.click();
        return true;
    }
    return false;
})
"@

        # 'Pick an account' identifies each tile by the account name in its data-test-id.
        #
        # The visibility test is not decoration: Get-EntraSignInProbeScript reports only visible
        # tiles, so the resolver can only ever choose one. Clicking the first element carrying the
        # id regardless would let a hidden namesake take the click instead, and that failure is
        # invisible from here - the click reports success, which restarts the stall clock, so the
        # driver would sit on the same page clicking nothing for as long as the window is open.
        $ClickAccountTileScript = @"
(function(dataTestId) {
    function isVisible(element) {
        if (!element) { return false; }
        try {
            var style = window.getComputedStyle(element);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') { return false; }
        }
        catch (e) { return false; }
        if (element.getAttribute('aria-hidden') === 'true') { return false; }
        if (element.disabled === true) { return false; }
        return element.offsetWidth > 0 || element.offsetHeight > 0 || element.getClientRects().length > 0;
    }

    var elements = document.querySelectorAll('[data-test-id]');
    for (var i = 0; i < elements.length; i++) {
        var value = elements[i].getAttribute('data-test-id');
        if (value != null && value.toLowerCase() === dataTestId.toLowerCase() && isVisible(elements[i])) {
            elements[i].click();
            return true;
        }
    }
    return false;
})
"@

        # The tile that leads away from the remembered accounts. Its label is localized; the id of
        # the element that labels it is not.
        $ClickUseAnotherAccountScript = @"
(function() {
    var otherAccount = document.querySelector('[aria-labelledby="otherTileText"]');
    if (otherAccount) {
        otherAccount.click();
        return true;
    }
    var otherTileText = document.getElementById('otherTileText');
    if (otherTileText) {
        var clickable = otherTileText.closest('[role="button"], button, a, div');
        if (clickable) {
            clickable.click();
            return true;
        }
    }
    return false;
})();
"@

        # Verification methods on 'choose a way to sign in' are clicked by position, because the
        # options carry nothing that names which method they are. Resolve-EntraSignInScreen only
        # produces an index after checking that the options and the methods line up.
        $ClickProofOptionScript = @"
(function(containerId, index) {
    var container = document.getElementById(containerId);
    if (!container) { return false; }
    var options = container.querySelectorAll('[data-value], [role="button"], [role="listitem"]');
    var counted = [];
    for (var i = 0; i < options.length; i++) {
        if (counted.indexOf(options[i]) === -1) { counted.push(options[i]); }
    }
    if (index < 0 || index >= counted.length) { return false; }
    counted[index].click();
    return true;
})
"@

        # Check if we're on the Microsoft login page
        if ($Script:WebView2.Source.Host -ne [System.Uri]::New("https://login.microsoftonline.com").Host) {
            $Script:MicrosoftOnlineLogin = $false
            # Reset state when leaving login page
            $Script:LoginState = $null
            $Script:LoginTask = $null
            $Script:PageState = $null
            $Script:PendingSubmitId = $null
            $Script:LoginSubState = $null
            $Script:LoginFailed = $false
            $Script:CurrentScenario = $null
            $Script:PreviousScenario = $null
            $Script:MfaWaitLastReported = $null
            Reset-LoginAutomationState
            return $false
        }

        # No user name means nothing to fill in, so the user signs in by hand in the open window.
        if (-not $Script:CurrentWebView2Session.Credential -or [string]::IsNullOrWhiteSpace($Script:CurrentWebView2Session.Credential.UserName)) {
            return $false
        }

        if ($null -eq $Script:LoginState) {
            $Script:LoginState = "ReadingPage"
            $Script:LoginTask = $null
            $Script:PageState = $null
            $Script:PendingSubmitId = $null
        }

        switch ($Script:LoginState) {
            "ReadingPage" {
                if ($null -eq $Script:LoginTask) {
                    "Invoke-WebView2MicrosoftLogin - Reading the sign-in page" | Write-Verbose
                    $Script:LoginTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync((Get-EntraSignInProbeScript))
                    return $false
                }

                if (-not $Script:LoginTask.IsCompleted) {
                    return $false
                }

                $Snapshot = $null
                $UnreadableReason = $null

                if ($Script:LoginTask.IsFaulted) {
                    $UnreadableReason = $Script:LoginTask.Exception.Message
                    "Invoke-WebView2MicrosoftLogin - Could not read the sign-in page: {0}" -f $UnreadableReason | Write-Verbose
                }
                else {
                    try {
                        # ExecuteScriptAsync hands back the script's return value as JSON, and the
                        # script returns a JSON document - so the payload is decoded twice.
                        $Snapshot = $Script:LoginTask.Result | ConvertFrom-Json | ConvertFrom-Json
                    }
                    catch {
                        $UnreadableReason = $_.Exception.Message
                        "Invoke-WebView2MicrosoftLogin - The sign-in page snapshot could not be read: {0}" -f $UnreadableReason | Write-Verbose
                    }

                    if ($null -eq $Snapshot -and $null -eq $UnreadableReason) {
                        $UnreadableReason = "The sign-in page did not answer the query this module reads it with."
                    }
                }

                $Script:LoginTask = $null

                if ($null -eq $Snapshot) {
                    # A page that cannot be read is the loudest form of a selector break - and a
                    # script that cannot even be executed is no different from here. Both retry on
                    # the next tick, because a page mid-navigation produces exactly this; the stall
                    # clock is what ends the retrying, and leaving it unarmed on either path would
                    # loop until the window is closed by hand.
                    if (Test-LoginAutomationStalled -ElementId @()) {
                        Switch-ToManualLogin -State "ReadingPage" -MissingElementId @($Script:EntraSignInElementId.Values) -FoundElementId @() -Url $Script:WebView2.Source.AbsoluteUri -Reason $UnreadableReason | Out-Null
                    }

                    return $false
                }

                $Script:PageState = $Snapshot
                $Script:LoginState = "Deciding"
                return $false
            }

            "Deciding" {
                $HasPassword = $false
                $NetworkCredential = $Script:CurrentWebView2Session.Credential.GetNetworkCredential()
                if (-not [string]::IsNullOrEmpty($NetworkCredential.Password)) {
                    $HasPassword = $true
                }

                $PreferredMfaMethod = $null
                if ($null -ne $Script:CurrentWebView2Session.PreferredMfaMethod) {
                    $PreferredMfaMethod = [string]$Script:CurrentWebView2Session.PreferredMfaMethod
                }

                $Decision = Resolve-EntraSignInScreen -PageState $Script:PageState -UserName $Script:CurrentWebView2Session.Credential.UserName.Trim() -HasPassword:$HasPassword -PreferredMfaMethod $PreferredMfaMethod -MfaRequestDisplayed:$Script:MfaRequestDisplayed

                "Invoke-WebView2MicrosoftLogin - Screen '{0}', action '{1}'" -f $Decision.Screen, $Decision.Action | Write-Verbose
                $Script:PreviousScenario = $Script:CurrentScenario
                $Script:CurrentScenario = $Decision.Screen

                # Waiting for someone to reach for their phone is not a stall, and it is the one step
                # that legitimately takes minutes.
                # Read through the property bag: Set-StrictMode turns a plain access on a member the
                # snapshot does not carry into a terminating error, and a partly readable page is
                # exactly the case this diagnostic exists for.
                $Present = @()
                $IdProperty = $Script:PageState.PSObject.Properties["ids"]
                if ($null -ne $IdProperty) {
                    $Present = @($IdProperty.Value)
                }

                $WaitingForApproval = $Script:MfaRequestDisplayed -and $Decision.Screen -eq "ApprovalNumber"
                if (Test-LoginAutomationStalled -ElementId $Present -WaitingForApproval:$WaitingForApproval) {
                    $MissingElementId = @($Script:EntraSignInElementId.Values | Where-Object { $_ -notin $Present })
                    $ScenarioName = "NoMatchingScreen"
                    if (-not [string]::IsNullOrWhiteSpace($Decision.Screen) -and $Decision.Screen -ne "Unknown") {
                        $ScenarioName = $Decision.Screen
                    }

                    Switch-ToManualLogin -State ("Deciding/{0}" -f $ScenarioName) -MissingElementId $MissingElementId -FoundElementId $Present -Url $Script:WebView2.Source.AbsoluteUri -Reason $Decision.Reason | Out-Null
                    return $false
                }

                switch ($Decision.Action) {
                    "Stop" {
                        $Message = $Decision.Reason
                        if ([string]::IsNullOrWhiteSpace($Message)) {
                            $Message = "Entra ID refused this sign-in."
                        }

                        Stop-OmadaLogin -Message $Message -Code $Decision.Code -Reason $Decision.Reason -Url $Script:WebView2.Source.AbsoluteUri -Engine "WebView2" | Out-Null

                        # The watchdog counters belong to the window that is closing, not to the next.
                        $Script:OmadaWatchdogStart = $null
                        $Script:OmadaWatchdogRunning = $false
                        $Script:ProgressCounter = 0
                        $Script:LastFiredSecond = -1

                        try {
                            if ($null -ne $Script:WebView2) {
                                $LoginForm = $Script:WebView2.FindForm()
                                if ($null -ne $LoginForm) {
                                    $LoginForm.Close()
                                }
                            }
                        }
                        catch {
                            "Invoke-WebView2MicrosoftLogin - Could not close the sign-in window: {0}" -f $_.Exception.Message | Write-Verbose
                        }

                        return $false
                    }

                    "Retry" {
                        "`nMFA failed! Please retry!" | Write-Warning
                        $Script:MfaRequestDisplayed = $false
                        $Script:MfaWaitLastReported = $null
                        $Script:UnmatchedPageSince = $null
                        $Script:LoginState = "ReadingPage"
                        $Script:PageState = $null
                        return $true
                    }

                    "ReadNumber" {
                        $Shown = Show-EntraApprovalNumber -Number $Decision.Value

                        # Read the page again on the next tick. Nothing is clicked here - the user
                        # approves on their phone - so this screen is left by the page changing, and
                        # deciding from the snapshot already in hand would never see that happen.
                        $Script:LoginState = "ReadingPage"
                        $Script:PageState = $null
                        return $Shown
                    }

                    "SetValueAndClick" {
                        $Value = $Decision.Value
                        if ($Decision.ValueSource -eq "Password") {
                            # Read here and nowhere else, so the secret never travels in the decision.
                            $Value = $NetworkCredential.Password
                        }

                        $SetScript = "$SetElementValueScript($(ConvertTo-JavaScriptLiteral $Decision.ElementId), $(ConvertTo-JavaScriptLiteral $Value))"
                        $Script:LoginTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync($SetScript)
                        $Script:PendingSubmitId = $Decision.SubmitId
                        $Script:LoginState = "Acting"
                        return $false
                    }

                    "Click" {
                        $Script:LoginTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync("$ClickElementScript($(ConvertTo-JavaScriptLiteral $Decision.ElementId))")
                        $Script:PendingSubmitId = $null
                        $Script:LoginState = "Acting"
                        return $false
                    }

                    "ClickAccountTile" {
                        $Script:LoginTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync("$ClickAccountTileScript($(ConvertTo-JavaScriptLiteral $Decision.Value))")
                        $Script:PendingSubmitId = $null
                        $Script:LoginState = "Acting"
                        return $false
                    }

                    "ClickUseAnotherAccount" {
                        $Script:LoginTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync($ClickUseAnotherAccountScript)
                        $Script:PendingSubmitId = $null
                        $Script:LoginState = "Acting"
                        return $false
                    }

                    "ClickProofOption" {
                        $Script:LoginTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync("$ClickProofOptionScript($(ConvertTo-JavaScriptLiteral $Script:EntraSignInElementId.ProofsContainer), $($Decision.Index))")
                        $Script:PendingSubmitId = $null
                        $Script:LoginState = "Acting"
                        return $false
                    }

                    default {
                        # 'Wait'. The stall clock above decides when waiting has gone on long enough;
                        # until then, read the page again on the next tick so a page that is only
                        # mid-navigation is picked up as soon as it settles.
                        if (-not [string]::IsNullOrWhiteSpace($Decision.Reason)) {
                            "Invoke-WebView2MicrosoftLogin - Waiting: {0}" -f $Decision.Reason | Write-Verbose
                        }

                        $Script:LoginState = "ReadingPage"
                        $Script:PageState = $null
                        return $false
                    }
                }
            }

            "Acting" {
                if ($null -eq $Script:LoginTask) {
                    $Script:LoginState = "ReadingPage"
                    return $false
                }

                if (-not $Script:LoginTask.IsCompleted) {
                    return $false
                }

                if ($Script:LoginTask.IsFaulted) {
                    # The page could not be driven at all, so autofill is over for this sign-in. Say
                    # so rather than going quiet.
                    $FoundElementId = @()
                    if ($null -ne $Script:PageState) {
                        $IdProperty = $Script:PageState.PSObject.Properties["ids"]
                        if ($null -ne $IdProperty) {
                            $FoundElementId = @($IdProperty.Value)
                        }
                    }

                    Switch-ToManualLogin -State ("Acting/{0}" -f $Script:CurrentScenario) -FoundElementId $FoundElementId -Url $Script:WebView2.Source.AbsoluteUri -Reason $Script:LoginTask.Exception.Message | Out-Null
                    $Script:LoginTask = $null
                    $Script:PendingSubmitId = $null
                    return $false
                }

                if (-not [string]::IsNullOrWhiteSpace($Script:PendingSubmitId)) {
                    $SubmitId = $Script:PendingSubmitId
                    $Script:PendingSubmitId = $null
                    $Script:LoginTask = $Script:WebView2.CoreWebView2.ExecuteScriptAsync("$ClickElementScript($(ConvertTo-JavaScriptLiteral $SubmitId))")
                    return $false
                }

                # Something was clicked, which counts as progress even when the next page happens to
                # carry the same element ids - the username and the password screen do.
                $Script:UnmatchedPageSince = $null
                $Script:LoginTask = $null
                $Script:PageState = $null
                $Script:LoginState = "ReadingPage"
                return $true
            }
        }

        return $false
    }
    catch {
        [Console]::WriteLine("Error in Invoke-WebView2MicrosoftLogin: $_")
        # Reset state on error
        $Script:LoginState = "ReadingPage"
        $Script:LoginTask = $null
        $Script:PageState = $null
        $Script:PendingSubmitId = $null
        return $false
    }
}
