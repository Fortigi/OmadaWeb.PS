param(
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
    Import-Module $ModulePath -Force -ErrorAction Stop -Prefix Test

    # The same in-process fake Omada endpoint the retry tests use (HttpListener on a background
    # thread via Start-ThreadJob). A real HTTP round trip rather than a mocked Invoke-RestMethod,
    # because Invoke-OmadaRequest resolves the native cmdlet through
    # 'Get-Command -FullyQualifiedModule', which bypasses Pester's function-based mock shadow.
    # Here it exists to answer 401 on demand, which is the condition that would normally send the
    # module off to re-authenticate.
    $Script:Port = Get-Random -Minimum 21000 -Maximum 23000
    $Script:BaseUrl = "http://127.0.0.1:$Script:Port"

    # Written by the test thread to arm each scenario and read by the listener thread, so it has to
    # be a synchronized hashtable rather than a plain one.
    $Script:SharedServer = [hashtable]::Synchronized(@{
            Listener       = $null
            RequestCount   = 0
            CookiesSeen    = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            ResponseStatus = 200
        })

    $Script:ServerJob = Start-ThreadJob -ArgumentList $Script:Port, $Script:SharedServer -ScriptBlock {
        param($Port, $Shared)
        $Listener = [System.Net.HttpListener]::new()
        $Listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $Listener.Start()
        $Shared.Listener = $Listener
        while ($Listener.IsListening) {
            try {
                $Ctx = $Listener.GetContext()
            }
            catch {
                break
            }

            # /ready is the startup probe and '/' is the environment-suspension probe
            # Invoke-OmadaRequest makes against the site root the first time a base URL is seen.
            # Neither is the request under test, so neither is counted - otherwise the probe would
            # be indistinguishable from a re-authentication retry in the request count below.
            if ($Ctx.Request.Url.AbsolutePath -in @('/ready', '/')) {
                $Bytes = [Text.Encoding]::UTF8.GetBytes('{"value":"ready"}')
                $Ctx.Response.ContentType = 'application/json'
                $Ctx.Response.StatusCode = 200
                $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
                $Ctx.Response.Close()
                continue
            }

            $Shared.RequestCount++
            $null = $Shared.CookiesSeen.Add([string]$Ctx.Request.Headers['Cookie'])

            $Ctx.Response.StatusCode = $Shared.ResponseStatus
            $Body = if ($Shared.ResponseStatus -eq 200) { '{"value":"served"}' } else { '{"error":"unauthorized"}' }
            $Bytes = [Text.Encoding]::UTF8.GetBytes($Body)
            $Ctx.Response.ContentType = 'application/json'
            $Ctx.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
            $Ctx.Response.Close()
        }
    }

    $Ready = $false
    1..30 | ForEach-Object {
        if (-not $Ready) {
            try {
                $ProbeParameters = @{ Uri = "$Script:BaseUrl/ready"; TimeoutSec = 1 }
                if ($PSVersionTable.PSVersion.Major -lt 6) { $ProbeParameters.UseBasicParsing = $true }
                $null = Invoke-WebRequest @ProbeParameters
                $Ready = $true
            }
            catch [System.Net.WebException], [System.Net.Http.HttpRequestException] {
                Start-Sleep -Milliseconds 200
            }
            catch {
                $Ready = $true
            }
        }
    }
    if (-not $Ready) {
        throw "Failed to start the fake Omada endpoint on $Script:BaseUrl"
    }

    # Seeds an already-authenticated session, which is the state this feature exists to serve: the
    # caller signed in earlier and now wants to use that session without any chance of a prompt.
    # The cookie is placed straight on the module's session context rather than written to disk, so
    # the test neither depends on nor disturbs the user's real encrypted cookie cache.
    function Set-SeededSession {
        param(
            [Parameter(Mandatory)]
            [string]$SessionKey
        )

        $Key = "{0}::webview2::{1}" -f "127.0.0.1:$Script:Port", $SessionKey
        InModuleScope 'OmadaWeb.PS' -Parameters @{ Key = $Key } {
            param($Key)
            $SessionContext = Get-OmadaSessionContext -Key $Key
            $SessionContext.AuthCookie = [PSCustomObject]@{ Name = 'oisauthtoken'; Value = 'seeded-session-value'; domain = '127.0.0.1' }
        }
    }

    function Reset-FakeServer {
        param(
            [int]$Status = 200
        )
        $Script:SharedServer.ResponseStatus = $Status
        $Script:SharedServer.RequestCount = 0
        $Script:SharedServer.CookiesSeen.Clear()
    }
}

