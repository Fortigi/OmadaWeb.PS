function Get-WebView2Cookie {
    [CmdletBinding()]
    param()
    try {

        if ( $Script:LastCheckedHost -ne $Script:WebView2.Source.Host) {
            # Diagnostics only: a login redirect URI can carry a token in its query string, so this
            # goes through the redaction walker. A shallow depth is enough for the Uri and avoids
            # walking the WebView2 object graph.
            "{0} - {1}" -f $MyInvocation.MyCommand, (ConvertTo-RedactedLogString -InputObject $Script:WebView2.Source -MaxDepth 3) | Write-Verbose
        }

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
                        [Console]::WriteLine($Script:Task.Exception.InnerException.Message)
                    }
                    else {
                        [Console]::WriteLine( $Script:Task.Exception.ToString())
                    }
                    [System.Windows.Forms.MessageBox]::Show($Message, 'Cookie retrieval failed')
                    return
                }
                elseif ($Script:Task.IsCanceled) {
                }
                elseif ($Script:Task.IsCompleted) {
                    $Cookies = $Script:Task.Result
                    if ($null -eq $Cookies) {
                        return
                    }
                    $Filter = [System.Uri]::New($Script:CurrentWebView2Session.BaseUrl).Host.ToLower()
                    # Wrapped, because Where-Object returns the single object itself when exactly one
                    # cookie matches, and a bare object has no Count for the test below to read.
                    # Under StrictMode that is a terminating error inside this callback, and the
                    # callback's catch only writes "Cookie callback error" to the console - so the
                    # cookie is never exported, the sign-in window never closes, and a sign-in that
                    # actually succeeded hangs until something else times it out.
                    #
                    # One matching cookie is not a corner case: it is what any host that sets only
                    # oisauthtoken produces, which is exactly what the scheduled canary's loopback
                    # stand-in does. It found this (issue #79); the same bug class as #68.
                    $Match = @($Cookies | Where-Object { ($null -ne $_.Domain) -and $_.Domain.ToLowerInvariant().EndsWith($Filter) })
                    $Script:CurrentWebView2Session.AuthCookie = [pscustomobject]@{}
                    $Exported = $false

                    if ($Match.Count -gt 0) {
                        $Match | ForEach-Object {
                            if (!$Exported -and $_.name -eq 'oisauthtoken') {
                                if ( $Script:LastCheckedHost -ne $Script:WebView2.Source.Host) {
                                    "Get-WebView2Cookie - Found oisauthtoken" | Write-Verbose
                                }

                                if (!$Script:UserAgentParameterUsed -and $null -ne $Script:WebView2 -and $null -ne $Script:WebView2.CoreWebView2 -and $null -ne $Script:WebView2.CoreWebView2.Settings) {
                                    $Script:UserAgent = $Script:WebView2.CoreWebView2.Settings.UserAgent
                                }

                                $Script:CurrentWebView2Session.AuthCookie = [pscustomobject]@{
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
                            # Close the WebView form
                            if ($null -ne $Script:WebView2 -and $null -ne $Script:WebView2.FindForm()) {
                                $Script:WebView2.FindForm().Close()
                                $Script:ProgressCounter = 0
                                $Script:LastFiredSecond = -1
                                $Script:OmadaWatchdogStart = $null
                                $Script:OmadaWatchdogRunning = $false
                            }
                        }
                    }
                    if ($Exported) {
                        return
                    }
                    else {
                        if ( $Script:LastCheckedHost -ne $Script:WebView2.Source.Host) {
                            "Get-WebView2Cookie - No oisauthtoken found yet" | Write-Verbose
                        }
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
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}