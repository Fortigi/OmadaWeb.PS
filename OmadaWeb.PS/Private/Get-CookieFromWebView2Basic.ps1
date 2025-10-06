function Get-CookieFromWebView2Basic {

    param(
        [string]$StartUrl = 'https://omada.omada.cloud/test'
    )

    $ErrorActionPreference = 'Stop'

    $DomainFilter = [System.Uri]::New($StartUrl).Host
    $Url = "{0}://{1}" -f [System.Uri]::New($StartUrl).Scheme, [System.Uri]::New($StartUrl).Host



    Install-WebView2
    # }


    try {
        [void][Reflection.Assembly]::LoadFrom($Script:WebView2CorePath)
    }
    catch {
        if ($_.Exception.Message -like '*Assembly with same name is already loaded*') {
            # Ignore
        }
        else {
            throw $_.Exception.Message
        }
    }

    try {
        [void][Reflection.Assembly]::LoadFrom($Script:WebView2WinFormsPath)
    }
    catch {
        if ($_.Exception.Message -like '*Assembly with same name is already loaded*') {
            # Ignore
        }
        else {
            throw $_.Exception.Message
        }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing


    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form


    [Microsoft.Web.WebView2.WinForms.WebView2] $webview = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $webview.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
    $Script:UserAgent = $webview.CoreWebView2.Settings.UserAgent
    $userDataFolder = Join-Path $env:TEMP 'OmadaWebView2Profile'
    if (-not (Test-Path $userDataFolder)) {
        New-Item -ItemType Directory -Force -Path $userDataFolder | Out-Null
    }
    $webview.CreationProperties.UserDataFolder = $userDataFolder
    $webview.CreationProperties.ProfileName = "OmadaWebProfile"

    #https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/webview-features-flags
    $EnvironmentOptions = "--msSingleSignOnForInPrivateWebView2 --disable-features=msWebView2EnableInPrivateWebView2"
    $webview.CreationProperties.AdditionalBrowserArguments = $EnvironmentOptions

    $InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState
    #endregion Generated Form Objects

    #----------------------------------------------
    # User Generated Script
    #----------------------------------------------
    function Initialize-WebView2 {
        param(
            [Microsoft.Web.WebView2.WinForms.WebView2]$WebView
        )

        $WebView.add_CoreWebView2InitializationCompleted({
                param($sender, $e)
                if ($e.IsSuccess) {

                    Write-Host "Timer1" -ForegroundColor Yellow


                    $timer = New-Object System.Windows.Forms.Timer
                    $timer.Interval = 150
                    try {
                        $timer.Start()
                        $timer.Add_Tick({
                                try {
                                    $Script:Task = $webview.CoreWebView2.CookieManager.GetCookiesAsync($null)
                                    $Script:Task.GetAwaiter().OnCompleted({

                                            if ($Script:Task.IsFaulted) {
                                                #$timer.Stop()
                                                $msg = $Script:Task.Exception.InnerException.Message

                                                if (-not $msg) { $msg = $Script:Task.Exception.ToString() }
                                                [System.Windows.Forms.MessageBox]::Show($msg, 'Cookie retrieval failed')
                                                # Set-Status 'Error'
                                            }
                                            elseif ($Script:Task.IsCanceled) {
                                                #$timer.Stop()
                                                # Set-Status 'Canceled'
                                            }
                                            elseif ($Script:Task.IsCompleted) {
                                                #$timer.Stop()
                                                $cookies = $Script:Task.Result

                                                $filter = $DomainFilter.tolower() #($txtDom.Text.Trim()).ToLowerInvariant()
                                                $match = $cookies | Where-Object { ($_.Domain) -and $_.Domain.ToLowerInvariant().EndsWith($filter) }
                                                if (-not $match -or $match.Count -eq 0) {
                                                    [System.Windows.Forms.MessageBox]::Show("No cookies for '*.$filter' found.")
                                                    # Set-Status 'No matching cookies'
                                                    #return
                                                }
                                                $Script:OmadaWebAuthCookie = [pscustomobject]@{}
                                                $Exported = $false
                                                $match | ForEach-Object {

                                                    if (!$Exported -and $_.name -eq 'oisauthtoken') {
                                                        Write-Host "Found oisauthtoken" -ForegroundColor Green
                                                        $Script:UserAgent = $webview.CoreWebView2.Settings.UserAgent
                                                        $Script:OmadaWebAuthCookie = [pscustomobject]@{
                                                            name     = $_.Name
                                                            value    = $_.Value
                                                            domain   = $_.Domain
                                                            path     = $_.Path
                                                            expires  = $exp
                                                            httpOnly = $_.IsHttpOnly
                                                            secure   = $_.IsSecure
                                                            sameSite = $_.SameSite.ToString()
                                                        }
                                                        # Set-Status "Exported oisauthtoken cookie"
                                                        $Exported = $true
                                                    }
                                                }
                                                if ($Exported) {
                                                    $form.Close()
                                                }
                                            }
                                        }
                                    )
                                }
                                catch {
                                    $_
                                }
                            })
                    }
                    catch {
                        # Set-Status "Failed..."
                        $timer.Stop()
                    }

                    if ($OnReady) { & $OnReady }
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("WebView2 init failed: $($e.InitializationException.Message)")
                }
            })
        $null = $WebView.EnsureCoreWebView2Async()
    }
    $form_Load = {
        #TODO: Initialize Form Controls here
        $webview.Source = ([System.Uri]::New($StartUrl))
        $webview.Visible = $true
    }

    $webview_SourceChanged = {
        $form.Text = $webview.Source.AbsoluteUri
    }

    # --End User Generated Script--
    #----------------------------------------------
    #region Generated Events
    #----------------------------------------------


    $Form_StateCorrection_Load =
    {
        #Correct the initial state of the form to prevent the .Net maximized form issue
        $form.WindowState = $InitialFormWindowState
    }

    $Form_Cleanup_FormClosed =
    {
        #Remove all event handlers from the controls
        try {
            $webview.remove_SourceChanged($webview_SourceChanged)
            $form.remove_Load($form_Load)
            $form.remove_Load($Form_StateCorrection_Load)
            $form.remove_FormClosed($Form_Cleanup_FormClosed)
        }
        catch { Out-Null <# Prevent PSScriptAnalyzer warning #> }
    }
    #endregion Generated Events

    #----------------------------------------------
    #region Generated Form Code
    #----------------------------------------------
    $form.SuspendLayout()
    #
    # form1
    #
    $form.Controls.Add($webview)
    $form.AutoScaleDimensions = New-Object System.Drawing.SizeF(6, 13)
    $form.AutoScaleMode = 'Font'
    $form.ClientSize = New-Object System.Drawing.Size(619, 413)
    $form.Name = 'OmadaWeb.PS'
    $form.Text = 'Form'
    $form.Width = 1100
    $form.Height = 800
    $form.StartPosition = 'CenterScreen'
    $form.add_Load($form_Load)
    $form.Add_Shown({
            param($sender, $e)
            Initialize-WebView2 -WebView $webview
        })
    #
    # webview
    #
    $webview.Location = New-Object System.Drawing.Point(0, 49)
    $webview.Name = 'webview'
    $webview.Size = New-Object System.Drawing.Size(619, 364)
    $webview.TabIndex = 0
    $webview.ZoomFactor = 1
    $webview.add_SourceChanged($webview_SourceChanged)

    $form.ResumeLayout()
    #endregion Generated Form Code

    #----------------------------------------------

    #Save the initial state of the form
    $InitialFormWindowState = $form.WindowState
    #Init the OnLoad event to correct the initial state of the form
    $form.add_Load($Form_StateCorrection_Load)
    #Clean up the control events
    $form.add_FormClosed($Form_Cleanup_FormClosed)
    #Show the Form
    $form.ShowDialog()

    $webview.Dispose()
    $form.Dispose()
}