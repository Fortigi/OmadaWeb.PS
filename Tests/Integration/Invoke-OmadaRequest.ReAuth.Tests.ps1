param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop

    # A listener of this file's own rather than Tests/Integration/Start-WebServer.ps1, which always
    # answers 200 and so cannot express the thing under test. It runs in-process on its own
    # runspace and is steered through a synchronized hashtable, so a test can say "refuse the next
    # request" or "refuse every request" and then read back how many requests actually arrived.
    $Script:ServerState = [hashtable]::Synchronized(@{
            UnauthorizedRemaining = 0      # 401 this many more times, then 200. -1 means always.
            StatusOverride        = $null  # answer with this status instead, for the 502 case
            Requests              = 0
            Stop                  = $false
        })

    $Script:ServerPort = Get-Random -Minimum 21000 -Maximum 22000
    $Script:ServerUri = "http://localhost:{0}/" -f $Script:ServerPort

    $Script:ServerRunspace = [runspacefactory]::CreateRunspace()
    $Script:ServerRunspace.Open()
    $Script:ServerRunspace.SessionStateProxy.SetVariable("Prefix", $Script:ServerUri)
    $Script:ServerRunspace.SessionStateProxy.SetVariable("State", $Script:ServerState)
    $Script:ServerShell = [powershell]::Create()
    $Script:ServerShell.Runspace = $Script:ServerRunspace
    $Script:ServerShell.AddScript({
            $Listener = [System.Net.HttpListener]::new()
            $Listener.Prefixes.Add($Prefix)
            $Listener.Start()
            while (-not $State.Stop) {
                try {
                    $Context = $Listener.GetContext()
                    if ($State.Stop) { $Context.Response.Close(); break }

                    $State.Requests++

                    if ($null -ne $State.StatusOverride) {
                        $Status = [int]$State.StatusOverride
                    }
                    elseif ($State.UnauthorizedRemaining -ne 0) {
                        $Status = 401
                        if ($State.UnauthorizedRemaining -gt 0) { $State.UnauthorizedRemaining-- }
                    }
                    else {
                        $Status = 200
                    }

                    $Body = if ($Status -eq 200) { '{"value":"ok"}' } else { "denied" }
                    $Bytes = [Text.Encoding]::UTF8.GetBytes($Body)
                    $Context.Response.StatusCode = $Status
                    $Context.Response.ContentType = "application/json"
                    $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                    $Context.Response.Close()
                }
                catch {
                    if (-not $Listener.IsListening) { break }
                }
            }
            try { $Listener.Stop() } catch { }
        }) | Out-Null
    $Script:ServerShell.BeginInvoke() | Out-Null

    # Readiness: poll rather than sleep a fixed amount. Deliberately not the shared harness's probe,
    # which counted a request of its own against the very counters these tests assert on.
    $Ready = $false
    $Deadline = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Ready -and $Deadline.Elapsed.TotalSeconds -lt 30) {
        try {
            Invoke-WebRequest -Uri $Script:ServerUri -TimeoutSec 2 -SkipHttpErrorCheck | Out-Null
            $Ready = $true
        }
        catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $Ready) { throw "The test listener did not start on $Script:ServerUri" }
    $Script:ServerState.Requests = 0

    function Reset-ServerState {
        param(
            [int]$Unauthorized = 0,
            $StatusOverride = $null
        )
        $Script:ServerState.UnauthorizedRemaining = $Unauthorized
        $Script:ServerState.StatusOverride = $StatusOverride
        $Script:ServerState.Requests = 0
    }

    # Every test starts from a session store with nothing in it, so one test's cookie or
    # re-authentication count cannot be read by the next.
    function Reset-SessionState {
        InModuleScope 'OmadaWeb.PS' {
            $Script:OmadaSessions = @{}
            $Script:OmadaWebAuthCookie = $null
            $Script:RecheckEnvironmentSuspended = $false
        }
    }

    function Get-OnlySessionContext {
        InModuleScope 'OmadaWeb.PS' {
            $Script:OmadaSessions.Values | Select-Object -First 1
        }
    }

    $Script:FakeCookie = [pscustomobject]@{
        name     = "oisauthtoken"
        value    = "test-cookie-value"
        domain   = "localhost"
        path     = "/"
        expires  = $null
        httpOnly = $true
        secure   = $false
        sameSite = "Lax"
    }
}

AfterAll {
    if ($null -ne $Script:ServerState) { $Script:ServerState.Stop = $true }
    try { Invoke-WebRequest -Uri $Script:ServerUri -TimeoutSec 2 -SkipHttpErrorCheck | Out-Null } catch { }
    try { $Script:ServerShell.Stop() } catch { }
    try { $Script:ServerRunspace.Dispose() } catch { }
}