Describe 'Invoke-TestOmadaRestMethod -NoInteractiveAuthentication' -Tag 'Integration' {
    BeforeEach {
        # Both browser engines are mocked so that a regression could only ever be observed as a
        # counted invocation here - never as a real Edge window opening on the machine running the
        # suite, and never as a WebView2 runtime error on an agent that has no desktop.
        Mock Get-DataFromWebView2 -ModuleName 'OmadaWeb.PS' {}
        Mock Get-DataFromWebDriver -ModuleName 'OmadaWeb.PS' {}
    }

    Context 'A live session' {
        It 'Should send the existing session cookie and return the response' {
            Reset-FakeServer -Status 200
            Set-SeededSession -SessionKey 'live-session'

            $Result = Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType WebView2 -SessionKey 'live-session' -SkipCookieCache -NoInteractiveAuthentication

            $Result.value | Should -Be 'served'
            $Script:SharedServer.CookiesSeen[0] | Should -BeLike '*oisauthtoken=seeded-session-value*'
            Should -Invoke Get-DataFromWebView2 -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly
            Should -Invoke Get-DataFromWebDriver -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly
        }
    }

    Context 'An expired session' {
        It 'Should not attempt re-authentication when the server answers 401' {
            # The acceptance criterion of issue #84. Without the switch this 401 is exactly the
            # condition that sends Invoke-OmadaRequest into Get-DataFromWebView2 and puts a sign-in
            # window on the screen.
            Reset-FakeServer -Status 401
            Set-SeededSession -SessionKey 'expired-session'

            $Failure = { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType WebView2 -SessionKey 'expired-session' -SkipCookieCache -NoInteractiveAuthentication -ErrorAction Stop } |
                Should -Throw -PassThru

            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'
            $Failure.Exception | Should -BeOfType [System.Security.Authentication.AuthenticationException]

            Should -Invoke Get-DataFromWebView2 -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly
            Should -Invoke Get-DataFromWebDriver -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly

            # One request and no more: the call neither retried the 401 nor replayed it after a
            # re-authentication that did not happen.
            $Script:SharedServer.RequestCount | Should -Be 1
        }

        It 'Should drop the rejected session so a later interactive call signs in cleanly' {
            Reset-FakeServer -Status 401
            Set-SeededSession -SessionKey 'dropped-session'

            { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType WebView2 -SessionKey 'dropped-session' -SkipCookieCache -NoInteractiveAuthentication -ErrorAction Stop } | Should -Throw

            $Key = "{0}::webview2::dropped-session" -f "127.0.0.1:$Script:Port"
            $RemainingCookie = InModuleScope 'OmadaWeb.PS' -Parameters @{ Key = $Key } {
                param($Key)
                (Get-OmadaSessionContext -Key $Key).AuthCookie
            }

            $RemainingCookie | Should -BeNullOrEmpty
        }
    }

    Context 'A session that was never established' {
        It 'Should fail with the same error rather than opening a sign-in' {
            Reset-FakeServer -Status 200

            $Failure = { Invoke-TestOmadaRestMethod -Uri "$Script:BaseUrl/data" -AuthenticationType WebView2 -SessionKey 'never-established' -SkipCookieCache -NoInteractiveAuthentication -ErrorAction Stop } |
                Should -Throw -PassThru

            $Failure.FullyQualifiedErrorId | Should -BeLike 'OmadaSessionExpired*'

            Should -Invoke Get-DataFromWebView2 -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly
            Should -Invoke Get-DataFromWebDriver -ModuleName 'OmadaWeb.PS' -Times 0 -Exactly

            # The request under test was never sent: the refusal happens while the session is being
            # assembled, before any call to the endpoint. RequestCount deliberately excludes the
            # startup and environment-suspension probes, so this says nothing about those - only
            # that no request for /data went out.
            $Script:SharedServer.RequestCount | Should -Be 0
        }
    }
}

AfterAll {
    if ($Script:SharedServer.Listener) {
        $Script:SharedServer.Listener.Stop()
        $Script:SharedServer.Listener.Close()
    }
    if ($Script:ServerJob) {
        $Script:ServerJob | Stop-Job -PassThru | Remove-Job
    }
    Get-Module OmadaWeb.PS | ForEach-Object { $_ | Remove-Module -Force -ErrorAction SilentlyContinue }
}
