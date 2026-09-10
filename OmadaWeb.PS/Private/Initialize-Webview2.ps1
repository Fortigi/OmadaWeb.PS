function Initialize-WebView2 {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    param()

    try {
        "{0} - Initializing WebView2" -f $MyInvocation.MyCommand | Write-Verbose
        Write-Host "`r`nWebView2 opened, please login! Waiting for login." -NoNewline -ForegroundColor Yellow
        $Script:MicrosoftOnlineLogin = $true
        # This window gets its own attempt at autofill, and its own diagnostic if that attempt ends
        # in a manual sign-in.
        Reset-LoginAutomationState

        $Script:WebView2.add_CoreWebView2InitializationCompleted({
                param($sender, $e)

                Reset-Timer

                if ($e.IsSuccess) {
                    $Script:WinForm.Text = 'OmadaWeb.PS Login - Loading...'

                    try {

                        $sender.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $false
                        $sender.CoreWebView2.Settings.AreDevToolsEnabled = $false
                        $sender.CoreWebView2.Settings.AreBrowserAcceleratorKeysEnabled = $false
                        $sender.CoreWebView2.Settings.IsGeneralAutofillEnabled = $false
                        $sender.CoreWebView2.Settings.IsPasswordAutosaveEnabled = $false
                        $sender.CoreWebView2.Settings.IsScriptEnabled = $true
                        $sender.CoreWebView2.Settings.IsStatusBarEnabled = $true
                        $sender.CoreWebView2.Settings.IsZoomControlEnabled = $false
                        if ($Script:UserAgentParameterUsed -eq $true -and $null -ne $Script:UserAgent) {
                            $sender.CoreWebView2.Settings.UserAgent = $Script:UserAgent
                        }
                        else {
                            $sender.CoreWebView2.Settings.UserAgent = "{0} {1}" -f $sender.CoreWebView2.Settings.UserAgent, $Script:UserAgent
                        }
                        $sender.CoreWebView2.Settings.IsPinchZoomEnabled = $false
                        $sender.CoreWebView2.Settings.AreDefaultScriptDialogsEnabled = $true
                        $sender.CoreWebView2.Settings.AreHostObjectsAllowed = $false
                        $sender.CoreWebView2.Settings.IsBuiltInErrorPageEnabled = $true
                        $sender.CoreWebView2.Settings.IsWebMessageEnabled = $true
                        $sender.CoreWebView2.Settings.IsSwipeNavigationEnabled = $true
                        $sender.CoreWebView2.Settings.IsReputationCheckingRequired = $true
                        $sender.CoreWebView2.Settings.IsNonClientRegionSupportEnabled = $false

                        if ($Script:DebugWebView2) {
                            "Initialize-WebView2 - DebugWebView2 enabled, DevTools are available" | Write-Verbose
                            $sender.CoreWebView2.Settings.AreDefaultContextMenusEnabled = $true
                            $sender.CoreWebView2.Settings.AreDevToolsEnabled = $true
                            $sender.CoreWebView2.Settings.AreBrowserAcceleratorKeysEnabled = $true
                        }
                    }
                    catch {
                        [console]::ForegroundColor = 'Red'
                        [Console]::WriteLine("Error setting WebView2 settings: $_")
                        [Console]::ResetColor()
                        return
                    }

                    "Initialize-WebView2 - WebView2 Settings:`n{0}" -f ($sender.CoreWebView2.Settings | Format-List | Out-String) | Write-Verbose

                    # Which account signs in is settled in the authorization request, not on the page
                    # it leads to. Omada builds that request and Entra ID answers it - and when the
                    # browser already holds a session, it answers it without drawing anything at all,
                    # which is how a sign-in ends up being made as an account nobody chose. By the
                    # time the timer below sees a page, the choice has been made.
                    #
                    # NavigationStarting is the last point at which it can be influenced. It fires for
                    # redirects as well as for typed navigations, which is what this needs: the
                    # authorization request arrives as a redirect from Omada. Cancelling and
                    # navigating to the rewritten request is the documented way to do this, and only
                    # ever adds parameters, so what Entra validates is still the request Omada built.
                    try {
                        $sender.CoreWebView2.add_NavigationStarting({
                                param($NavigationSender, $NavigationArgs)

                                try {
                                    if ($null -eq $Script:CurrentWebView2Session) {
                                        return
                                    }

                                    $SignInAccount = Get-OmadaSignInAccount -SessionContext $Script:CurrentWebView2Session
                                    $Rewritten = New-EntraSignInUri -Uri $NavigationArgs.Uri -UserName $SignInAccount.UserName -SelectAccount:$SignInAccount.SelectAccount
                                    if ([string]::IsNullOrWhiteSpace($Rewritten)) {
                                        return
                                    }

                                    # A redirect chain can legitimately carry more than one
                                    # authorization request, so this is a cap rather than a single
                                    # shot - but a browser going round the same loop is worse than one
                                    # that stops trying, and the sign-in still works without the
                                    # rewrite. It just picks the account itself, which is the
                                    # behaviour this module had before.
                                    if ($Script:EntraSignInRequestRewriteCount -ge 3) {
                                        "Initialize-WebView2 - The sign-in request has already been redirected {0} times to ask for this account, so it is left alone now." -f $Script:EntraSignInRequestRewriteCount | Write-Verbose
                                        return
                                    }

                                    $Script:EntraSignInRequestRewriteCount++

                                    # The account name is in that URI, so only its path is reported -
                                    # the same rule every other diagnostic here follows.
                                    "Initialize-WebView2 - Asking Entra ID for the account this call named, on {0}" -f ([System.Uri]::new($Rewritten)).GetLeftPart([System.UriPartial]::Path) | Write-Verbose

                                    $NavigationArgs.Cancel = $true
                                    $NavigationSender.Navigate($Rewritten)
                                }
                                catch {
                                    # A failure here must not take the sign-in with it: without the
                                    # rewrite the browser simply chooses the account itself, which is
                                    # what it did before this existed.
                                    #
                                    # Reported by type and not by message. The exception raised while
                                    # rewriting a sign-in request routinely quotes the URI it was
                                    # given, and that URI is the one place the account name appears -
                                    # so printing the message here would put an account name on the
                                    # console for a failure that is not even fatal. The type says
                                    # which of the two steps broke, which is what a reader needs.
                                    [Console]::WriteLine("Error in NavigationStarting: {0}" -f $_.Exception.GetType().FullName)
                                }
                            })
                    }
                    catch {
                        # Same rule as the handler above: the type, not the message.
                        [Console]::WriteLine("Could not watch navigation for the sign-in account: {0}" -f $_.Exception.GetType().FullName)
                    }

                    $Script:WebView2.Visible = $true
                    $Script:OmadaWatchdogStart = $null
                    $Script:OmadaWatchdogRunning = $false
                    $Script:LastLoggedSecond = -2
                    Reset-Timer
                    $Script:Timer.Start()
                    try {
                        $Script:Timer.Add_Tick({
                                # Use .NET methods only - PowerShell cmdlets can throw PipelineStoppedException
                                try {

                                    if ($Script:WebView2.Source -eq "about:blank") {
                                        "{0} - Navigating to {1}" -f $MyInvocation.MyCommand, $Script:CurrentWebView2Session.BaseUrl | Write-Verbose
                                        $Script:WebView2.Source = ([System.Uri]::New($Script:CurrentWebView2Session.BaseUrl))
                                        $Script:OmadaWatchdogRunning = $false
                                    }

                                    if ([System.Uri]::New($Script:CurrentWebView2Session.BaseUrl).Host -eq $Script:WebView2.Source.Host) {
                                        if (!$Script:OmadaWatchdogRunning) {
                                            $Script:OmadaWatchdogStart = [DateTime]::Now
                                            $Script:OmadaWatchdogRunning = $true
                                            $Script:LastLoggedSecond = -1

                                            "Initialize-WebView2 - Omada watchdog timer started. Watchdog timer expires after {0} seconds" -f $Script:OmadaWatchdogTimeout | Write-Verbose
                                        }
                                        elseif ($Script:OmadaWatchdogRunning) {
                                            # Check if timeout exceeded
                                            if ($Script:OmadaWatchdogRunning -and [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds -gt 5 -and [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds % 10 -eq 0 -and [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds -ne $Script:LastLoggedSecond) {
                                                $Script:LastLoggedSecond = [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds
                                                "Initialize-WebView2 - Omada watchdog timer running for {0} seconds" -f [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds | Write-Verbose
                                            }
                                            if ($Script:OmadaWatchdogRunning -and [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds -ge $Script:OmadaWatchdogTimeout) {
                                                [Console]::ForegroundColor = 'Yellow'
                                                $m = "`nWARNING: Omada response watchdog timeout exceeded after {0} seconds. {1}!" -f [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds, $(if ($Script:CurrentWebView2Session.LoginRetryCount -lt $Script:MaxLoginRetries) { "A re-authentication will be triggered" } else { "Login try count exceeded, stopping" })
                                                [Console]::WriteLine($m)
                                                [Console]::ResetColor()

                                                # Reset watchdog
                                                $Script:OmadaWatchdogStart = $null
                                                $Script:LastCheckedHost = $null

                                                # Close the form to trigger a reload
                                                if ($null -ne $Script:WebView2 -and $null -ne $Script:WebView2.FindForm()) {
                                                    $Script:WebView2.FindForm().Close()
                                                }

                                                return $false
                                            }
                                            elseif ($Script:OmadaWatchdogRunning -and [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds -gt 5 -and [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds % 20 -eq 0 -and [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds -ne $Script:LastFiredSecond -and ($Script:OmadaWatchdogTimeout - [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds) -ge 1) {
                                                $Script:LastFiredSecond = [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds
                                                [Console]::ForegroundColor = 'Yellow'
                                                $m = "`nWARNING: Omada should respond in the remaining {0} seconds! If not, a re-authentication will be triggered." -f ($Script:OmadaWatchdogTimeout - [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds)
                                                [Console]::WriteLine($m)
                                                [Console]::ResetColor()
                                            }
                                        }
                                    }
                                    else {
                                        if ( $Script:LastCheckedHost -ne $Script:WebView2.Source.Host) {
                                            "Initialize-WebView2 - Omada watchdog timer stopped" | Write-Verbose
                                        }
                                        $Script:OmadaWatchdogStart = $null
                                        $Script:LastCheckedHost = $Script:WebView2.Source.Host
                                        $Script:OmadaWatchdogRunning = $false
                                        $Script:LastLoggedSecond = -2

                                    }
                                    if (-not $Script:ProgressCounter) { $Script:ProgressCounter = 0 }
                                    $Script:ProgressCounter++
                                    if ($Script:ProgressCounter % 3 -eq 0) {
                                        [Console]::ForegroundColor = 'Yellow'
                                        [Console]::Write(".")
                                        [Console]::ResetColor()
                                    }

                                    switch ($Script:WebView2.Source) {
                                        { $_.Host -eq [System.Uri]::New($Script:CurrentWebView2Session.BaseUrl).Host } {
                                            # A federated sign-in that failed comes back as an error
                                            # banner on Omada's own logon page, not as an HTTP error:
                                            # no oisauthtoken is ever set, so the watchdog below would
                                            # keep re-opening this window until the retry count runs
                                            # out. Read the page before waiting on a cookie that
                                            # cannot arrive.
                                            if (Get-WebView2LogonPageError) {
                                                return
                                            }
                                            Get-WebView2Cookie
                                        }
                                        { $_.Host -eq [System.Uri]::New("https://login.microsoftonline.com").Host -and $Script:MicrosoftOnlineLogin } {
                                            Invoke-WebView2MicrosoftLogin
                                        }
                                        default {
                                            return
                                        }
                                    }

                                    if ( $Script:LastCheckedHost -ne $Script:WebView2.Source.Host) {
                                        $Script:LastCheckedHost = $Script:WebView2.Source.Host
                                    }
                                }
                                catch {
                                    [Console]::ForegroundColor = 'Yellow'
                                    $m = "`nWARNING: An error occurred in WebView2, retry: {0}`n" -f $_.Exception.Message
                                    [Console]::Write($m)
                                    [Console]::ResetColor()
                                }
                            })
                    }
                    catch {
                        [Console]::WriteLine("Error: $_")
                        Reset-Timer

                        $Script:OmadaWatchdogRunning = $false
                        return
                    }
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("WebView2 init failed: $($e.InitializationException.Message)")
                    Reset-Timer
                    return
                }
            }

        )

    }
    catch {
        "Error in Initialize-WebView2: {0}" -f $_ | Write-Host  -ForegroundColor Red
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}