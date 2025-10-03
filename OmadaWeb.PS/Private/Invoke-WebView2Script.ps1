function Invoke-WebView2Script {
    <#
    .SYNOPSIS
    Executes JavaScript in the WebView2.

    .PARAMETER Script
    The JavaScript code to execute.
    #>

    [CmdletBinding()]
    param(
        $ScriptToExecute  ,
        $OnCompletedScriptBlock
    )
    try {

        $Script:Task = $wv.CoreWebView2.CookieManager.GetCookiesAsync($null)
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
                    #$timer.Stop()
                    $cookies = $Script:Task.Result

                    $filter = $DomainFilter.tolower() #($txtDom.Text.Trim()).ToLowerInvariant()
                    $match = $cookies | Where-Object { ($_.Domain) -and $_.Domain.ToLowerInvariant().EndsWith($filter) }
                    if (-not $match -or $match.Count -eq 0) {
                        [System.Windows.Forms.MessageBox]::Show("No cookies for '*.$filter' found.")
                        Set-Status 'No matching cookies'
                        $btnExport.Enabled = $true
                        return
                    }

                    $outDir = Split-Path -Parent $PSCommandPath; if (-not $outDir) { $outDir = (Get-Location).Path }
                    $cookiesPath = Join-Path $outDir 'cookies.json'
                    $headerPath = Join-Path $outDir 'cookie-header.txt'

                    $cookieHeader = ($match | ForEach-Object { "{0}={1}" -f $_.Name, $_.Value }) -join '; '
                    $Exported = $false
                    $match | ForEach-Object {

                        if (!$Exported -and $_.name -eq 'oisauthtoken') {
                            Write-Host "Found oisauthtoken" -ForegroundColor Green


                            $exp = $_.Expires
                            [pscustomobject]@{
                                name = $_.Name; value = $_.Value; domain = $_.Domain; path = $_.Path; expires = $exp
                                httpOnly = $_.IsHttpOnly; secure = $_.IsSecure; sameSite = $_.SameSite.ToString()
                            } | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $cookiesPath
                            $cookieHeader | Set-Content -Encoding UTF8 $headerPath
                            Set-Status "Exported $($match.Count) cookies -> $cookiesPath, $headerPath"
                            $Exported = $true
                            #$btnExport.Enabled = $true
                        }
                    }
                    if ($Exported) {
                        "Cookie export complete. Exiting in 5 seconds..." | Write-Host -ForegroundColor Green
                        Start-Sleep -Seconds 5
                        $form.Close()
                    }
                }
            }

        )

    }
    catch {
        $_.Exception.Message | Write-LogOutput -LogType ERROR
    }
}
