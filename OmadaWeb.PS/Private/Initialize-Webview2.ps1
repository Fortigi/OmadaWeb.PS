function Initialize-WebView2 {
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'sender', Justification = 'The use of sender is intended here for event handlers.')]
    param()

    try {
        Write-Host "`r`nWebView2 opened, please login! Waiting for login." -NoNewline -ForegroundColor Yellow
        $Script:MicrosoftOnlineLogin = $true

        $Script:WebView2.add_CoreWebView2InitializationCompleted({

                param($sender, $e)

                if ($e.IsSuccess) {

                    $Timer = New-Object System.Windows.Forms.Timer
                    $Timer.Interval = 150
                    $Timer.Start()
                    try {
                        $Timer.Add_Tick({
                                # Use .NET methods only - no PowerShell cmdlets that can throw PipelineStoppedException
                                try {
                                    if ($null -eq $Script:WebView2 -or $null -eq $Script:WebView2.CoreWebView2) {
                                        return
                                    }

                                    # Progress indicator using Console.Write (not Write-Host)
                                    if (-not $Script:ProgressCounter) { $Script:ProgressCounter = 0 }
                                    $Script:ProgressCounter++
                                    if ($Script:ProgressCounter % 3 -eq 0) {
                                        [Console]::ForegroundColor = 'Yellow'
                                        [Console]::Write(".")
                                        [Console]::ResetColor()
                                    }

                                    if ($Script:LastSource -ne $Script:WebView2.Source) {
                                        "Initialize-WebView2 - {0}" -f ($Script:WebView2.Source | ConvertTo-Json ) | Write-Verbose
                                        $Script:LastSource = $Script:WebView2.Source
                                    }
                                    switch ($Script:WebView2.Source) {
                                        { $_.Host -eq [System.Uri]::New($Script:OmadaWebBaseUrl).Host } {
                                            Get-WebView2Cookie
                                        }
                                        { $_.Host -eq [System.Uri]::New("https://login.microsoftonline.com").Host -and $Script:MicrosoftOnlineLogin} {
                                            Invoke-WebView2MicrosoftLogin
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