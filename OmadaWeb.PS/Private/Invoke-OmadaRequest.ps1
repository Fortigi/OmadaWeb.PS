function Invoke-OmadaRequest {
    [CmdletBinding(DefaultParameterSetName = "StandardMethod")]
    param()

    dynamicparam {
        return Set-DynamicParameter -FunctionName $Script:FunctionName
    }
    process {
        try {

            "{0} called for {1} by {2}" -f $MyInvocation.MyCommand, $Script:FunctionName, (Get-PSCallStack)[1].Command | Write-Verbose

            $Script:StopError = $false
            $BoundParams = $PsCmdLet.MyInvocation.BoundParameters

            if ("UserAgent" -notin $BoundParams.Keys) {
                $BoundParams.Add("UserAgent", $Script:UserAgent)
                $Script:UserAgentParameterUsed = $false
            }
            else {
                $Script:UserAgentParameterUsed = $true
                $Script:UserAgent = $BoundParams.UserAgent
            }

            if ("DebugWebView2" -in $BoundParams.Keys) {
                $Script:DebugWebView2 = $true
            }

            # The retry policy is on by default; -MaximumRetryCount 0 turns it off, matching how the
            # native cmdlets read that parameter. Defaults are applied to $BoundParams rather than
            # relying on the dynamic parameter's own default value, because a dynamic parameter that
            # was not supplied never reaches $PsCmdLet.MyInvocation.BoundParameters at all. Putting
            # them in $BoundParams also carries them through the re-authentication recursion below,
            # which rebuilds its arguments from exactly this hashtable.
            if ("MaximumRetryCount" -notin $BoundParams.Keys) {
                $BoundParams.Add("MaximumRetryCount", 3)
            }

            if ("RetryIntervalSec" -notin $BoundParams.Keys) {
                $BoundParams.Add("RetryIntervalSec", 2)
            }

            $RetryPolicy = @{
                MaximumRetryCount = [int]$BoundParams.MaximumRetryCount
                RetryIntervalSec  = [int]$BoundParams.RetryIntervalSec
            }

            if ("Headers" -notin $BoundParams.Keys) {
                $BoundParams.Add("Headers", @{})
            }

            $Uri = [System.Uri]::new($BoundParams.Uri)
            if ($null -ne $Uri) {
                $BaseUrl = $Uri.GetLeftPart([System.UriPartial]::Authority)

                # Update the cached base URL up front - before the suspension probe/abort below.
                # When the environment is suspended the abort throws before the rest of the process
                # block runs, so deferring this assignment would leave the global holding the previous
                # URL and re-probe a suspended environment on every call instead of once. Capture the
                # previous value first so the probe can still tell whether the base URL actually changed.
                $PreviousBaseUrl = $Global:OmadaWebPSCurrentBaseUrl
                "{0} - BaseUrl: {1}" -f $MyInvocation.MyCommand, $BaseUrl | Write-Verbose
                $Global:OmadaWebPSCurrentBaseUrl = $BaseUrl
                "{0} - Export global variable OmadaWebPSCurrentBaseUrl: {1}" -f $MyInvocation.MyCommand, $Global:OmadaWebPSCurrentBaseUrl | Write-Verbose

                # Test environment status. The result is cached for the current base URL (only the
                # single last-used URL is tracked, so alternating between two environments re-probes
                # each switch) so the probe normally runs once, not on every request. It is
                # re-evaluated when the base URL changes, when the module is re-imported with -Force
                # (which resets the module-scoped state), or after a 502 response (flagged on the catch
                # path below, which is how a suspended environment surfaces once a session is active).
                if ($BaseUrl -ne $PreviousBaseUrl -or $Script:RecheckEnvironmentSuspended) {
                    $Script:EnvironmentSuspended = Test-EnvironmentSuspended -Url $BaseUrl -TimeoutSec 5
                    $Script:RecheckEnvironmentSuspended = $false
                }
                if ($Script:EnvironmentSuspended) {
                    "{0} - Environment is suspended ({1}), aborting request." -f $MyInvocation.MyCommand, $BaseUrl | Write-Error -ErrorAction "Stop"
                }
            }
            else {
                "Could not determine the base URL from '{0}', is the URL correct?" -f $BoundParams.Uri | Write-Error -ErrorAction "Stop"
            }

            $Session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $Session.UserAgent = $Script:UserAgent

            if ("AuthenticationType" -notin $BoundParams.Keys) {
                $BoundParams.Add("AuthenticationType", "WebView2")
            }

            # Reusable session state (cookie, base URL, WebView2 profile, etc.) is keyed by
            # (tenant base URL, auth type, identity) instead of single unkeyed module variables,
            # so concurrent sessions to different tenants/users don't clobber each other.
            $SessionKey = Get-OmadaSessionKey -Uri $Uri -AuthenticationType $BoundParams.AuthenticationType -Credential $BoundParams.Credential -SessionKey $BoundParams.SessionKey
            $SessionContext = Get-OmadaSessionContext -Key $SessionKey -AuthorityHost $Uri.Host
            $SessionContext.BaseUrl = $BaseUrl
            # Computed unconditionally (not just lazily inside the encrypted-cache branch below) so it's
            # always available for Invoke-BrowserAuthentication.ps1's cache-write step later, even when
            # this particular call took the -CookiePath branch instead on its first-ever use of this session.
            $SessionContext.CookieCacheFilePath = Get-OmadaCookieCacheFilePath -SessionKey $SessionKey

            # The three pieces of per-request state the private helpers work on, bundled so they can
            # take them as a parameter instead of reading them out of this function's scope. The
            # context aliases the objects below rather than copying them, so the locals stay valid.
            $RequestContext = New-OmadaRequestContext -BoundParams $BoundParams -Session $Session -SessionContext $SessionContext

            if ($BoundParams.Keys -contains "CookiePath") {
                # -CookiePath is authoritative on every call (not just when no cookie is cached yet),
                # so callers can force a specific session's cookie to be used for a given call.
                $CookieFileName = Get-OmadaCookieFileName -Uri $Uri -Credential $BoundParams.Credential -SessionKey $BoundParams.SessionKey
                $CookiePath = (Join-Path $($BoundParams.CookiePath) -ChildPath $CookieFileName)
                "{0} - Loading custom cookie: {1}" -f $MyInvocation.MyCommand, $CookiePath | Write-Verbose
                if (!(Test-Path $CookiePath -PathType Leaf)) {
                    # -CookiePath is authoritative, so a missing file must not leave a stale in-memory
                    # cookie (possibly from an earlier call for this session) in place - that would
                    # silently defeat the "force this specific cookie" contract -CookiePath implies.
                    $SessionContext.AuthCookie = $null
                    "No cookie found at '{0}', trying to create a new one." -f $CookiePath | Write-Warning
                }
                else {
                    try {
                        $SessionContext.AuthCookie = (Import-Clixml $CookiePath).OmadaWebAuthCookie
                        # Diagnostics only: the cookie's own value is the session secret, so this goes
                        # through the redaction walker. Depth is kept shallow on purpose so a verbose
                        # log does not expand the whole cookie object graph.
                        "{0} - Cookie:`r{1}" -f $MyInvocation.MyCommand, (ConvertTo-RedactedLogString -InputObject $SessionContext.AuthCookie -MaxDepth 3) | Write-Verbose
                    }
                    catch {
                        $SessionContext.AuthCookie = $null
                        "Failure loading cookie, try to create a new one." | Write-Verbose
                    }
                }
            }
            elseif ($null -eq $SessionContext.AuthCookie -and $BoundParams.Keys -notcontains "SkipCookieCache") {
                if ($BoundParams.Keys -notcontains "ForceAuthentication" -and (Test-Path $SessionContext.CookieCacheFilePath -PathType Leaf)) {
                    "{0} - Loading cached encrypted cookie: {1}" -f $MyInvocation.MyCommand, $SessionContext.CookieCacheFilePath | Write-Verbose

                    try {
                        $SessionContext.AuthCookie = ([System.Management.Automation.PSSerializer]::Deserialize([System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Import-Clixml $SessionContext.CookieCacheFilePath))
                                ))).OmadaWebAuthCookie
                        # Diagnostics only: the cookie's own value is the session secret, so this goes
                        # through the redaction walker. Depth is kept shallow on purpose so a verbose
                        # log does not expand the whole cookie object graph.
                        "{0} - Cookie:`r{1}" -f $MyInvocation.MyCommand, (ConvertTo-RedactedLogString -InputObject $SessionContext.AuthCookie -MaxDepth 3) | Write-Verbose
                    }
                    catch {
                        "Failure loading cookie, try to create a new one." | Write-Verbose
                    }
                }
            }

            "{0} - Authentication type: {1}" -f $MyInvocation.MyCommand, $($BoundParams.AuthenticationType) | Write-Verbose

            switch ($BoundParams.AuthenticationType) {
                "Windows" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    $RequestContext = Invoke-WindowsAuthentication -RequestContext $RequestContext
                }
                "Browser" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    Invoke-BrowserAuthentication
                }
                "WebView2" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    Invoke-BrowserAuthentication
                }
                "OAuth" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    $RequestContext = Invoke-OAuth2Authentication -RequestContext $RequestContext
                }
                "Integrated" {
                    "{0} - {1} Authentication " -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    $RequestContext = Invoke-IntegratedAuthentication -RequestContext $RequestContext
                }
                "Basic" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                    $RequestContext = Invoke-BasicAuthentication -RequestContext $RequestContext
                }
                "None" {
                    "{0} - {1} Authentication" -f $MyInvocation.MyCommand, $_ | Write-Verbose
                }
                default {
                    "{0} - {1} not supported!" -f $MyInvocation.MyCommand, $_ | Write-Error -ErrorAction "Stop"
                }
            }

            if ($BoundParams.Method -in @('PUT', 'POST', 'PATCH')) {
                "{0} - {1} - Add Body" -f $MyInvocation.MyCommand, $BoundParams.Method | Write-Verbose
                $RequestContext = Set-Body -RequestContext $RequestContext
            }

            $BoundParams.Add("WebSession", $Session)

            # UseBasicParsing is deprecated since PowerShell Core 6, there it is only set when using PowerShell 5 (https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-7.4#-usebasicparsing)
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $BoundParams.Add("UseBasicParsing", $true)
            }

            $Paged = $false
            if ("Paged" -in $BoundParams.Keys -and [bool]$BoundParams.Paged) {
                if ("Method" -in $BoundParams.Keys -and $BoundParams.Method -ne "GET") {
                    "{0} - -Paged only supports HTTP GET requests, got -Method '{1}'" -f $MyInvocation.MyCommand, $BoundParams.Method | Write-Error -ErrorAction "Stop"
                }
                $Paged = $true
            }

            # Diagnostics only: $BoundParams holds the Authorization header, the credential and the
            # session carrying the auth cookie, so it only ever reaches the verbose stream through the
            # redaction walker. The string is built on every request even without -Verbose, which is
            # why the walker's depth cap matters as much as its masking.
            "{0} - {1}" -f $MyInvocation.MyCommand, (ConvertTo-RedactedLogString -InputObject $BoundParams) | Write-Verbose
            try {
                $CustomErrorTrigger = "Login failed - {0}" -f (New-Guid).Guid.ToString()
                $FullyQualifiedModule = @{
                    ModuleName    = "Microsoft.PowerShell.Utility"
                    Guid          = [guid]"1da87e53-152b-403e-98dc-74d7b4d63d59"
                    ModuleVersion = [Version]"7.0.0"
                }
                if ($PSVersionTable.PSEdition -eq "Desktop") {
                    $FullyQualifiedModule.ModuleVersion = [Version]"3.1.0.0"
                }

                # The hashtable above holds no secrets, but it goes through the walker anyway so that
                # "no ConvertTo-Json reaches Write-Verbose in this module" stays true as a rule - a
                # rule is what survives future edits; a per-site judgement is not.
                "{0} - Using Microsoft.PowerShell.Utility module: {1}" -f $MyInvocation.MyCommand, (ConvertTo-RedactedLogString -InputObject $FullyQualifiedModule) | Write-Verbose

                switch ($Script:FunctionName) {
                    "Invoke-RestMethod" {

                        if ("Accept" -notin $BoundParams.Headers.Keys) {
                            $BoundParams.Headers.Add("Accept", "application/json")
                        }

                        if ("ContentType" -in $BoundParams.Keys) {
                            $BoundParams.Headers.Add("Content-Type", $BoundParams.ContentType)
                            $BoundParams.Remove("ContentType") | Out-Null
                        }
                        elseif ("Content-Type" -notin $BoundParams.Headers.Keys) {
                            $BoundParams.Headers.Add("Content-Type", "application/json")
                        }
                        $Parameters = Set-RequestParameter -RequestContext $RequestContext

                        try {
                            $CommandInfo = Get-Command $_ -FullyQualifiedModule $FullyQualifiedModule
                        }
                        catch {
                            Import-Module $FullyQualifiedModule.ModuleName -MinimumVersion $FullyQualifiedModule.ModuleVersion -Force -ErrorAction Stop
                            $CommandInfo = Get-Command $_ -FullyQualifiedModule $FullyQualifiedModule
                        }
                        "{0} - Execute: {1}\{2}, Version: {3}" -f $MyInvocation.MyCommand, $CommandInfo.Source, $CommandInfo.Name, $CommandInfo.Version | Write-Verbose

                        $Return = Invoke-OmadaRetryableRequest -CommandInfo $CommandInfo -Parameters $Parameters @RetryPolicy

                        if ($Paged -and $null -ne $Return -and $Return.PSObject.Properties['@odata.nextLink'] -and -not [string]::IsNullOrWhiteSpace($Return.'@odata.nextLink')) {
                            $OriginalUri = $Parameters.Uri
                            try {
                                $ValueList = [System.Collections.Generic.List[object]]::new()
                                if ($Return.PSObject.Properties['value']) {
                                    $ValueList.AddRange(@($Return.value))
                                }
                                $NextLink = $Return.'@odata.nextLink'
                                $SeenLinks = [System.Collections.Generic.HashSet[string]]::new()
                                $PageCount = 0
                                while (-not [string]::IsNullOrWhiteSpace($NextLink)) {
                                    $Parameters.Uri = $NextLink
                                    if (-not $SeenLinks.Add([string]$NextLink)) {
                                        throw ("Paging loop detected (repeated @odata.nextLink): {0}" -f $NextLink)
                                    }
                                    if (++$PageCount -gt 1000) {
                                        throw "Paging aborted: exceeded maximum page limit (1000)."
                                    }
                                    "{0} - Execute: {1}\{2}, Version: {3}" -f $MyInvocation.MyCommand, $CommandInfo.Source, $CommandInfo.Name, $CommandInfo.Version | Write-Verbose
                                    $NextPage = Invoke-OmadaRetryableRequest -CommandInfo $CommandInfo -Parameters $Parameters @RetryPolicy
                                    if ($null -ne $NextPage -and $NextPage.PSObject.Properties['value']) {
                                        $ValueList.AddRange(@($NextPage.value))
                                    }
                                    $NextLink = if ($null -ne $NextPage) { $NextPage.'@odata.nextLink' } else { $null }
                                }
                                $Return.value = $ValueList.ToArray()
                                $Return.PSObject.Properties.Remove('@odata.nextLink')
                            }
                            finally {
                                $Parameters.Uri = $OriginalUri
                            }
                        }

                        #To support -SkipHttpErrorCheck
                        if ($BoundParams.Keys -contains "SkipHttpErrorCheck" -and ($BoundParams.AuthenticationType) -in ("Browser", "WebView2") -and $Return -is [System.Xml.XmlDocument]) {
                            $NamespaceManager = New-Object System.Xml.XmlNamespaceManager($Return.NameTable)
                            $NamespaceManager.AddNamespace("xhtml", "http://www.w3.org/1999/xhtml")
                            if ($Return.SelectSingleNode('//xhtml:html/xhtml:head/xhtml:title', $NamespaceManager).'#text' -like "401 *") {
                                throw $CustomErrorTrigger
                            }
                        }
                        $SessionContext.LoginCount++
                        return $Return
                    }
                    "Invoke-WebRequest" {
                        $Parameters = Set-RequestParameter -RequestContext $RequestContext
                        try {
                            $CommandInfo = Get-Command $_ -FullyQualifiedModule $FullyQualifiedModule
                        }
                        catch {
                            Import-Module $FullyQualifiedModule.ModuleName -MinimumVersion $FullyQualifiedModule.ModuleVersion -Force -ErrorAction Stop
                            $CommandInfo = Get-Command $_ -FullyQualifiedModule $FullyQualifiedModule
                        }
                        "{0} - Execute: {1}\{2}, Version: {3}" -f $MyInvocation.MyCommand, $CommandInfo.Source, $CommandInfo.Name, $CommandInfo.Version | Write-Verbose
                        $Return = Invoke-OmadaRetryableRequest -CommandInfo $CommandInfo -Parameters $Parameters @RetryPolicy

                        #To support -SkipHttpErrorCheck
                        if ($BoundParams.Keys -contains "SkipHttpErrorCheck" -and ($BoundParams.AuthenticationType) -in ("Browser", "WebView2") -and $Return -is [Microsoft.PowerShell.Commands.WebResponseObject] -and $Return.StatusCode -eq 401) {
                            throw $CustomErrorTrigger
                        }
                        $SessionContext.LoginCount++
                        return $Return
                    }
                    default {
                        #Ignored
                    }
                }
            }

            catch {
                # Not every exception reaching here is HTTP-based (e.g. the $CustomErrorTrigger
                # re-auth signal thrown above has no .Response), which is why the status code is
                # resolved through Get-OmadaResponseStatusCode - it evaluates to $null rather than
                # faulting the catch handler under Set-StrictMode. The single value is reused for
                # the 502/401 checks below.
                $StatusCode = Get-OmadaResponseStatusCode -Exception $_.Exception
                if ($StatusCode -eq 502) {
                    # A 502 is how a suspended Omada environment surfaces once a session already
                    # exists; invalidate the cached status so the next request re-probes the
                    # environment (and can then abort early with the suspended message).
                    $Script:RecheckEnvironmentSuspended = $true
                    "{0} - Received HTTP 502; environment suspension will be re-checked on the next request." -f $MyInvocation.MyCommand | Write-Verbose
                }
                if (($BoundParams.AuthenticationType) -in ("Browser", "WebView2") -and ($StatusCode -eq 401 -or $_.Exception.Message -eq $CustomErrorTrigger)) {

                    # The exception comes from Invoke-RestMethod/Invoke-WebRequest or the browser stack
                    # and routinely quotes the request that failed, headers included. There is no
                    # object left to walk here, so the regex safety net is what applies.
                    "{0} - Re-Authentication - Error message: {1}" -f $MyInvocation.MyCommand, (Protect-LogMessage -Message $_.Exception.Message) | Write-Verbose
                    $SessionContext.AuthCookie = $null
                    if (![string]::IsNullOrWhiteSpace($SessionContext.CookieCacheFilePath) -and (Test-Path $SessionContext.CookieCacheFilePath -PathType Leaf)) {
                        $SessionContext.CookieCacheFilePath | Remove-Item -ErrorAction SilentlyContinue
                    }
                    if ($SessionContext.LoginCount -le 1) {
                        "Authentication needed!" | Write-Host
                    }
                    else {
                        "Re-authentication failed!" | Write-Host
                    }
                    $WebView2Authentication = $false
                    if ($BoundParams.ContainsKey('UseWebView2') -and $BoundParams.UseWebView2 -or $BoundParams.AuthenticationType -eq "WebView2") {
                        $WebView2Authentication = $true
                    }
                    elseif ($SessionContext.WebView2Used) {
                        "{0} - Continue to use WebView2" -f $MyInvocation.MyCommand | Write-Verbose
                        $WebView2Authentication = $true
                    }
                    if ($WebView2Authentication) {
                        "{0} - Using WebView2 for authentication" -f $MyInvocation.MyCommand | Write-Verbose
                        Get-DataFromWebView2 -SessionContext $SessionContext -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
                        $BrowserData = @($SessionContext.AuthCookie, $Script:UserAgent)
                        $SessionContext.WebView2Used = $true
                    }
                    else {
                        $BrowserData = Get-DataFromWebDriver -SessionContext $SessionContext -EdgeProfile $BoundParams.EdgeProfile -InPrivate:$($BoundParams.InPrivate).IsPresent
                    }
                    $SessionContext.AuthCookie = $BrowserData[0]

                    if ($BoundParams.Keys -contains "CookiePath") {
                        # -CookiePath is now authoritative on every call (including this recursive retry),
                        # so the freshly re-authenticated cookie must be persisted here first - otherwise the
                        # recursive call below would immediately reload and clobber it with the stale cookie
                        # still on disk (the one that caused this 401 in the first place), looping forever.
                        $RetryCookieFileName = Get-OmadaCookieFileName -Uri $Uri -Credential $BoundParams.Credential -SessionKey $BoundParams.SessionKey
                        $RetryCookiePath = Join-Path $BoundParams.CookiePath -ChildPath $RetryCookieFileName
                        try {
                            [PSCustomObject]@{ OmadaWebAuthCookie = $SessionContext.AuthCookie } | Export-Clixml $RetryCookiePath -Force
                        }
                        catch {
                            "{0} - Failed to update cookie file '{1}' after re-authentication." -f $MyInvocation.MyCommand, $RetryCookiePath | Write-Verbose
                        }
                    }

                    try {
                        $Parameters = Set-RequestParameter -RequestContext $RequestContext -InvokeOmadaRequest
                        return (Invoke-OmadaRequest @Parameters)
                    }
                    catch {
                        $PSCmdlet.ThrowTerminatingError($PSItem)
                    }
                }
                else {
                    $PSCmdlet.ThrowTerminatingError($PSItem)
                }
            }
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
    }
}