Describe 'Invoke-OmadaRequest 401 re-authentication' -Tag 'Integration' {

    BeforeEach {
        Reset-SessionState
        # The browser is the one thing that cannot run here, so it is the one thing mocked: it
        # hands back a cookie exactly as a completed sign-in would. Everything else - the request,
        # the 401, the catch, the recursion - is the real code path.
        Mock -ModuleName OmadaWeb.PS Get-DataFromWebView2 {
            $SessionContext.AuthCookie = [pscustomobject]@{
                name     = "oisauthtoken"
                value    = "test-cookie-value"
                domain   = "localhost"
                path     = "/"
                expires  = $null
                httpOnly = $true
                secure   = $false
                sameSite = "Lax"
            }
        }
    }

    Context 'The server rejects once and then accepts' {
        It 'should return the successful response to the caller' {
            Reset-ServerState -Unauthorized 1

            $Result = Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache
            $Result.value | Should -Be "ok"
        }

        It 'should sign in once more and retry exactly once' {
            Reset-ServerState -Unauthorized 1

            Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache | Out-Null

            # Two requests: the rejected one and the retry. Two sign-ins: the initial one (no
            # cookie yet) and the one the 401 forced.
            $Script:ServerState.Requests | Should -Be 2
            Should -Invoke -ModuleName OmadaWeb.PS Get-DataFromWebView2 -Times 2 -Exactly
        }

        It 'should discard the rejected cookie before signing in again' {
            Reset-ServerState -Unauthorized 1
            $Observed = [System.Collections.Generic.List[object]]::new()
            Mock -ModuleName OmadaWeb.PS Get-DataFromWebView2 -MockWith {
                # What the cookie was at the moment the re-authentication started. A cookie still
                # sitting here would mean the rejected one was never cleared.
                $Observed.Add($SessionContext.AuthCookie)
                $SessionContext.AuthCookie = [pscustomobject]@{
                    name = "oisauthtoken"; value = "test-cookie-value"; domain = "localhost"
                    path = "/"; expires = $null; httpOnly = $true; secure = $false; sameSite = "Lax"
                }
            }

            Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache | Out-Null

            $Observed.Count | Should -Be 2
            $Observed[1] | Should -BeNullOrEmpty
        }

        It 'should leave the re-authentication budget spent, then restored, so the next expiry gets a full one' {
            Reset-ServerState -Unauthorized 1
            Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache | Out-Null

            (Get-OnlySessionContext).ReAuthenticationCount | Should -Be 0
        }
    }

    Context 'The server rejects every time' {
        It 'should stop instead of recursing without end' {
            # This is the case that used to recurse until the call stack ran out: each turn reset
            # the sign-in window counter, so nothing accumulated across the recursion.
            Reset-ServerState -Unauthorized -1

            { Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache -ErrorAction Stop } |
                Should -Throw "*still answered HTTP 401*"
        }

        It 'should give up after the configured number of attempts, not before and not after' {
            Reset-ServerState -Unauthorized -1
            $MaxRetries = InModuleScope 'OmadaWeb.PS' { $Script:MaxLoginRetries }

            try { Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache -ErrorAction Stop | Out-Null } catch { }

            # The first request happens after the initial sign-in; each of the MaxLoginRetries
            # re-authentications adds one more. The attempt that would exceed the budget is refused
            # before another sign-in window is opened.
            $Script:ServerState.Requests | Should -Be ($MaxRetries + 1)
            Should -Invoke -ModuleName OmadaWeb.PS Get-DataFromWebView2 -Times ($MaxRetries + 1) -Exactly
        }

        It 'should say how many attempts were made and which tenant refused them' {
            Reset-ServerState -Unauthorized -1
            $MaxRetries = InModuleScope 'OmadaWeb.PS' { $Script:MaxLoginRetries }

            $Message = $null
            try { Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache -ErrorAction Stop | Out-Null }
            catch { $Message = $_.Exception.Message }

            $Message | Should -Match ([regex]::Escape("attempted {0} time(s)" -f $MaxRetries))
            $Message | Should -Match "localhost"
        }

        It 'should reset the budget once it has given up, so a later call is not refused outright' {
            Reset-ServerState -Unauthorized -1
            try { Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache -ErrorAction Stop | Out-Null } catch { }

            (Get-OnlySessionContext).ReAuthenticationCount | Should -Be 0

            # And proves it: the same session succeeds the moment the server accepts again.
            Reset-ServerState -Unauthorized 0
            (Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache).value | Should -Be "ok"
        }
    }

    Context 'A 401 with -CookiePath' {
        It 'should write the fresh cookie to disk before retrying, so the retry cannot reload the rejected one' {
            $CookieFolder = Join-Path ([System.IO.Path]::GetTempPath()) ("omadaCookie_{0}" -f ([guid]::NewGuid().ToString("N")))
            New-Item -Path $CookieFolder -ItemType Directory -Force | Out-Null
            try {
                $CookieFileName = InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Script:ServerUri } {
                    Get-OmadaCookieFileName -Uri ([System.Uri]::new($UriA))
                }
                $CookieFile = Join-Path $CookieFolder -ChildPath $CookieFileName

                # A stale cookie already on disk: exactly the one that causes the 401, and the one
                # an unfixed retry would reload on its way round the loop. Written and read through
                # the module's own helpers, so the file is in whatever shape the module expects
                # (protected at rest since issue #21) rather than a bare Clixml this test invented.
                InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $CookieFile } {
                    Export-OmadaCookieFile -Path $PathA -AuthCookie ([pscustomobject]@{
                            name = "oisauthtoken"; value = "stale-cookie"; domain = "localhost"
                            path = "/"; expires = $null; httpOnly = $true; secure = $false; sameSite = "Lax"
                        }) | Out-Null
                }

                Reset-ServerState -Unauthorized 1
                Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -CookiePath $CookieFolder | Out-Null

                $OnDisk = InModuleScope 'OmadaWeb.PS' -Parameters @{ PathA = $CookieFile } {
                    Import-OmadaCookieFile -Path $PathA
                }
                $OnDisk.value | Should -Be "test-cookie-value"
                $Script:ServerState.Requests | Should -Be 2
            }
            finally {
                Remove-Item -Path $CookieFolder -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'A 401 with the encrypted cookie cache in play' {
        It 'should delete the cached cookie the server has just rejected' {
            Reset-ServerState -Unauthorized 1

            $CachePath = $null
            # Observed while each re-authentication runs: by the time the call returns the cache
            # has been written again, so asserting afterwards would prove nothing. A list in the
            # test's own scope, not a $Script: variable - inside a mock body that would land in
            # this file's scope, not the module's, and read back as $null.
            $CacheExistedAtSignIn = [System.Collections.Generic.List[bool]]::new()
            Mock -ModuleName OmadaWeb.PS Get-DataFromWebView2 -MockWith {
                $CacheExistedAtSignIn.Add(
                    (![string]::IsNullOrWhiteSpace($SessionContext.CookieCacheFilePath)) -and (Test-Path $SessionContext.CookieCacheFilePath -PathType Leaf)
                )
                $SessionContext.AuthCookie = [pscustomobject]@{
                    name = "oisauthtoken"; value = "test-cookie-value"; domain = "localhost"
                    path = "/"; expires = $null; httpOnly = $true; secure = $false; sameSite = "Lax"
                }
            }

            try {
                Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 | Out-Null
                # Two sign-ins: the initial one and the one the 401 forced. The cache must have
                # been gone by the time the second started - that is the rejected cookie being
                # thrown away rather than handed straight back to the retry.
                $CacheExistedAtSignIn.Count | Should -Be 2
                $CacheExistedAtSignIn[1] | Should -Be $false
            }
            finally {
                $CachePath = (Get-OnlySessionContext).CookieCacheFilePath
                if (![string]::IsNullOrWhiteSpace($CachePath)) {
                    Remove-Item -Path $CachePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Context 'Responses that are not a 401' {
        It 'should not re-authenticate on a 502, and should mark the environment for a re-probe' {
            Reset-ServerState -StatusOverride 502

            # -MaximumRetryCount 0 turns off the transient-failure retry policy, which treats a 502
            # as worth retrying with backoff. That is a separate mechanism and is not what this
            # test is about: here the question is only whether a 502 triggers a sign-in.
            try { Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache -MaximumRetryCount 0 -ErrorAction Stop | Out-Null } catch { }

            InModuleScope 'OmadaWeb.PS' { $Script:RecheckEnvironmentSuspended } | Should -Be $true
            # One sign-in (there was no cookie) and no second one: a 502 is not an authentication
            # problem, and signing in again would only delay the real error.
            Should -Invoke -ModuleName OmadaWeb.PS Get-DataFromWebView2 -Times 1 -Exactly
            $Script:ServerState.Requests | Should -Be 1
        }

        It 'should surface a 500 without re-authenticating' {
            Reset-ServerState -StatusOverride 500

            { Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache -MaximumRetryCount 0 -ErrorAction Stop } | Should -Throw
            $Script:ServerState.Requests | Should -Be 1
            Should -Invoke -ModuleName OmadaWeb.PS Get-DataFromWebView2 -Times 1 -Exactly
        }
    }

    Context '-NoInteractiveAuthentication' {
        It 'should refuse to sign in again on a 401 and say so' {
            Reset-ServerState -Unauthorized -1

            # Seed a cookie so the call gets as far as the request; the switch forbids the sign-in
            # that would otherwise happen first.
            InModuleScope 'OmadaWeb.PS' -Parameters @{ UriA = $Script:ServerUri } {
                $Key = Get-OmadaSessionKey -Uri ([System.Uri]::new($UriA)) -AuthenticationType "WebView2"
                $Context = Get-OmadaSessionContext -Key $Key -AuthorityHost ([System.Uri]::new($UriA)).Host
                $Context.AuthCookie = [pscustomobject]@{
                    name = "oisauthtoken"; value = "seeded"; domain = "localhost"
                    path = "/"; expires = $null; httpOnly = $true; secure = $false; sameSite = "Lax"
                }
            }

            { Invoke-OmadaRestMethod -Uri $Script:ServerUri -AuthenticationType WebView2 -SkipCookieCache -NoInteractiveAuthentication -ErrorAction Stop } |
                Should -Throw "*no sign-in was attempted*"

            Should -Invoke -ModuleName OmadaWeb.PS Get-DataFromWebView2 -Times 0 -Exactly
        }
    }
}
