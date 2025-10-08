function Invoke-BrowserAuthentication {
    [CmdletBinding()]
    param()

    "{0} - Set Browser authentication" -f $MyInvocation.MyCommand | Write-Verbose

    if ($BoundParams.ForceAuthentication) {
        $Script:OmadaWebAuthCookie = $null
    }
    $Script:Credential = $null
    if ($BoundParams.keys -contains "Credential") {
        $Script:Credential = $BoundParams.Credential
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

    if ($null -ne $($Script:OmadaWebAuthCookie) -and ([System.Uri]::New($Script:OmadaWebBaseUrl).host -eq $($Script:OmadaWebAuthCookie.domain))) {
        "{0} - Using existing cookie for this domain: {1}" -f $MyInvocation.MyCommand, $Script:OmadaWebBaseUrl | Write-Verbose
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

        # Check if WebView2 should be used instead of Selenium
        $UseWebView2 = $false
        if ($BoundParams.ContainsKey('UseWebView2') -and $BoundParams.UseWebView2) {
            $UseWebView2 = $true
        }
        elseif ($Script:PreferWebView2 -eq $true) {
            $UseWebView2 = $true
        }

        if ($UseWebView2) {
            "{0} - Using WebView2 for authentication" -f $MyInvocation.MyCommand | Write-Verbose
            Invoke-DataFromWebView2 -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
            $BrowserData = @($Script:OmadaWebAuthCookie, $Script:UserAgent)
        }
        else {
            "{0} - Using Selenium WebDriver for authentication" -f $MyInvocation.MyCommand | Write-Verbose
            $BrowserData = Invoke-DataFromWebDriver -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
        }

        $Script:OmadaWebAuthCookie = $BrowserData[0]
        $BoundParams.UserAgent = $BrowserData[1]
        $Session.UserAgent = $BrowserData[1]

        if ("Cookie" -notin $BoundParams.Headers.Keys) {
            $BoundParams.Headers.Add("Cookie", ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "="))
        }
        else {
            $BoundParams.Headers.Cookie = ($($Script:OmadaWebAuthCookie).Name, $($Script:OmadaWebAuthCookie).Value -join "=")
        }
        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($Script:OmadaWebAuthCookie.Value), "/", $($Script:OmadaWebAuthCookie.domain))))
    }

    if (![string]::IsNullOrEmpty($($BoundParams.CookiePath))) {
        $CookiePath = (Join-Path $($BoundParams.CookiePath) -ChildPath ("{0}.cookie" -f $Script:OmadaWebAuthCookie.domain))
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $Script:OmadaWebAuthCookie
        }

        try {
            $CookieObject | Export-Clixml $CookiePath -Force
            "Cookie file exported to: {0}" -f $CookiePath | Write-Verbose
        }
        catch [System.UnauthorizedAccessException] {
            "Unable to export the cookie file due insufficient permissions in folder {0}" -f $($BoundParams.CookiePath) | Write-Warning
        }
        catch {
            throw
        }
    }
    elseif ($BoundParams.Keys -notcontains "SkipCookieCache") {
        "{0} - Caching encrypted cookie" -f $MyInvocation.MyCommand | Write-Verbose
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $Script:OmadaWebAuthCookie
        }
        $CookieCliXmlContent = [System.Management.Automation.PSSerializer]::Serialize($CookieObject, [int]::MaxValue)
        $SecureCookieCliXml = ConvertTo-SecureString -String $CookieCliXmlContent -AsPlainText -Force
        try {
            $SecureCookieCliXml | Export-Clixml -Path $Script:CookieCacheFilePath -Force
            "{0} - Updated encrypted cookie cache: {1}" -f $MyInvocation.MyCommand, $Script:CookieCacheFilePath | Write-Verbose
        }
        catch [System.UnauthorizedAccessException] {
            "Unable to cache cookie due insufficient permissions to the temp folder" | Write-Warning
        }
        catch {
            throw
        }
    }
}
