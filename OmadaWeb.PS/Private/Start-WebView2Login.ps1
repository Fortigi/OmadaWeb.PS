function Start-WebView2Login {
    <#
    .SYNOPSIS
        Starts a WebView2 login session for Omada Controller.
    .DESCRIPTION
        This function initializes and starts a WebView2 login session for the Omada Controller. It creates a Windows Form with a WebView2 control to facilitate user authentication.
    .EXAMPLE
        Start-WebView2Login
    .NOTES

    #>
    [CmdletBinding()]
    param(
        $EdgeProfile = "Default"
    )

    try {

        $Script:LoginRetryCount++

        [System.Windows.Forms.Application]::EnableVisualStyles()
        $Script:WinForm = New-Object System.Windows.Forms.Form

        [Microsoft.Web.WebView2.WinForms.WebView2] $Script:WebView = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $Script:WebView.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
        $UserDataFolder = Join-Path $env:LOCALAPPDATA 'OmadaWeb.PS\Edge User Data\OmadaWebView2Profile'
        if (-not (Test-Path $UserDataFolder -PathType Container)) {
            New-Item -ItemType Directory -Force -Path $UserDataFolder | Out-Null
        }
        $Script:WebView.CreationProperties.UserDataFolder = $UserDataFolder
        $Script:WebView.CreationProperties.ProfileName = $EdgeProfile

        #https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags
        #$EnvironmentOptions = "--msSingleSignOnOSForPrimaryAccountIsShared"
        #$Script:WebView.CreationProperties.AdditionalBrowserArguments = $EnvironmentOptions

        $InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState

        $Script:WinForm_Load = {
            try {
                if ($null -ne $Script:WebView) {
                    $Script:WebView.Source = ([System.Uri]::New($Script:OmadaWebBaseUrl))
                    $Script:WebView.Visible = $true
                }
            }
            catch {
                [Console]::WriteLine("Error in WinForm_Load: $_")
            }
        }

        $Script:WebView_SourceChanged = {
            try {
                if ($null -ne $Script:WebView -and $null -ne $Script:WebView.Source -and $null -ne $Script:WinForm) {
                    $Script:WinForm.Text = $Script:WebView.Source.AbsoluteUri
                }
            }
            catch [System.Management.Automation.PipelineStoppedException] {
                # Ctrl+C was pressed - silently ignore
                return
            }
            catch {
                # Use Console.WriteLine to prevent crashes in event handlers
                [Console]::WriteLine("Error in SourceChanged: $_")
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
                [Console]::WriteLine("Error in StateCorrection: $_")
            }
        }

        $Script:WinForm_Cleanup_FormClosed = {
            try {
                $Script:WebView.remove_SourceChanged($Script:WebView_SourceChanged)
                $Script:WinForm.remove_Load($Script:WinForm_Load)
                $Script:WinForm.remove_Load($Script:WinForm_StateCorrection_Load)
                $Script:WinForm.remove_FormClosed($Script:WinForm_Cleanup_FormClosed)
            }
            catch { Out-Null <# Prevent PSScriptAnalyzer warning #> }
        }

        $Script:WinForm.SuspendLayout()
        $Script:WinForm.Controls.Add($Script:WebView)
        $Script:WinForm.AutoScaleDimensions = New-Object System.Drawing.SizeF(6, 13)
        $Script:WinForm.AutoScaleMode = 'Font'
        $Script:WinForm.Dock = 'Fill'
        $Script:WinForm.AutoSize = $true
        $Script:WinForm.Name = 'OmadaWeb.PS Login'
        $Script:WinForm.ShowIcon = $false
        $Script:WinForm.Text = 'OmadaWeb.PS Login'
        $Script:WinForm.Width = 440
        $Script:WinForm.Height = 598
        $Script:WinForm.StartPosition = 'CenterScreen'
        $Script:WinForm.add_Load($Script:WinForm_Load)
        $Script:WinForm.Add_Shown({
                param($Sender, $e)
                try {
                    Initialize-WebView2
                }
                catch {
                    [Console]::WriteLine("Error in Add_Shown: $_")
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

        $Script:WebView.Location = New-Object System.Drawing.Point(0, 49)
        $Script:WebView.Name = 'webview'
        $Script:WebView.Dock = 'Fill'
        $Script:WebView.AutoSize = $true
        $Script:WebView.TabIndex = 0
        $Script:WebView.ZoomFactor = 1
        $Script:WebView.add_SourceChanged($Script:WebView_SourceChanged)

        function New-WebView2EnvironmentWithWam {
            param(
                [Parameter(Mandatory)] [string] $UserDataFolder
            )
            $envOpts = [Microsoft.Web.WebView2.Core.CoreWebView2EnvironmentOptions]::new()
            $envOpts.AllowSingleSignOnUsingOSPrimaryAccount = $true


            $task = [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null, $UserDataFolder, $envOpts)
            return $task.GetAwaiter().GetResult()
        }

        $userDataFolder = Join-Path $env:LOCALAPPDATA 'User Data\OmadaWebView2Profile'
        if (-not (Test-Path $userDataFolder)) { New-Item -ItemType Directory -Force -Path $userDataFolder | Out-Null }


        # Create the env once and reuse it for all WebView2 instances in this session
        if ($null -eq $Script:WebViewEnv) {
            $Script:WebViewEnv = New-WebView2EnvironmentWithWam -UserDataFolder $userDataFolder
        }
        if ($Script:WebView.CoreWebView2 -eq $null) {
            $null = $WebView.EnsureCoreWebView2Async($Script:WebViewEnv)
        }


        # Disable Ctrl+C handling while form is open avoiding crashing the sessions when CTRL+C is pressed
        $OriginalTreatControlCAsInput = [Console]::TreatControlCAsInput
        [Console]::TreatControlCAsInput = $true

        $Script:WinForm.ShowDialog() | Out-Null

        [Console]::TreatControlCAsInput = $OriginalTreatControlCAsInput

        $Script:WebView.Dispose()
        $Script:WinForm.Dispose()

    }
    catch {
        try {
            $Script:WebView.Dispose()
            $Script:WinForm.Dispose()
            if ($null -ne $OriginalTreatControlCAsInput) {
                [Console]::TreatControlCAsInput = $OriginalTreatControlCAsInput
            }
        }
        catch {}
        Write-Host "Error in Start-WebView2Login: $_" -ForegroundColor Red
    }
}