function Invoke-BrowserAuthentication {

    "{0} - Set Browser authentication" -f $MyInvocation.MyCommand | Write-Verbose

    if ($BoundParams.ForceAuthentication) {
        $Script:OmadaWebAuthCookie = $null
    }
    switch ($Script:LastSessionType) {
        { $_ -eq "Normal" -and $($BoundParams.InPrivate).IsPresent -eq $true } {
            "{0} - Reset OmadaWebAuthCookie because session has changed to InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $Script:OmadaWebAuthCookie = $null
            $Script:LastSessionType = "InPrivate"
        }
        { $_ -eq "InPrivate" -and $($BoundParams.InPrivate).IsPresent -eq $false } {
            "{0} - Reset OmadaWebAuthCookie because session has changed from InPrivate to not InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $Script:OmadaWebAuthCookie = $null
            $Script:LastSessionType = "Normal"
        }
        default {}
    }

    if ($null -ne $($Script:OmadaWebAuthCookie) -and ($Script:OmadaWebBaseUrl -like "*$($Script:OmadaWebAuthCookie.domain)*" )) {
        "{0} - OmadaWebAuthCookie exists for this domain: {1}" -f $MyInvocation.MyCommand, $Script:OmadaWebBaseUrl | Write-Verbose
        if ("Cookie" -notin $BoundParams.Headers.Keys) {
            $BoundParams.Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
        }
        else {
            $BoundParams.Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
        }
        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
    }
    else {
        "{0} - OmadaWebAuthCookie not exists or is for different domain. Need to authenticate!" -f $MyInvocation.MyCommand | Write-Verbose
        $EdgeDriverData = Invoke-DataFromWebDriver -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
        $Script:OmadaWebAuthCookie = $EdgeDriverData[0]

        $BoundParams.UserAgent = $EdgeDriverData[1]

        $Session.UserAgent = $EdgeDriverData[1]

        if ("Cookie" -notin $BoundParams.Headers.Keys) {
            $BoundParams.Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
        }
        else {
            $BoundParams.Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
        }

        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
    }
    if (![string]::IsNullOrEmpty($($BoundParams.OmadaWebAuthCookieExportLocation))) {
        "Exporting cookie to {0}" -f $($BoundParams.OmadaWebAuthCookieExportLocation) | Write-Verbose
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $Script:OmadaWebAuthCookie
        }
        $CookieObject | Export-Clixml (Join-Path $($BoundParams.OmadaWebAuthCookieExportLocation) -ChildPath ("{0}.cookie" -f $Script:OmadaWebAuthCookie.domain)) -Force
    }
}