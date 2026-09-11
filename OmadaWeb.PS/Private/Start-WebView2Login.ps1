function Start-WebView2Login {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'e', Justification = 'The use of e is intended here for event handlers.')]
    param(
        [string]$EdgeProfile = "Default",
        [switch]$InPrivate
    )

    # Declared outside the try because the catch below reads them. Anything that threw before they
    # were assigned would otherwise make the handler fail on an unset variable under StrictMode, and
    # the error the user saw would be that one instead of the one that actually broke the sign-in.
    $ConsoleControlAvailable = $false
    $OriginalTreatControlCAsInput = $null

    try {
        "{0} - Starting WebView2 login" -f $MyInvocation.MyCommand | Write-Verbose

        # Ctrl+C is taken over further down so that pressing it closes this window instead of killing
        # the caller's session, and put back afterwards. Both halves of that go through
        # Console.TreatControlCAsInput, which throws "The handle is invalid" on a process with no
        # console attached - a scheduled task, a service, a CI job, a piped script. Reading it here
        # unguarded is what made -AuthenticationType WebView2 fail instantly and non-interactively,
        # before the browser it needs was ever created (issue #79). See Test-OmadaConsoleControl.
        $ConsoleControlAvailable = Test-OmadaConsoleControl
        if ($ConsoleControlAvailable) {
            $OriginalTreatControlCAsInput = [Console]::TreatControlCAsInput
        }

        # Asked before anything is built, and answered plainly. WebView2 is COM that needs a
        # single-threaded apartment: on an MTA thread the WinForms objects below are all created
        # happily and then CoreWebView2Environment::CreateAsync comes back with "Cannot change thread
        # mode after it is set", which reads as a COM fault rather than as "this host cannot show a
        # window". Both fallbacks fail the same way, so the trace showed two attempts and no reason,
        # and the sign-in canary reported the missing browser as a changed Microsoft sign-in page
        # (issue #90). Stopping here says which host is the problem and what to do instead.
        #
        # $Script:StopError, because retrying is pointless: a thread's apartment cannot be changed
        # once it is set, so the next of the three login attempts would fail identically.
        if (-not (Test-OmadaStaThread)) {
            $Script:StopError = $true
            "{0} - WebView2 needs a single-threaded apartment (STA), and this host is multi-threaded (MTA), so no browser window can be created here. A PowerShell background job and any runspace created without ApartmentState.STA are MTA. Start the host with -STA, run the sign-in in its own STA process, or use -AuthenticationType Selenium." -f $MyInvocation.MyCommand | Write-Error -ErrorAction Stop
        }

        [System.Windows.Forms.Application]::EnableVisualStyles()
        $Script:WinForm = New-Object System.Windows.Forms.Form
        [Microsoft.Web.WebView2.WinForms.WebView2] $Script:WebView2 = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $Script:WebView2.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
        $WebView2ProfilePath = $Script:CurrentWebView2Session.WebView2ProfilePath
        if (-not (Test-Path $WebView2ProfilePath -PathType Container)) { New-Item -ItemType Directory -Force -Path $WebView2ProfilePath | Out-Null }
        $Script:WebView2.CreationProperties.UserDataFolder = $WebView2ProfilePath
        $Script:WebView2.CreationProperties.ProfileName = $EdgeProfile
        $Script:Timer = New-Object System.Windows.Forms.Timer

        # Enable InPrivate mode if switch is specified
        if ($InPrivate) {
            Write-Verbose "Enabling InPrivate browsing mode"
            $Script:WebView2.CreationProperties.IsInPrivateModeEnabled = $true
        }

        #https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags
        #$EnvironmentOptions = "--msSingleSignOnOSForPrimaryAccountIsShared"
        #$Script:WebView2.CreationProperties.AdditionalBrowserArguments = $EnvironmentOptions

        $InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState

        $Script:WinForm_Load = {
            try {
                $Script:WinForm.Text = "OmadaWeb.PS - Loading..."
            }
            catch {
                [Console]::WriteLine("Error in WinForm_Load: $_")
            }
        }

        $Script:WebView_SourceChanged = {
            try {
                if ($null -ne $Script:WebView2 -and $null -ne $Script:WebView2.Source -and $null -ne $Script:WinForm) {
                    $Script:WinForm.Text = "OmadaWeb.PS - {0}" -f $Script:WebView2.Source.AbsoluteUri
                }
            }
            catch [System.Management.Automation.PipelineStoppedException] {
                # Ctrl+C was pressed - silently ignore
                return
            }
            catch {
                # Use Console.WriteLine to prevent crashes in event handlers
                [Console]::ForegroundColor = 'Red'
                [Console]::WriteLine("Get-Error in SourceChanged: $_")
                [Console]::ResetColor()
            }
        }

        $Script:WinForm_StateCorrection_Load = {
            try {
                if ($null -ne $Script:WinForm) {
                    $Script:WinForm.WindowState = $InitialFormWindowState
                }
            }
            catch [System.Management.Automation.PipelineStoppedException] {
                # Ctrl+C was pressed - silently ignore
                return
            }
            catch {
                [Console]::ForegroundColor = 'Red'
                [Console]::WriteLine("Error in StateCorrection: $_")
                [Console]::ResetColor()
            }
        }

        $Script:WinForm_Cleanup_FormClosed = {
            try {
                $Script:WebView2.remove_SourceChanged($Script:WebView_SourceChanged)
                $Script:WinForm.remove_Load($Script:WinForm_Load)
                $Script:WinForm.remove_Load($Script:WinForm_StateCorrection_Load)
                $Script:WinForm.remove_FormClosed($Script:WinForm_Cleanup_FormClosed)
            }
            catch { Out-Null <# Prevent PSScriptAnalyzer warning #> }
        }

        $Script:WinForm.SuspendLayout()
        $Script:WinForm.Controls.Add($Script:WebView2)
        $Script:WinForm.AutoScaleDimensions = New-Object System.Drawing.SizeF(6, 13)
        $Script:WinForm.AutoScaleMode = 'Font'
        $Script:WinForm.Dock = 'Fill'
        $Script:WinForm.AutoSize = $true
        $Script:WinForm.Name = 'OmadaWeb.PS Browser Login'
        $Script:WinForm.ShowIcon = $false
        $Script:WinForm.Text = 'OmadaWeb.PS'
        $Script:WinForm.Width = 500
        $Script:WinForm.Height = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height / 1.5
        $Script:WinForm.StartPosition = 'CenterScreen'
        $Script:WinForm.add_Load($Script:WinForm_Load)
        $Script:WinForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $Script:WinForm.MaximizeBox = $false
        $Script:WinForm.MinimizeBox = $false
        $Script:WinForm.Add_Shown({
                param($Sender, $e)
                try {
                    "Start-WebView2Login - Form loaded. Execute Initialize-WebView2" -f $MyInvocation.MyCommand | Write-Verbose
                    $Script:WinForm.Activate()
                    $Script:WebView2.Focus()
                    Initialize-WebView2
                }
                catch {
                    [Console]::ForegroundColor = 'Red'
                    [Console]::WriteLine("Error in Add_Shown: $_")
                    [Console]::ResetColor()
                }
            })
        # $Script:WinForm.add_FormClosing({
        #         param($s, [System.Windows.Forms.FormClosingEventArgs]$e)
        #         switch ($e.CloseReason) {
        #             'UserClosing' { Write-Host 'Closing: user initiated (X/Alt+F4/etc.)' }
        #             'WindowsShutDown' { Write-Host 'Closing: OS shutdown/logoff' }
        #             'TaskManagerClosing' { Write-Host 'Closing: killed by Task Manager' }
        #             'FormOwnerClosing' { Write-Host 'Closing: owner closed' }
        #             'MdiFormClosing' { Write-Host 'Closing: MDI parent closed' }
        #             'ApplicationExitCall' { Write-Host 'Closing: Application.Exit()' }
        #             default { Write-Host "Closing: $($e.CloseReason)" }
        #         }
        #     })
        $Script:WinForm.ResumeLayout()
        ##Save the initial state of the form
        $InitialFormWindowState = $Script:WinForm.WindowState

        ##Init the OnLoad event to correct the initial state of the form
        $Script:WinForm.add_Load($Script:WinForm_StateCorrection_Load)
        ##Clean up the control events

        $Script:WinForm.add_FormClosed($Script:WinForm_Cleanup_FormClosed)

        $Script:WebView2.Location = New-Object System.Drawing.Point(0, 49)
        $Script:WebView2.Name = 'WebView'
        $Script:WebView2.Dock = 'Fill'
        $Script:WebView2.AutoSize = $true
        $Script:WebView2.TabIndex = 0
        $Script:WebView2.ZoomFactor = 1
        $Script:WebView2.add_SourceChanged($Script:WebView_SourceChanged)

        # Single sign-on with the Windows account is what makes the ordinary sign-in instant: WebView2
        # presents the account the machine is logged on with and Entra waves it through. It is also
        # precisely what takes the choice away when that account is the wrong one - which is what an
        # 'AADSTS50178 ... does not exist in tenant' refusal is. So it stays on by default, and is
        # turned off for exactly the sign-ins where the caller has said which account to use, or has
        # asked to be shown the picker.
        $SignInAccount = Get-OmadaSignInAccount -SessionContext $Script:CurrentWebView2Session
        $UseOsPrimaryAccount = [string]::IsNullOrWhiteSpace($SignInAccount.UserName) -and -not $SignInAccount.SelectAccount

        # Create the env once per session and reuse it for all WebView2 instances of that session -
        # a CoreWebView2Environment is bound 1:1 to the UserDataFolder it was created against, so it
        # must be scoped to the same session as the profile folder above.
        #
        # It is also bound to the options it was created with, and those cannot be changed afterwards.
        # A session that signed in once without naming an account and is now asked for a different one
        # would otherwise silently reuse an environment that still signs in with the Windows account,
        # and the parameter the caller passed would do nothing at all.
        $PreviousWebViewEnv = $null
        if ($null -ne $Script:CurrentWebView2Session.WebViewEnv -and $Script:CurrentWebView2Session.WebViewEnvSingleSignOn -ne $UseOsPrimaryAccount) {
            "{0} - Single sign-on with the Windows account is now {1} for this session, which the existing WebView2 environment cannot be told, so a new one is created." -f $MyInvocation.MyCommand, $(if ($UseOsPrimaryAccount) { "wanted" } else { "not wanted" }) | Write-Verbose

            # Kept, not dropped. WebView2 refuses to create a second environment over a user data
            # folder that is still in use with different options, and a browser process from the
            # window that just closed can still be on its way out. Failing the sign-in over that
            # would be the wrong trade: the option only decides whether the Windows account is
            # offered without being asked for, while what actually settles the account is the prompt
            # parameter on the request itself, which is sent either way.
            $PreviousWebViewEnv = $Script:CurrentWebView2Session.WebViewEnv
            $Script:CurrentWebView2Session.WebViewEnv = $null
        }

        if ($null -eq $Script:CurrentWebView2Session.WebViewEnv) {
            "{0} - Creating CoreWebView2Environment (single sign-on with the Windows account: {1})..." -f $MyInvocation.MyCommand, $UseOsPrimaryAccount | Write-Verbose
            $EnvOptions = [Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions]::new()
            $EnvOptions.AllowSingleSignOnUsingOSPrimaryAccount = $UseOsPrimaryAccount
            try {
                "{0} - Try to start CoreWebView2Environment using implicit configuration..." -f $MyInvocation.MyCommand | Write-Verbose
                $Task = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $WebView2ProfilePath, $EnvOptions)
                $Script:CurrentWebView2Session.WebViewEnv = $Task.GetAwaiter().GetResult()
                $Script:CurrentWebView2Session.WebViewEnvSingleSignOn = $UseOsPrimaryAccount
            }
            catch {
                try {
                    "{0} - Failed to start CoreWebView2Environment using implicit configuration, now try explicit Edge WebView path: '{1}'..." -f $MyInvocation.MyCommand, $Script:InstalledEdgeWebView2Path | Write-Verbose
                    $Task = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($Script:InstalledEdgeWebView2Path, $WebView2ProfilePath, $EnvOptions)
                    $Script:CurrentWebView2Session.WebViewEnv = $Task.GetAwaiter().GetResult()
                    $Script:CurrentWebView2Session.WebViewEnvSingleSignOn = $UseOsPrimaryAccount
                }
                catch {
                    if ($null -ne $PreviousWebViewEnv) {
                        # Only the reconfiguration failed. The sign-in itself has an environment to
                        # run in, and the request still carries the parameter that decides the
                        # account, so it goes ahead in the one this session already had.
                        "{0} - Could not create a WebView2 environment with single sign-on {1}, so this sign-in reuses the environment this session already has: {2}" -f $MyInvocation.MyCommand, $(if ($UseOsPrimaryAccount) { "enabled" } else { "disabled" }), $_.Exception.Message | Write-Verbose
                        $Script:CurrentWebView2Session.WebViewEnv = $PreviousWebViewEnv
                    }
                    else {
                        $Script:StopError = $true
                        "{0} - Error creating CoreWebView2Environment. You can consider to install the Evergreen Standalone Installer from 'https://developer.microsoft.com/en-us/Microsoft-edge/webview2/' and try again: {1}" -f $MyInvocation.MyCommand, $_.Exception | Write-Error -ErrorAction Stop
                    }
                }
            }
        }
        if ($null -eq $Script:WebView2.CoreWebView2) {
            "{0} - Initializing WebView2 CoreWebView2..." -f $MyInvocation.MyCommand | Write-Verbose

            $Script:WebView2.Visible = $false

            # Start initialization
            $InitTask = $Script:WebView2.EnsureCoreWebView2Async($Script:CurrentWebView2Session.WebViewEnv)

            # If ForceAuthentication, clear data after initialization
            if ($Script:CurrentWebView2Session.ForceAuthentication -and -not $Script:CurrentWebView2Session.BrowserDataCleared) {
                $InitTask.GetAwaiter().OnCompleted({
                        try {
                            "Start-WebView2Login - WebView2 initialized, clearing browsing data..." | Write-Verbose
                            $ClearTask = $Script:WebView2.CoreWebView2.Profile.ClearBrowsingDataAsync()
                            $ClearTask.GetAwaiter().OnCompleted({
                                    "Start-WebView2Login - Browsing data cleared" | Write-Verbose
                                    $Script:CurrentWebView2Session.BrowserDataCleared = $true
                                })
                        }
                        catch {
                            $Msg = "Error clearing data: $_. This is non-terminating error."
                            [Console]::WriteLine($Msg)
                        }
                    })
            }
        }

        # Disable Ctrl+C handling while form is open avoiding crashing the sessions when CTRL+C is pressed
        if ($ConsoleControlAvailable) {
            "{0} - Disable Ctrl+C handling while form is open avoiding crashing the sessions when CTRL+C is pressed" -f $MyInvocation.MyCommand | Write-Verbose
            [Console]::TreatControlCAsInput = $true
        }

        "{0} - Show WinForm Dialog" -f $MyInvocation.MyCommand | Write-Verbose
        $Script:WinForm.ShowDialog() | Out-Null

        if ($ConsoleControlAvailable) {
            "{0} - Re-enable Ctrl+C." -f $MyInvocation.MyCommand | Write-Verbose
            [Console]::TreatControlCAsInput = $OriginalTreatControlCAsInput
        }

        "{0} - Reset-Timer" -f $MyInvocation.MyCommand | Write-Verbose
        Reset-Timer
        "{0} - Dispose WebView2" -f $MyInvocation.MyCommand | Write-Verbose
        $Script:WebView2.Dispose()
        "{0} - Dispose WinForm" -f $MyInvocation.MyCommand | Write-Verbose
        $Script:WinForm.Dispose()

    }
    catch {
        # The reason travels with the trace, not only with the terminating error. A caller that
        # captures the verbose stream - a scheduled task, a CI job, the sign-in canary - sees only
        # what is written here, and "Error occurred" on its own sent issue #90 looking for a changed
        # Microsoft sign-in page that had nothing to do with it.
        #
        # Read once and redacted once. A failure this deep in a sign-in can quote the request it fell
        # over on, and an authorization request carries an account name in its query string, so the
        # message goes through Protect-LogMessage like every other logged exception message in the
        # module - and both the trace and the console line below say the same redacted thing.
        $SafeErrorMessage = Protect-LogMessage -Message $PSItem.Exception.Message
        "{0} - Error occurred: {1}" -f $MyInvocation.MyCommand, $SafeErrorMessage | Write-Verbose
        try {
            "{0} - Reset-Timer" -f $MyInvocation.MyCommand | Write-Verbose
            Reset-Timer
            "{0} - Dispose WebView2" -f $MyInvocation.MyCommand | Write-Verbose
            $Script:WebView2.Dispose()
            "{0} - Dispose WinForm" -f $MyInvocation.MyCommand | Write-Verbose
            $Script:WinForm.Dispose()
            # $null here means Ctrl+C was never taken over, either because there was no console to
            # take it from or because the failure happened before that point. Either way there is
            # nothing to put back, and writing to the console would throw a second time inside the
            # handler for the first failure.
            if ($ConsoleControlAvailable -and $null -ne $OriginalTreatControlCAsInput) {
                "{0} - Re-enable Ctrl+C." -f $MyInvocation.MyCommand | Write-Verbose
                [Console]::TreatControlCAsInput = $OriginalTreatControlCAsInput
            }
        }
        catch {}
        Write-Host ("Error in Start-WebView2Login: {0}" -f $SafeErrorMessage) -ForegroundColor Red
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}