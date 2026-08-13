function Invoke-BrowserAuthentication {
    [CmdletBinding()]
    param()

    "{0} - Set Browser authentication" -f $MyInvocation.MyCommand | Write-Verbose

    if ($BoundParams.ForceAuthentication) {
        "{0} - ForceAuthentication used. Reset OmadaWebAuthCookie and reset Browser authentication engine to default" -f $MyInvocation.MyCommand | Write-Verbose
        $SessionContext.AuthCookie = $null
        $SessionContext.WebView2Used = $false
        $SessionContext.ForceAuthentication = $true
    }
    $SessionContext.Credential = $null
    if ($BoundParams.keys -contains "Credential") {
        $SessionContext.Credential = $BoundParams.Credential
    }
    switch ($SessionContext.LastSessionType) {
        { $_ -eq "Normal" -and $($BoundParams.InPrivate).IsPresent -eq $true } {
            "{0} - Reset OmadaWebAuthCookie because session has changed to InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $SessionContext.AuthCookie = $null
            $SessionContext.LastSessionType = "InPrivate"
        }
        { $_ -eq "InPrivate" -and $($BoundParams.InPrivate).IsPresent -eq $false } {
            "{0} - Reset OmadaWebAuthCookie because session has changed from InPrivate to not InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $SessionContext.AuthCookie = $null
            $SessionContext.LastSessionType = "Normal"
        }
        default {}
    }

    if ($null -ne $($SessionContext.AuthCookie) -and ([System.Uri]::New($SessionContext.BaseUrl).host -eq $($SessionContext.AuthCookie.domain))) {
        "{0} - Using existing cookie for this domain: {1}" -f $MyInvocation.MyCommand, $SessionContext.BaseUrl | Write-Verbose
        if ("Cookie" -notin $BoundParams.Headers.Keys) {
            $BoundParams.Headers.Add("Cookie", ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "="))
        }
        else {
            $BoundParams.Headers.Cookie = ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "=")
        }
        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($SessionContext.AuthCookie.Value), "/", $($SessionContext.AuthCookie.domain))))
    }
    else {
        "{0} - OmadaWebAuthCookie not exists or is for different domain. Need to authenticate!" -f $MyInvocation.MyCommand | Write-Verbose

        # Check if WebView2 should be used instead of Selenium
        $WebView2Authentication = $false
        if (($BoundParams.ContainsKey('UseWebView2') -and $BoundParams.UseWebView2) -or $BoundParams.AuthenticationType -eq "WebView2") {
            "{0} - UseWebView2 parameter used" -f $MyInvocation.MyCommand | Write-Verbose
            if ($BoundParams.ContainsKey('UseWebView2') -and $BoundParams.UseWebView2) {
                "Parameter UseWebView2 is deprecated, please use AuthenticationType WebView2' instead." | Write-Warning
            }
            $WebView2Authentication = $true
        }
        elseif ($SessionContext.WebView2Used) {
            "{0} - Continue to use WebView2" -f $MyInvocation.MyCommand | Write-Verbose
            $WebView2Authentication = $true
        }

        if ($WebView2Authentication) {
            "{0} - Using WebView2 for authentication" -f $MyInvocation.MyCommand | Write-Verbose
            # Get-DataFromWebView2 bridges $SessionContext into $Script:CurrentWebView2Session itself
            # (WebView2's .NET event-handler closures cannot see this call stack to read it directly).
            Get-DataFromWebView2 -SessionContext $SessionContext -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
            $BrowserData = @($SessionContext.AuthCookie, $Script:UserAgent)
            $SessionContext.WebView2Used = $true
        }
        else {
            "{0} - Using Selenium WebDriver for authentication" -f $MyInvocation.MyCommand | Write-Verbose
            $BrowserData = Get-DataFromWebDriver -SessionContext $SessionContext -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
        }

        "{0} - Setting OmadaWebAuthCookie and user agent" -f $MyInvocation.MyCommand | Write-Verbose
        $SessionContext.AuthCookie = $BrowserData[0]
        $BoundParams.UserAgent = $Script:UserAgent
        $Session.UserAgent = $Script:UserAgent

        if ("Cookie" -notin $BoundParams.Headers.Keys) {
            $BoundParams.Headers.Add("Cookie", ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "="))
        }
        else {
            $BoundParams.Headers.Cookie = ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "=")
        }
        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($SessionContext.AuthCookie.Value), "/", $($SessionContext.AuthCookie.domain))))
    }

    if (![string]::IsNullOrEmpty($($BoundParams.CookiePath))) {
        "{0} - Export cookie to: {1}" -f $MyInvocation.MyCommand, $BoundParams.CookiePath | Write-Verbose

        # Uses the same helper as the read path in Invoke-OmadaRequest.ps1 to guarantee an identical
        # filename (previously this used the cookie's own .domain attribute, which may lack the port,
        # producing a different filename than what the read path looked for). Built from
        # $BoundParams.Uri directly rather than relying on the caller's $Uri local.
        $CookieFileName = Get-OmadaCookieFileName -Uri ([System.Uri]::new($BoundParams.Uri)) -Credential $BoundParams.Credential -SessionKey $BoundParams.SessionKey
        $CookiePath = (Join-Path $($BoundParams.CookiePath) -ChildPath $CookieFileName)
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $SessionContext.AuthCookie
        }

        try {
            $CookieObject | Export-Clixml $CookiePath -Force
            "Cookie file exported to: {0}" -f $CookiePath | Write-Verbose
        }
        catch [System.UnauthorizedAccessException] {
            "Unable to export the cookie file due insufficient permissions in folder {0}" -f $($BoundParams.CookiePath) | Write-Warning
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
    elseif ($BoundParams.Keys -contains "SkipCookieCache") {
        "{0} - Skipping cookie caching" -f $MyInvocation.MyCommand | Write-Verbose
        if (![string]::IsNullOrWhiteSpace($SessionContext.CookieCacheFilePath) -and (Test-Path $SessionContext.CookieCacheFilePath -PathType Leaf)) {
            "{0} - Existing cookie cache file found, removing it" -f $MyInvocation.MyCommand | Write-Verbose
            $SessionContext.CookieCacheFilePath | Remove-Item -ErrorAction SilentlyContinue
        }
    }
    elseif ($BoundParams.Keys -notcontains "SkipCookieCache") {
        "{0} - Caching encrypted cookie" -f $MyInvocation.MyCommand | Write-Verbose
        $CookieObject = [PSCustomObject]@{
            OmadaWebAuthCookie = $SessionContext.AuthCookie
        }
        $CookieCliXmlContent = [System.Management.Automation.PSSerializer]::Serialize($CookieObject, [int]::MaxValue)
        $SecureCookieCliXml = ConvertTo-SecureString -String $CookieCliXmlContent -AsPlainText -Force
        try {
            $SecureCookieCliXml | Export-Clixml -Path $SessionContext.CookieCacheFilePath -Force
            "{0} - Updated encrypted cookie cache: {1}" -f $MyInvocation.MyCommand, $SessionContext.CookieCacheFilePath | Write-Verbose
        }
        catch [System.UnauthorizedAccessException] {
            "Unable to cache cookie due insufficient permissions in folder '{0}'" -f (Split-Path $SessionContext.CookieCacheFilePath) | Write-Warning
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
}
