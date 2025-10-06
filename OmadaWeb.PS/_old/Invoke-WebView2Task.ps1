function Invoke-WebView2Task {
    [CmdLetBinding()]
    param(
        $Webview2Task = $wv.CoreWebView2.CookieManager.GetCookiesAsync($null),
        $ScriptToExecute  ,
        $OnCompletedScriptBlock
    )
    try {

        $Script:Task = $Webview2Task
        $Script:Task.GetAwaiter().OnCompleted({

                if ($Script:Task.IsFaulted) {
                    #$timer.Stop()
                    $msg = $Script:Task.Exception.InnerException.Message

                    if (-not $msg) { $msg = $Script:Task.Exception.ToString() }
                    [System.Windows.Forms.MessageBox]::Show($msg, 'Cookie retrieval failed')
                    Set-Status 'Error'
                    $btnExport.Enabled = $true
                }
                elseif ($Script:Task.IsCanceled) {
                    #$timer.Stop()
                    Set-Status 'Canceled'
                    $btnExport.Enabled = $true
                }
                elseif ($Script:Task.IsCompleted) {

                }
            }

        )

    }
    catch {
        throw $_
    }
}
