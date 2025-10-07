function Initialize-WebView2 {
    [CmdletBinding()]
    param()

    try {
        Write-Host "`r`nWebview2 opened, please login! Waiting for login." -NoNewline -ForegroundColor Yellow
        $Script:WebView.add_CoreWebView2InitializationCompleted({

                param($sender, $e)

                if ($e.IsSuccess) {

                    $Timer = New-Object System.Windows.Forms.Timer
                    $Timer.Interval = 150
                    $Timer.Start()
                    try {
                        $Timer.Add_Tick({
                                # Use .NET methods only - no PowerShell cmdlets that can throw PipelineStoppedException
                                try {
                                    if ($null -eq $Script:WebView -or $null -eq $Script:WebView.CoreWebView2) {
                                        return
                                    }

                                    # Progress indicator using Console.Write (not Write-Host)
                                    if (-not $Script:ProgressCounter) { $Script:ProgressCounter = 0 }
                                    $Script:ProgressCounter++
                                    if ($Script:ProgressCounter % 3 -eq 0) {
                                        [Console]::Write(".")
                                    }

                                    if ($Script:LastSource -ne $Script:WebView.Source) {
                                        "Initialize-WebView2 - {0}" -f ($Script:WebView.Source | ConvertTo-Json ) | Write-Verbose
                                        $Script:LastSource = $Script:WebView.Source
                                    }

                                    switch ($Script:WebView.Source) {
                                        { $_.Host -eq [System.Uri]::New($Script:OmadaWebBaseUrl).Host } {
                                            Get-WebView2Cookies
                                        }
                                        { $_.Host -eq [System.Uri]::New("https://login.microsoftonline.com").Host } {
                                            #Wait-Debugger
                                            #Invoke-WebView2MicrosoftLogin
                                        }
                                        default {
                                            return
                                        }
                                    }
                                }
                                catch {
                                    # Completely silent - do nothing
                                    # Any exception here (including PipelineStoppedException) is swallowed
                                }
                            })
                    }
                    catch {
                        [Console]::WriteLine("Error: $_")
                        if ($null -ne $Timer -and $Timer.Enabled) {
                            $Timer.Stop()
                        }
                        return
                    }
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("WebView2 init failed: $($e.InitializationException.Message)")
                }
            }

        )

    }
    catch {
        "Error in Initialize-WebView2: {0}" -f $_ | Write-Host  -ForegroundColor Red
        throw
    }
}