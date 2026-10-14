function Invoke-BrowserAuthentication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSTypeName("OmadaWeb.PS.RequestContext")]$RequestContext
    )

    # The only helper that works on all three members: it adds the Cookie header to $BoundParams,
    # adds the cookie to $Session's container, and reads and updates the per-session $SessionContext.
    $BoundParams = $RequestContext.BoundParams
    $Session = $RequestContext.Session
    $SessionContext = $RequestContext.SessionContext

    "{0} - Set Browser authentication" -f $MyInvocation.MyCommand | Write-Verbose

    if ($BoundParams['ForceAuthentication']) {
        "{0} - ForceAuthentication used. Reset OmadaWebAuthCookie and reset Browser authentication engine to default" -f $MyInvocation.MyCommand | Write-Verbose
        $SessionContext.AuthCookie = $null
        $SessionContext.WebView2Used = $false
        $SessionContext.ForceAuthentication = $true
    }
    $SessionContext.Credential = $null
    if ($BoundParams.keys -contains "Credential") {
        $SessionContext.Credential = $BoundParams['Credential']
    }

    # One account, from either of the two places a caller can name it. Resolved here so that nothing
    # downstream has to ask the question twice, and carried on the session for the same reason the
    # credential is: the WebView2 sign-in runs inside a blocking dialog whose handlers cannot see
    # this call stack. Left null when nobody named an account, which is what keeps the default
    # behaviour - the browser decides - exactly as it was.
    $SessionContext.UserName = $null
    if ($BoundParams.keys -contains "UserName" -and -not [string]::IsNullOrWhiteSpace($BoundParams['UserName'])) {
        $SessionContext.UserName = $BoundParams['UserName'].Trim()
    }
    elseif ($null -ne $SessionContext.Credential -and -not [string]::IsNullOrWhiteSpace($SessionContext.Credential.UserName)) {
        $SessionContext.UserName = $SessionContext.Credential.UserName.Trim()
    }

    $SessionContext.SelectAccount = $BoundParams.keys -contains "SelectAccount" -and [bool]$BoundParams['SelectAccount']

    # Carried on the session rather than passed down: the WebView2 sign-in runs inside a blocking
    # WinForm dialog whose event handlers cannot see this call stack, and the session context is how
    # everything else - the credential included - reaches them.
    $SessionContext.PreferredMfaMethod = $null
    if ($BoundParams.keys -contains "PreferredMfaMethod") {
        $SessionContext.PreferredMfaMethod = $BoundParams['PreferredMfaMethod']
    }
    switch ($SessionContext.LastSessionType) {
        { $_ -eq "Normal" -and [bool]$BoundParams['InPrivate'] } {
            "{0} - Reset OmadaWebAuthCookie because session has changed to InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $SessionContext.AuthCookie = $null
            $SessionContext.LastSessionType = "InPrivate"
        }
        # ContainsKey rather than a plain negation, to keep the asymmetry this branch has always had:
        # it fires only on an explicit -InPrivate:$false, not on -InPrivate being left off. The reads
        # here used to go through .IsPresent on the bound value, which is $null when the switch was
        # never supplied, and $null -eq $false is False - so an omitted switch never reached this arm.
        { $_ -eq "InPrivate" -and $BoundParams.ContainsKey("InPrivate") -and -not [bool]$BoundParams['InPrivate'] } {
            "{0} - Reset OmadaWebAuthCookie because session has changed from InPrivate to not InPrivate" -f $MyInvocation.MyCommand | Write-Verbose
            $SessionContext.AuthCookie = $null
            $SessionContext.LastSessionType = "Normal"
        }
        default {}
    }

    if ($null -ne $($SessionContext.AuthCookie) -and ([System.Uri]::New($SessionContext.BaseUrl).host -eq $($SessionContext.AuthCookie.domain))) {
        "{0} - Using existing cookie for this domain: {1}" -f $MyInvocation.MyCommand, $SessionContext.BaseUrl | Write-Verbose
        if ("Cookie" -notin $BoundParams['Headers'].Keys) {
            $BoundParams['Headers'].Add("Cookie", ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "="))
        }
        else {
            $BoundParams['Headers'].Cookie = ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "=")
        }
        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($SessionContext.AuthCookie.Value), "/", $($SessionContext.AuthCookie.domain))))
    }
    else {
        "{0} - OmadaWebAuthCookie not exists or is for different domain. Need to authenticate!" -f $MyInvocation.MyCommand | Write-Verbose

        # -NoInteractiveAuthentication is refused here, above the engine selection, rather than
        # inside either engine: this is the single point every browser sign-in passes through when no
        # usable cookie is available, so stopping here is what makes "no window can open" a property
        # of the code rather than a claim about it.
        #
        # The session's own flag counts as well as the switch: a session seeded by
        # Import-OmadaSession is being used by a worker runspace with no desktop and nobody
        # watching, so it may not sign in whether or not this particular call remembered to say so.
        if (($BoundParams.ContainsKey("NoInteractiveAuthentication") -and [bool]$BoundParams['NoInteractiveAuthentication']) -or $SessionContext.NoInteractiveAuthentication) {
            $Message = if ($SessionContext.Seeded) {
                "The Omada session imported for '{0}' is no longer usable, so no sign-in was attempted. Export a fresh session from the runspace that signed in, or import it with -AllowInteractiveAuthentication." -f $SessionContext.BaseUrl
            }
            else {
                "No usable Omada session for '{0}' and -NoInteractiveAuthentication was specified, so no sign-in was attempted. Sign in once without -NoInteractiveAuthentication, then retry." -f $SessionContext.BaseUrl
            }
            throw (New-OmadaSessionExpiredError -Message $Message -BaseUrl $SessionContext.BaseUrl)
        }

        # Check if WebView2 should be used instead of Selenium
        $WebView2Authentication = $false
        if (($BoundParams.ContainsKey('UseWebView2') -and $BoundParams['UseWebView2']) -or $BoundParams['AuthenticationType'] -eq "WebView2") {
            "{0} - UseWebView2 parameter used" -f $MyInvocation.MyCommand | Write-Verbose
            if ($BoundParams.ContainsKey('UseWebView2') -and $BoundParams['UseWebView2']) {
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
            Get-DataFromWebView2 -SessionContext $SessionContext -EdgeProfile $BoundParams['EdgeProfile'] -InPrivate:([bool]$BoundParams['InPrivate'])
            $BrowserData = @($SessionContext.AuthCookie, $Script:UserAgent)
            $SessionContext.WebView2Used = $true
        }
        else {
            "{0} - Using Selenium WebDriver for authentication" -f $MyInvocation.MyCommand | Write-Verbose
            Write-OmadaDeprecationWarning -Feature "SeleniumBrowserEngine"
            $BrowserData = Get-DataFromWebDriver -SessionContext $SessionContext -EdgeProfile $BoundParams['EdgeProfile'] -InPrivate:([bool]$BoundParams['InPrivate'])
        }

        "{0} - Setting OmadaWebAuthCookie and user agent" -f $MyInvocation.MyCommand | Write-Verbose
        $SessionContext.AuthCookie = $BrowserData[0]
        $BoundParams['UserAgent'] = $Script:UserAgent
        $Session.UserAgent = $Script:UserAgent

        if ("Cookie" -notin $BoundParams['Headers'].Keys) {
            $BoundParams['Headers'].Add("Cookie", ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "="))
        }
        else {
            $BoundParams['Headers'].Cookie = ($($SessionContext.AuthCookie).Name, $($SessionContext.AuthCookie).Value -join "=")
        }
        $Session.Cookies.Add((New-Object System.Net.Cookie("oisauthtoken", $($SessionContext.AuthCookie.Value), "/", $($SessionContext.AuthCookie.domain))))
    }

    if (![string]::IsNullOrEmpty($($BoundParams['CookiePath']))) {
        "{0} - Export cookie to: {1}" -f $MyInvocation.MyCommand, $BoundParams['CookiePath'] | Write-Verbose

        # Uses the same helper as the read path in Invoke-OmadaRequest.ps1 to guarantee an identical
        # filename (previously this used the cookie's own .domain attribute, which may lack the port,
        # producing a different filename than what the read path looked for). Built from
        # $BoundParams['Uri'] directly rather than relying on the caller's $Uri local.
        $CookieFileName = Get-OmadaCookieFileName -Uri ([System.Uri]::new($BoundParams['Uri'])) -Credential $BoundParams['Credential'] -SessionKey $BoundParams['SessionKey'] -UserName $BoundParams['UserName']
        $CookiePath = (Join-Path $($BoundParams['CookiePath']) -ChildPath $CookieFileName)

        # Protected at rest, through the same writer as the default cache below. This used to be a
        # bare Export-Clixml, which left the raw oisauthtoken readable in the file (issue #21).
        if (Export-OmadaCookieFile -Path $CookiePath -AuthCookie $SessionContext.AuthCookie) {
            "Cookie file exported to: {0}" -f $CookiePath | Write-Verbose
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
        if (Export-OmadaCookieFile -Path $SessionContext.CookieCacheFilePath -AuthCookie $SessionContext.AuthCookie) {
            "{0} - Updated encrypted cookie cache: {1}" -f $MyInvocation.MyCommand, $SessionContext.CookieCacheFilePath | Write-Verbose
        }
    }

    return $RequestContext
}
