function Get-CookieFromWebView2Basic {

    param(
        [string]$StartUrl = 'https://omada.omada.cloud/test',
        [string]$DomainFilter = 'omada.omada.cloud'
    )

    $ErrorActionPreference = 'Stop'

    $DomainFilter = [System.Uri]::New($StartUrl).Host
    $Url = "{0}://{1}" -f [System.Uri]::New($StartUrl).Scheme, [System.Uri]::New($StartUrl).Host

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # function Find-WebView2Assemblies {
    #     $base = Join-Path $PSScriptRoot "OmadaWeb.PS"
    #     $candidates = Get-ChildItem -Path $base -Recurse -Include 'Microsoft.Web.WebView2.WinForms.dll' -ErrorAction SilentlyContinue | Sort-Object ProductVersion -Descending | Select-Object -First 1
    #     if (-not $candidates) { return $null }

    #     foreach ($wf in $candidates) {
    #         $corePeer = Join-Path (Split-Path $wf.fullname) 'Microsoft.Web.WebView2.Core.dll'
    #         if (Test-Path $corePeer) {
    #             return [pscustomobject]@{
    #                 WinForms = $wf.FullName
    #                 Core     = $corePeer
    #             }
    #         }
    #     }
    #     return $null
    # }

    # $wv2 = Find-WebView2Assemblies
    # if (-not $wv2) {
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


    #$WebView2Type = [Microsoft.Web.WebView2.WinForms.WebView2]

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Omada Cookie Grabber (WebView2, PowerShell)'
    $form.Width = 1100
    $form.Height = 800
    $form.StartPosition = 'CenterScreen'

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = 'Top'
    $panel.Height = 44


    $wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
    $wv.Dock = 'Fill'

    $status = New-Object System.Windows.Forms.StatusStrip
    $lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
    $lblStatus.Text = 'Ready.'
    $status.Items.Add($lblStatus) | Out-Null

    $form.Controls.Add($wv)
    $form.Controls.Add($panel)
    $form.Controls.Add($status)

    function Initialize-WebView2 {
        param([Microsoft.Web.WebView2.WinForms.WebView2]$Control, [scriptblock]$OnReady)

        if ($Control.CoreWebView2 -ne $null) { & $OnReady; return }
        $userDataFolder = Join-Path $env:TEMP 'OmadaWebView2Profile'
        if (-not (Test-Path $userDataFolder)) { New-Item -ItemType Directory -Force -Path $userDataFolder | Out-Null }
        # Use CreationProperties to set UserDataFolder before async init (best practice for WinForms)
        $props = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
        $props.UserDataFolder = $userDataFolder
        $Control.CreationProperties = $props
        $Control.add_CoreWebView2InitializationCompleted({
                param($sender, $e)
                if ($e.IsSuccess) {

                    $uriText = $Url
                    if (-not [Uri]::IsWellFormedUriString($uriText, [UriKind]::Absolute)) { [System.Windows.Forms.MessageBox]::Show('Invalid URL'); return }
                    $wv.Source = [Uri]$uriText
                    Set-Status "Navigating to $uriText ..."
                    Write-Host "Timer1" -ForegroundColor Yellow

                    $timer = New-Object System.Windows.Forms.Timer
                    $timer.Interval = 150
                    try {

                        $timer.Start()
                        $timer.Add_Tick({
                                Set-Status "Add_Tick..."
                                Invoke-ExecuteScriptAsync
                            })
                    }
                    catch {
                        Set-Status "Failed..."
                        $timer.Stop()
                    }

                    if ($OnReady) { & $OnReady }
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("WebView2 init failed: $($e.InitializationException.Message)")
                }
            })
        $null = $Control.EnsureCoreWebView2Async()
    }

    function Set-Status { param([string]$t) $lblStatus.Text = $t }
    $Cookie = [pscustomobject]@{}

    function Invoke-ExecuteScriptAsync {
        [CmdLetBinding()]
        param(
            $ScriptToExecute,
            $OnCompletedScriptBlock
        )
        try {

            $Script:Task = $wv.CoreWebView2.CookieManager.GetCookiesAsync($null)
            $Cookie = $Script:Task.GetAwaiter().OnCompleted({

                    if ($Script:Task.IsFaulted) {
                        $msg = $Script:Task.Exception.InnerException.Message

                        if (-not $msg) { $msg = $Script:Task.Exception.ToString() }
                        [System.Windows.Forms.MessageBox]::Show($msg, 'Cookie retrieval failed')
                        Set-Status 'Error'
                        $btnExport.Enabled = $true
                    }
                    elseif ($Script:Task.IsCanceled) {
                        Set-Status 'Canceled'
                        $btnExport.Enabled = $true
                    }
                    elseif ($Script:Task.IsCompleted) {
                        $cookies = $Script:Task.Result

                        $filter = $DomainFilter.tolower() #($txtDom.Text.Trim()).ToLowerInvariant()
                        $match = $cookies | Where-Object { ($_.Domain) -and $_.Domain.ToLowerInvariant().EndsWith($filter) }
                        if (-not $match -or $match.Count -eq 0) {
                            [System.Windows.Forms.MessageBox]::Show("No cookies for '*.$filter' found.")
                            Set-Status 'No matching cookies'
                            $btnExport.Enabled = $true
                            return $Cookie
                        }

                        $Exported = $false
                        $match | ForEach-Object {

                            if (!$Exported -and $_.name -eq 'oisauthtoken') {
                                Write-Host "Found oisauthtoken" -ForegroundColor Green


                                $exp = $_.Expires
                                $Cookie = [pscustomobject]@{
                                    name     = $_.Name;
                                    value    = $_.Value;
                                    domain   = $_.Domain;
                                    path     = $_.Path;
                                    expires  = $exp;
                                    httpOnly = $_.IsHttpOnly;
                                    secure   = $_.IsSecure;
                                    sameSite = $_.SameSite.ToString()
                                }
                                Set-Status "Cookies found $($match.Count)"
                                $Exported = $true
                                #$btnExport.Enabled = $true
                            }
                        }
                        if ($Exported) {
                            "Cookie export complete. Exiting in 5 seconds..." | Write-Host -ForegroundColor Green
                            Start-Sleep -Seconds 2
                            $form.Close()
                            return $Cookie
                        }
                    }
                }

            )

        }
        catch {
            $_.Exception.Message | Write-LogOutput -LogType ERROR
        }
    }


    $form.Add_Shown({
            Initialize-WebView2 -Control $wv -OnReady {
                $uriText = $null #$txtUrl.Text.Trim()
                if ([string]::IsNullOrWhiteSpace($uriText)) { $uriText = $Url }
                if (-not [Uri]::IsWellFormedUriString($uriText, [UriKind]::Absolute)) { return }
                $wv.Source = [Uri]$uriText
                Set-Status "Navigating to $uriText ..."
            }
        })

    $wv.add_SourceChanged({
            param($s, $e)
            $wv.Source | ConvertTo-Json | Write-Host
            if ($wv.Source) {
                $url = $wv.Source.AbsoluteUri
                Set-Status "SourceChanged → $url"
            }
        })

    $wv.add_WebMessageReceived({
            param($s, $e)
            try {
                $msg = [System.Text.Json.JsonDocument]::Parse($e.WebMessageAsJson)
                $msg | ConvertTo-Json | Write-Host
            }
            catch {
                Set-Status "Msg parse error: $($_.Exception.Message)"
            }
        })

    [System.Windows.Forms.Application]::EnableVisualStyles()
    [System.Windows.Forms.Application]::Run($form)
    $AgentString = $wv.CoreWebView2.Settings.UserAgent
    $wv.Dispose()
    $form.Dispose()
    return $Cookie, $AgentString
}