function Start-WebView2Login {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'e', Justification = 'The use of e is intended here for event handlers.')]
    param(
        [string]$EdgeProfile = "Default",
        [switch]$InPrivate
    )

    try {
        "{0} - Starting WebView2 login" -f $MyInvocation.MyCommand | Write-Verbose

        $Script:LoginRetryCount++

        [System.Windows.Forms.Application]::EnableVisualStyles()
        $Script:WinForm = New-Object System.Windows.Forms.Form
        [Microsoft.Web.WebView2.WinForms.WebView2] $Script:WebView2 = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $Script:WebView2.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
        if (-not (Test-Path $Script:WebView2UserProfilePath -PathType Container)) { New-Item -ItemType Directory -Force -Path $Script:WebView2UserProfilePath | Out-Null }
        $Script:WebView2.CreationProperties.UserDataFolder = $Script:WebView2UserProfilePath
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

        # Create the env once and reuse it for all WebView2 instances in this session
        if ($null -eq $Script:WebViewEnv) {
            $EnvOptions = [Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions]::new()
            $EnvOptions.AllowSingleSignOnUsingOSPrimaryAccount = $true
            $Task = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $Script:WebView2UserProfilePath, $EnvOptions)
            $Script:WebViewEnv = $Task.GetAwaiter().GetResult()
        }
        if ($null -eq $Script:WebView2.CoreWebView2) {
            "{0} - Initializing WebView2 CoreWebView2..." -f $MyInvocation.MyCommand | Write-Verbose

            $Script:WebView2.Visible = $false

            # Start initialization
            $InitTask = $Script:WebView2.EnsureCoreWebView2Async($Script:WebViewEnv)

            # If ForceAuthentication, clear data after initialization
            if ($Script:ForceAuthentication -and -not $Script:BrowserDataCleared) {
                $InitTask.GetAwaiter().OnCompleted({
                        try {
                            "Start-WebView2Login - WebView2 initialized, clearing browsing data..." -f $MyInvocation.MyCommand | Write-Verbose
                            $ClearTask = $Script:WebView2.CoreWebView2.Profile.ClearBrowsingDataAsync()
                            $ClearTask.GetAwaiter().OnCompleted({
                                    "Start-WebView2Login - Browsing data cleared" -f $MyInvocation.MyCommand | Write-Verbose
                                    $Script:BrowserDataCleared = $true
                                })
                        }
                        catch {
                            [Console]::WriteLine("Error clearing data: $_")
                        }
                    })
            }
        }

        # Disable Ctrl+C handling while form is open avoiding crashing the sessions when CTRL+C is pressed
        $OriginalTreatControlCAsInput = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true

        $Script:WinForm.ShowDialog() | Out-Null

        [Console]::TreatControlCAsInput = $OriginalTreatControlCAsInput

        Reset-Timer
        $Script:WebView2.Dispose()
        $Script:WinForm.Dispose()

    }
    catch {
        try {
            Reset-Timer
            $Script:WebView2.Dispose()
            $Script:WinForm.Dispose()
            if ($null -ne $OriginalTreatControlCAsInput) {
                [Console]::TreatControlCAsInput = $OriginalTreatControlCAsInput
            }
        }
        catch {}
        Write-Host "Error in Start-WebView2Login: $_" -ForegroundColor Red
    }
}