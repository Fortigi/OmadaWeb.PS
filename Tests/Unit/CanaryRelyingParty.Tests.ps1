[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ModulePath', Justification = 'Declared so the container -Data the build passes to every test file binds. Genuinely unused: these tests cover the canary scaffolding, which is not part of the module.')]
param(
    # Accepted and unused. The build hands every container the same -Data, and a test file whose
    # param block rejects it fails to discover at all. Nothing here needs the module: the relying
    # party is scaffolding for the canary, not part of OmadaWeb.PS.
    [string]$ModulePath = (Join-Path $(Split-Path $(Split-Path $PSScriptRoot)) -ChildPath 'OmadaWeb.PS\OmadaWeb.PS.psm1')
)

BeforeAll {
    . (Join-Path (Split-Path $PSScriptRoot) -ChildPath 'E2E\Start-CanaryRelyingParty.ps1')

    # Every request below goes through HttpClient rather than Invoke-WebRequest. The two things
    # these tests need most - reading a 302 without following it, and reading a Set-Cookie header -
    # are spelled differently on Windows PowerShell 5.1 and PowerShell 7 (-MaximumRedirection 0
    # throws on 5.1, and -SkipHttpErrorCheck needs 7.4+), and PR Validation runs both editions.
    if ($PSVersionTable.PSEdition -eq "Desktop") {
        Add-Type -AssemblyName System.Net.Http
    }

    function Invoke-CanaryRequest {
        param(
            [Parameter(Mandatory)]
            [string]$Uri,

            [switch]$FollowRedirect
        )

        $Handler = [System.Net.Http.HttpClientHandler]::new()
        $Handler.AllowAutoRedirect = [bool]$FollowRedirect
        $Handler.UseCookies = $false
        $Client = [System.Net.Http.HttpClient]::new($Handler)
        try {
            $Client.Timeout = [System.TimeSpan]::FromSeconds(15)
            $Response = $Client.GetAsync($Uri).GetAwaiter().GetResult()
            try {
                $Location = $null
                if ($null -ne $Response.Headers.Location) {
                    $Location = $Response.Headers.Location.OriginalString
                }

                $SetCookie = @()
                $CookieValues = $null
                if ($Response.Headers.TryGetValues("Set-Cookie", [ref]$CookieValues)) {
                    $SetCookie = @($CookieValues)
                }

                return [pscustomobject]@{
                    StatusCode = [int]$Response.StatusCode
                    Location   = $Location
                    SetCookie  = $SetCookie
                    Content    = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                }
            }
            finally {
                $Response.Dispose()
            }
        }
        finally {
            $Client.Dispose()
        }
    }

    function Get-CanaryQueryParameter {
        # [System.Web.HttpUtility] lives in a different assembly on each edition, and asking for the
        # wrong one is a load failure rather than a test failure. Splitting the query is cheaper than
        # being right about that on both.
        param(
            [Parameter(Mandatory)]
            [string]$Uri
        )

        $Query = ([System.Uri]::new($Uri)).Query.TrimStart("?")
        $Parameter = @{}
        foreach ($Pair in $Query.Split("&")) {
            if ([string]::IsNullOrWhiteSpace($Pair)) {
                continue
            }

            $Separator = $Pair.IndexOf("=")
            if ($Separator -lt 0) {
                $Parameter[[System.Uri]::UnescapeDataString($Pair)] = ""
                continue
            }

            $Name = [System.Uri]::UnescapeDataString($Pair.Substring(0, $Separator))
            $Parameter[$Name] = [System.Uri]::UnescapeDataString($Pair.Substring($Separator + 1))
        }

        return $Parameter
    }
}

Describe 'New-CanaryPkcePair' -Tag 'Unit' {

    It 'Returns a verifier and a challenge that are base64url, not base64' {
        $Pair = New-CanaryPkcePair

        $Pair.Verifier | Should -Not -Match '[+/=]'
        $Pair.Challenge | Should -Not -Match '[+/=]'
    }

    It 'Returns a verifier inside the length RFC 7636 allows' {
        $Pair = New-CanaryPkcePair

        $Pair.Verifier.Length | Should -BeGreaterOrEqual 43
        $Pair.Verifier.Length | Should -BeLessOrEqual 128
    }

    It 'Derives the challenge as base64url of SHA-256 over the ASCII verifier' {
        $Pair = New-CanaryPkcePair

        $Sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $Expected = [Convert]::ToBase64String($Sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($Pair.Verifier)))
        }
        finally {
            $Sha256.Dispose()
        }

        $Pair.Challenge | Should -Be $Expected.Replace("+", "-").Replace("/", "_").TrimEnd("=")
    }

    It 'Returns a different verifier on every call' {
        $First = New-CanaryPkcePair
        $Second = New-CanaryPkcePair

        $First.Verifier | Should -Not -Be $Second.Verifier
    }
}

