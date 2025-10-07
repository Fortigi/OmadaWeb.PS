function Initialize-WebView2Helper {
    param([Microsoft.Web.WebView2.WinForms.WebView2]$Control, [scriptblock]$OnReady)
    #Wait-Debugger
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

                $uriText = $StartUrl
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