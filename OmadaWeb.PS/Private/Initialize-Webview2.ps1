function Initialize-WebView2 {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    param()

    try {
        "{0} - Initializing WebView2" -f $MyInvocation.MyCommand | Write-Verbose
        Write-Host "`r`nWebView2 opened, please login! Waiting for login." -NoNewline -ForegroundColor Yellow
        $Script:MicrosoftOnlineLogin = $true

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
                                        "Initialize-WebView2 - Navigating to {1}" -f $MyInvocation.MyCommand, $Script:OmadaWebBaseUrl | Write-Verbose
                                        $Script:WebView2.Source = ([System.Uri]::New($Script:OmadaWebBaseUrl))
                                        $Script:OmadaWatchdogRunning = $false
                                    }

                                    if ([System.Uri]::New($Script:OmadaWebBaseUrl).Host -eq $Script:WebView2.Source.Host) {
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
                                                $m = "`nWARNING: Omada response watchdog timeout exceeded after {0} seconds. {1}!" -f [System.Int32]([DateTime]::Now - $Script:OmadaWatchdogStart).TotalSeconds, $(if ($Script:LoginRetryCount -lt $Script:MaxLoginRetries) { "A re-authentication will be triggered" } else { "Login retry count exceeded, stopping" })
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
                                        { $_.Host -eq [System.Uri]::New($Script:OmadaWebBaseUrl).Host } {
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
        throw
    }
}