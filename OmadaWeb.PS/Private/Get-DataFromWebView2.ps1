function Get-DataFromWebView2 {
    [CmdletBinding()]
    param(
        [string]$EdgeProfile = "Default",
        [switch]$InPrivate
    )

    try {
        "{0} - Invoking data from WebView2" -f $MyInvocation.MyCommand | Write-Verbose

        if (!(Install-WebView2)) {
            "WebView2 Runtime could not be installed! Cannot continue." | Write-Error -ErrorAction "Stop"
        }

        # The blocking WinForm/WebView2 dialog and its event-handler closures cannot see this call
        # stack, so the session driving this login is bridged through this script-scope pointer.
        $Script:CurrentWebView2Session = $SessionContext
        $Script:CurrentWebView2Session.LoginRetryCount = 0

        Add-ReflectionAssembly -Object $Script:WebView2CorePath
        Add-ReflectionAssembly -Object $Script:WebView2WinFormsPath
        Add-ReflectionAssembly -Object "System.Drawing" -Type LoadWithPartialName
        Add-ReflectionAssembly -Object "System.Windows.Forms" -Type LoadWithPartialName
        do {
            try {
                $Script:CurrentWebView2Session.LoginRetryCount++

                if ($Script:StopError) {
                    $Script:CurrentWebView2Session.LoginRetryCount = 0
                    break
                }

                if ($Script:CurrentWebView2Session.LoginRetryCount -gt 3) {
                    "`nLogin try count exceeded! Cannot continue!" | Write-Error -ErrorAction "Stop" -Category AuthenticationError
                }

                "`n{0} - Login try {1} of max {2}" -f $MyInvocation.MyCommand, $Script:CurrentWebView2Session.LoginRetryCount, $Script:MaxLoginRetries | Write-Verbose

                if ($null -eq $Script:CurrentWebView2Session.AuthCookie -or ($Script:CurrentWebView2Session.AuthCookie -is [PSCustomObject] -and ($Script:CurrentWebView2Session.AuthCookie.PsObject.Properties | Measure-Object).Count -eq 0)) {
                    if ($Script:CurrentWebView2Session.LoginRetryCount -le 1) {
                        try {
                            Start-WebView2Login -EdgeProfile $EdgeProfile -InPrivate:$InPrivate
                        }
                        catch {
                            $PSCmdlet.ThrowTerminatingError($PSItem)
                        }
                    }
                    else {
                        "`nWebView2 was unable to complete the process to retrieve a cookie. Re-open WebView2 in 2 seconds!" | Write-Host -ForegroundColor Yellow
                        Start-Sleep -Seconds 2
                        "`n{0} - Login try count: {1}" -f $MyInvocation.MyCommand, $Script:CurrentWebView2Session.LoginRetryCount | Write-Verbose
                        try {
                            Start-WebView2Login -EdgeProfile $EdgeProfile -InPrivate:$InPrivate
                        }
                        catch {
                            $PSCmdlet.ThrowTerminatingError($PSItem)
                        }
                    }
                }
                else {
                    "{0} - Existing authentication cookie found" -f $MyInvocation.MyCommand | Write-Verbose
                }
            }
            catch {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }
        }
        until(($null -ne $Script:CurrentWebView2Session.AuthCookie -and ($Script:CurrentWebView2Session.AuthCookie -is [PSCustomObject] -and ($Script:CurrentWebView2Session.AuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) -or $Script:CurrentWebView2Session.LoginRetryCount -ge 3)

        if ($null -ne $Script:CurrentWebView2Session.AuthCookie -and ($Script:CurrentWebView2Session.AuthCookie -is [PSCustomObject] -and ($Script:CurrentWebView2Session.AuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) {
            $Script:CurrentWebView2Session.LoginRetryCount = 0
        }
        else {
            "Could not authenticate to '{0}'" -f $Script:CurrentWebView2Session.BaseUrl | Write-Error -ErrorAction "Stop"
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($PSItem)
    }
}
