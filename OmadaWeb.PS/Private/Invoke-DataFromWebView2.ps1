function Invoke-DataFromWebView2 {
    [CmdletBinding()]
    param(
        [string]$EdgeProfile = "Default",
        [switch]$InPrivate
    )

    "{0} - Invoking data from WebView2" -f $MyInvocation.MyCommand | Write-Host

    if (!(Install-WebView2)) {
        "WebView2 Runtime could not be installed! Cannot continue." | Write-Error -ErrorAction "Stop"
    }
    $Script:LoginRetryCount = 0

    Add-ReflectionAssembly -Object $Script:WebView2CorePath
    Add-ReflectionAssembly -Object $Script:WebView2WinFormsPath
    Add-ReflectionAssembly -Object "System.Drawing" -Type LoadWithPartialName
    Add-ReflectionAssembly -Object "System.Windows.Forms" -Type LoadWithPartialName
    do {
        try {
            $Script:LoginRetryCount++

            if ($Script:StopError) {
                $PSCmdlet.ThrowTerminatingError($PSItem)
            }

            if ($Script:LoginRetryCount -gt 3) {
                "`nLogin try count exceeded! Cannot continue!" | Write-Error -ErrorAction "Stop" -Category AuthenticationError
            }

            "`n{0} - Login try {1} of max {2}" -f $MyInvocation.MyCommand, $Script:LoginRetryCount, $Script:MaxLoginRetries | Write-Verbose

            if ($null -eq $Script:OmadaWebAuthCookie -or ($Script:OmadaWebAuthCookie -is [PSCustomObject] -and ($Script:OmadaWebAuthCookie.PsObject.Properties | Measure-Object).Count -eq 0)) {
                if ($Script:LoginRetryCount -le 1) {
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
                    "`n{0} - Login try count: {1}" -f $MyInvocation.MyCommand, $Script:LoginRetryCount | Write-Verbose
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
    until(($null -ne $Script:OmadaWebAuthCookie -and ($Script:OmadaWebAuthCookie -is [PSCustomObject] -and ($Script:OmadaWebAuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) -or $Script:LoginRetryCount -ge 3)

    if ($null -ne $Script:OmadaWebAuthCookie -and ($Script:OmadaWebAuthCookie -is [PSCustomObject] -and ($Script:OmadaWebAuthCookie.PsObject.Properties | Measure-Object).Count -gt 0)) {
        $Script:LoginRetryCount = 0
    }
    else {
        "Could not authenticate to '{0}" -f $Script:OmadaWebBaseUrl | Write-Error -ErrorAction "Stop"
    }
}