Describe 'New-CanaryAuthorizeUri' -Tag 'Unit' {

    BeforeAll {
        $Script:AuthorizeParameter = @{
            TenantId      = "11111111-1111-1111-1111-111111111111"
            ClientId      = "22222222-2222-2222-2222-222222222222"
            RedirectUri   = "http://localhost:8400/canary"
            CodeChallenge = "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"
            State         = "0123456789abcdef"
            LoginHint     = "canary@example.onmicrosoft.com"
        }
    }

    It 'Targets the tenant-specific v2.0 authorize endpoint' {
        $Uri = New-CanaryAuthorizeUri @Script:AuthorizeParameter

        $Uri | Should -BeLike "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/oauth2/v2.0/authorize?*"
    }

    It 'Produces a URI the framework can parse' {
        $Uri = New-CanaryAuthorizeUri @Script:AuthorizeParameter

        { [System.Uri]::new($Uri) } | Should -Not -Throw
    }

    It 'Requests an authorization code delivered to the loopback redirect URI' {
        $Query = Get-CanaryQueryParameter -Uri (New-CanaryAuthorizeUri @Script:AuthorizeParameter)

        $Query["response_type"] | Should -Be "code"
        $Query["response_mode"] | Should -Be "query"
        $Query["redirect_uri"] | Should -Be "http://localhost:8400/canary"
    }

    It 'Forces the sign-in screens to be rendered' {
        # Without prompt=login a warm profile is waved straight through, the screens under test are
        # never drawn, and the canary passes by testing nothing.
        $Query = Get-CanaryQueryParameter -Uri (New-CanaryAuthorizeUri @Script:AuthorizeParameter)

        $Query["prompt"] | Should -Be "login"
    }

    It 'Sends the PKCE challenge with its method' {
        $Query = Get-CanaryQueryParameter -Uri (New-CanaryAuthorizeUri @Script:AuthorizeParameter)

        $Query["code_challenge"] | Should -Be $Script:AuthorizeParameter.CodeChallenge
        $Query["code_challenge_method"] | Should -Be "S256"
    }

    It 'Escapes a login hint that contains characters with a meaning in a query string' {
        $Parameter = $Script:AuthorizeParameter.Clone()
        $Parameter.LoginHint = "canary+test@example.onmicrosoft.com"

        $Uri = New-CanaryAuthorizeUri @Parameter

        # A raw '+' in a query string decodes to a space, which would send Entra a different account.
        $Uri | Should -Not -Match 'login_hint=canary\+test'
        (Get-CanaryQueryParameter -Uri $Uri)["login_hint"] | Should -Be "canary+test@example.onmicrosoft.com"
    }

    It 'Omits the login hint when none was supplied' {
        $Parameter = $Script:AuthorizeParameter.Clone()
        $Parameter.LoginHint = ""

        New-CanaryAuthorizeUri @Parameter | Should -Not -Match 'login_hint'
    }

    It 'Does not carry the code verifier' {
        # Only the challenge may travel in the front channel; the verifier is the secret half.
        $Pair = New-CanaryPkcePair
        $Parameter = $Script:AuthorizeParameter.Clone()
        $Parameter.CodeChallenge = $Pair.Challenge

        New-CanaryAuthorizeUri @Parameter | Should -Not -Match ([regex]::Escape($Pair.Verifier))
    }
}

Describe 'New-CanarySetCookieHeader' -Tag 'Unit' {

    It 'Names the cookie Get-WebView2Cookie waits for' {
        New-CanarySetCookieHeader -Name "oisauthtoken" -Value "abc" | Should -BeLike "oisauthtoken=abc;*"
    }

    It 'Omits Domain so the cookie is host-only' {
        # A Domain of 'localhost' is rejected by parts of the cookie stack. Host-only still satisfies
        # the suffix match Get-WebView2Cookie applies against the BaseUrl host.
        New-CanarySetCookieHeader -Name "oisauthtoken" -Value "abc" | Should -Not -Match 'Domain='
    }

    It 'Omits Secure so a plain-HTTP loopback response is not dropped' {
        New-CanarySetCookieHeader -Name "oisauthtoken" -Value "abc" | Should -Not -Match '(^|;\s*)Secure(\s*;|$)'
    }

    It 'Applies to the whole site' {
        New-CanarySetCookieHeader -Name "oisauthtoken" -Value "abc" | Should -Match 'Path=/'
    }
}

