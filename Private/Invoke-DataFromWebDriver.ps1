function Invoke-DataFromWebDriver {
    PARAM(
        [string]$EdgeProfile,
        [switch]$InPrivate
    )

    $AuthCookie = $null

    "Opening Edge to retrieve authentication cookie" | Write-Host
    $EdgeDriver = Start-EdgeDriver -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile

    Start-EdgeDriverLogin

    $AgentString = $EdgeDriver.ExecuteScript("return navigator.userAgent")

    Start-Sleep -Seconds 1
    $LoginMessageShown = $false
    do {
        if ($EdgeDriver.url -notlike "*$($Script:OmadaWebBaseUrl)/home*") {
            if (-not $LoginMessageShown) {
                Write-Host "`r`nBrowser opened, please login! Waiting for login." -NoNewline -ForegroundColor Yellow
                $LoginMessageShown = $true
            }

            Write-Host "." -NoNewline -ForegroundColor Yellow
            Start-Sleep -Seconds 1

            if ($null -eq $EdgeDriver -or $null -eq $EdgeDriver.WindowHandles) {
                if ($Script:LoginRetryCount -ge 3) {
                    Close-EdgeDriver
                    "`nLogin retry count exceeded! Please check your credentials as no cookie could be retrieved!" | Write-Error -ErrorAction "Stop"
                }
                else {
                    "`n{0} - Login retry count: {1}" -f $MyInvocation.MyCommand, $Script:LoginRetryCount | Write-Verbose
                }

                "" | Write-Host
                "Edge window seems to be closed before authentication was completed. Re-open Edge driver!" | Write-Host -ForegroundColor Yellow
                $LoginMessageShown = $false
                Close-EdgeDriver
                $EdgeDriver = Start-EdgeDriver -InPrivate:$InPrivate.IsPresent -EdgeProfile $EdgeProfile
                Start-EdgeDriverLogin
                $Script:LoginRetryCount++
            }
        }
        else {
            $AuthCookie = $EdgeDriver.Manage().Cookies.AllCookies | Where-Object { $_.Name -eq 'oisauthtoken' }
        }
    }
    until($null -ne $AuthCookie)
    "{0} (Line {1}): {2}" -f $MyInvocation.MyCommand, $MyInvocation.ScriptLineNumber, $$ | Write-Verbose

    Close-EdgeDriver
    if ($null -ne $AuthCookie) {
        $Script:LoginRetryCount = 0
        return $AuthCookie, $AgentString
    }
    else {
        "Could not authenticate to '{0}" -f $Script:OmadaWebBaseUrl | Write-Error -ErrorAction "Stop"
    }
}