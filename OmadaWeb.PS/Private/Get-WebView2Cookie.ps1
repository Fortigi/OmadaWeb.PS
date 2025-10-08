function Get-WebView2Cookie {
    [CmdletBinding()]
    param()
    try {
        "{0} - {1}" -f $MyInvocation.MyCommand, ($Script:WebView2.Source | ConvertTo-Json ) | Write-Verbose

        if ($null -eq $Script:WebView2.CoreWebView2.CookieManager) {
            return
        }

        $Script:Task = $Script:WebView2.CoreWebView2.CookieManager.GetCookiesAsync($null)

        if ($null -eq $Script:Task) {
            return
        }

        $ScriptBlock = {
            try {
                if ($Script:Task.IsFaulted) {
                    $Message = if ($Script:Task.Exception.InnerException) {
                        $Script:Task.Exception.InnerException.Message
                    }
                    else {
                        $Script:Task.Exception.ToString()
                    }
                    [System.Windows.Forms.MessageBox]::Show($Message, 'Cookie retrieval failed')
                }
                elseif ($Script:Task.IsCanceled) {
                }
                elseif ($Script:Task.IsCompleted) {
                    $Cookies = $Script:Task.Result
                    if ($null -eq $Cookies) {
                        return
                    }
                    $Filter = [System.Uri]::New($Script:OmadaWebBaseUrl).Host.ToLower()
                    $Match = $Cookies | Where-Object { ($null -ne $_.Domain) -and $_.Domain.ToLowerInvariant().EndsWith($Filter) }
                    $Script:OmadaWebAuthCookie = [pscustomobject]@{}
                    $Exported = $false

                    if ($Match -and $Match.Count -gt 0) {
                        $Match | ForEach-Object {
                            if (!$Exported -and $_.name -eq 'oisauthtoken') {
                                "Get-WebView2Cookie - Found oisauthtoken" | Write-Verbose

                                if ($null -ne $Script:WebView2 -and $null -ne $Script:WebView2.CoreWebView2 -and $null -ne $Script:WebView2.CoreWebView2.Settings) {
                                    $Script:UserAgent = $Script:WebView2.CoreWebView2.Settings.UserAgent
                                }

                                $Script:OmadaWebAuthCookie = [pscustomobject]@{
                                    name     = $_.Name
                                    value    = $_.Value
                                    domain   = $_.Domain
                                    path     = $_.Path
                                    expires  = $_.Expires
                                    httpOnly = $_.IsHttpOnly
                                    secure   = $_.IsSecure
                                    sameSite = $_.SameSite.ToString()
                                }
                                $Exported = $true
                            }
                        }
                        if ($Exported) {
                            # if ($null -ne $Timer -and $Timer.Enabled) {
                            #     $Timer.Stop()
                            # }
                            # Close the WebView form
                            if ($null -ne $Script:WebView2 -and $null -ne $Script:WebView2.FindForm()) {
                                $Script:WebView2.FindForm().Close()
                            }
                        }
                    }
                    if ($Exported) {
                        # if ($null -ne $Timer -and $Timer.Enabled) {
                        #     $Timer.Stop()
                        # }
                        return
                    }
                }
            }
            catch [System.Management.Automation.PipelineStoppedException] {
                # Ctrl+C was pressed - silently ignore
                [Console]::WriteLine("PipelineStoppedException")
                return
            }
            catch {
                # Silently catch to prevent crash - log to console
                [Console]::WriteLine("Cookie callback error: $_")
            }
        }
        $Script:Task.GetAwaiter().OnCompleted($ScriptBlock)
    }
    catch {
        Write-Host "Error in Initialize-WebView2: $_" -ForegroundColor Red
        throw
    }
}