Describe 'Start-CanaryRelyingParty' -Tag 'Unit' {

    BeforeAll {
        $Script:Port = Get-Random -Minimum 21000 -Maximum 23000
        $Script:RelyingParty = Start-CanaryRelyingParty -TenantId "11111111-1111-1111-1111-111111111111" -ClientId "22222222-2222-2222-2222-222222222222" -LoginHint "canary@example.onmicrosoft.com" -Port $Script:Port
    }

    AfterAll {
        Stop-CanaryRelyingParty -RelyingParty $Script:RelyingParty
    }

    It 'Redirects an unauthenticated request to the Entra authorization endpoint' {
        $Response = Invoke-CanaryRequest -Uri $Script:RelyingParty.BaseUrl

        $Response.StatusCode | Should -Be 302
        $Response.Location | Should -BeLike "https://login.microsoftonline.com/*"
    }

    It 'Keeps redirecting, because the environment probe spends the first one' {
        # Test-EnvironmentSuspended fetches the BaseUrl with its own redirect-following client before
        # the browser ever opens. A listener that redirected only once would have nothing left to
        # send the browser.
        foreach ($Attempt in 1..3) {
            (Invoke-CanaryRequest -Uri $Script:RelyingParty.BaseUrl).StatusCode | Should -Be 302
        }
    }

    It 'Sets the session cookie when Entra hands the browser back' {
        $Uri = "{0}?code=fake-code&state={1}" -f $Script:RelyingParty.RedirectUri, $Script:RelyingParty.ExpectedState
        $Response = Invoke-CanaryRequest -Uri $Uri

        $Response.StatusCode | Should -Be 200
        ($Response.SetCookie -join ";") | Should -Match 'oisauthtoken='
        $Script:RelyingParty.CallbackError | Should -BeNullOrEmpty
    }

    It 'Counts the redirect so a canary cannot pass without a real round trip through Entra' {
        $Script:RelyingParty.RedirectHitCount | Should -BeGreaterThan 0
    }

    It 'Serves a callback page that the Omada logon-error scraper reads as clean' {
        # Get-OmadaLogonErrorScript sweeps the body for anything carrying an error severity whenever
        # the path looks like a logon page, and reports a match as a refused sign-in.
        $Uri = "{0}?code=fake-code&state={1}" -f $Script:RelyingParty.RedirectUri, $Script:RelyingParty.ExpectedState
        $Response = Invoke-CanaryRequest -Uri $Uri

        $Script:RelyingParty.RedirectPath | Should -Not -Match 'logon|login|signin|sign-in|error'
        $Response.Content | Should -Not -Match 'class\s*=\s*"[^"]*error'
        $Response.Content | Should -Not -Match 'role\s*=\s*"alert"'
    }

    It 'Reports a state mismatch rather than treating the callback as a success' {
        $Uri = "{0}?code=fake-code&state=not-the-state-we-sent" -f $Script:RelyingParty.RedirectUri
        $null = Invoke-CanaryRequest -Uri $Uri

        $Script:RelyingParty.CallbackError | Should -Be "state_mismatch"
        $Script:RelyingParty.CallbackError = $null
    }

    It 'Records the error code when Entra refuses the sign-in' {
        $Uri = "{0}?error=access_denied&error_description=names-the-account&state={1}" -f $Script:RelyingParty.RedirectUri, $Script:RelyingParty.ExpectedState
        $null = Invoke-CanaryRequest -Uri $Uri

        $Script:RelyingParty.CallbackError | Should -Be "access_denied"
    }

    It 'Does not keep the error description, which can name the account and the tenant' {
        # A failing canary reports this value into a public issue.
        $Script:RelyingParty.CallbackError | Should -Not -Match 'names-the-account'
    }

    It 'Serves the resource the module requests once it holds the cookie' {
        $Response = Invoke-CanaryRequest -Uri $Script:RelyingParty.ResourceUrl

        $Response.StatusCode | Should -Be 200
        ($Response.Content | ConvertFrom-Json).canary | Should -Be "ok"
    }

    It 'Survives a client that abandons its request' {
        # The browser abandons requests routinely while it navigates; one of those must not take the
        # listener down and strand the sign-in window.
        $Client = [System.Net.Http.HttpClient]::new()
        try {
            $CancellationSource = [System.Threading.CancellationTokenSource]::new([System.TimeSpan]::FromMilliseconds(1))
            try {
                $null = $Client.GetAsync($Script:RelyingParty.ResourceUrl, $CancellationSource.Token).GetAwaiter().GetResult()
            }
            catch {
                $null = $_
            }
            finally {
                $CancellationSource.Dispose()
            }
        }
        finally {
            $Client.Dispose()
        }

        (Invoke-CanaryRequest -Uri $Script:RelyingParty.ResourceUrl).StatusCode | Should -Be 200
        $Script:RelyingParty.ListenerError | Should -BeNullOrEmpty
    }
}
